#!/usr/bin/env python3
"""Validate bilingual notes and render only changes since a published release."""

import argparse
from pathlib import Path
import re
import subprocess
import sys
import unicodedata


ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = "release-notes"
README = f"{DIRECTORY}/README.md"
NAME = re.compile(r"release-notes/[a-z0-9]+(?:-[a-z0-9]+)*\.md")
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
HEADINGS = ("## 日本語", "## English")
MAX_BYTES = 8192


class NotesError(ValueError):
    pass


def git(root, *args):
    result = subprocess.run(
        ["git", "--no-replace-objects", *args], cwd=root,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    if result.returncode:
        raise NotesError(result.stderr.decode("utf-8", errors="replace").strip()
                         or f"git {args[0]} failed")
    return result.stdout


def parse_note(data, name):
    if len(data) > MAX_BYTES:
        raise NotesError(f"{name}: notes must be at most {MAX_BYTES} bytes")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise NotesError(f"{name}: notes must be UTF-8") from error
    if any(unicodedata.category(c) in ("Cc", "Cf") and c != "\n" for c in text):
        raise NotesError(f"{name}: use plain UTF-8 text and LF line endings")

    sections = [[], []]
    section = -1
    for line in text.splitlines():
        if not line:
            continue
        if section + 1 < len(HEADINGS) and line == HEADINGS[section + 1]:
            section += 1
            continue
        if section < 0 or not line.startswith("- ") or not line[2:].strip():
            raise NotesError(f"{name}: use 日本語 then English headings and one-line '- ' bullets")
        bullet = line[2:]
        if bullet != bullet.strip() or "<" in bullet or ">" in bullet:
            raise NotesError(f"{name}: remove extra whitespace and HTML/placeholders")
        if re.search(r"\b(?:TODO|TBD|FIXME)\b", bullet, re.IGNORECASE) or bullet in ("...", "…"):
            raise NotesError(f"{name}: replace draft placeholders before release")
        sections[section].append(bullet)

    if not 1 <= len(sections[0]) <= 5 or len(sections[0]) != len(sections[1]):
        raise NotesError(f"{name}: each language needs the same 1–5 translated bullets")
    return sections


def check(root):
    directory = root / DIRECTORY
    if not directory.is_dir() or directory.is_symlink():
        raise NotesError("release-notes must be a directory")
    count = 0
    for path in sorted(directory.iterdir()):
        name = path.relative_to(root).as_posix()
        if name == README:
            continue
        if not NAME.fullmatch(name) or not path.is_file() or path.is_symlink():
            raise NotesError(f"Invalid note path: {name!r}")
        parse_note(path.read_bytes(), name)
        count += 1
    if not count:
        raise NotesError("No release notes found")
    return count


def release_version(root, revision="HEAD"):
    if git(root, "rev-parse", "--is-shallow-repository").strip() != b"false":
        raise NotesError("Release notes require full git history (fetch-depth: 0)")
    project = git(root, "show", f"{revision}:project.yml").decode("utf-8")
    values = re.findall(r"^\s*MARKETING_VERSION:\s*\"(" + VERSION + r")\"\s*$", project, re.MULTILINE)
    if len(values) != 1:
        raise NotesError("project.yml must define one quoted MARKETING_VERSION")
    base = values[0].rsplit(".", 1)[0]
    build = git(root, "rev-list", "--count", revision).decode("ascii").strip()
    return f"{base}.{build}"


def tree(root, revision):
    notes = {}
    for entry in git(root, "ls-tree", "-r", "-z", revision, "--", DIRECTORY).split(b"\0"):
        if not entry:
            continue
        metadata, raw_name = entry.split(b"\t", 1)
        name = raw_name.decode("utf-8")
        if name == README:
            continue
        mode, kind, object_id = metadata.split()
        if not NAME.fullmatch(name) or mode != b"100644" or kind != b"blob":
            raise NotesError(f"Invalid committed note path or mode: {name!r}")
        notes[name] = object_id.decode("ascii")
    return notes


def render(root, since, version):
    if not re.fullmatch("v" + VERSION, since):
        raise NotesError("--since must be the latest published release tag, e.g. v0.1.27")
    head = git(root, "rev-parse", "HEAD").decode("ascii").strip()
    expected = release_version(root, head)
    if version != expected:
        raise NotesError(f"Version mismatch: this commit releases {expected}, not {version!r}")
    try:
        previous = git(root, "rev-parse", "--verify", f"refs/tags/{since}^{{commit}}").decode("ascii").strip()
    except NotesError as error:
        raise NotesError(f"Missing {since}; fetch the published release tag before rendering") from error
    try:
        git(root, "merge-base", "--is-ancestor", previous, head)
    except NotesError as error:
        raise NotesError(f"{since} is not an ancestor of the release commit") from error
    if tuple(map(int, version.split("."))) <= tuple(map(int, since[1:].split("."))):
        raise NotesError("Release version must be newer than the published release")

    old, current = tree(root, previous), tree(root, head)
    for name, object_id in old.items():
        if current.get(name) != object_id:
            raise NotesError(f"Published note was changed or removed: {name}; add a new note instead")
    added = sorted(current.keys() - old.keys())
    if not added:
        raise NotesError(f"No new release notes since {since}; add a bilingual note or use [skip release]")
    sections = [[], []]
    for name in added:
        parsed = parse_note(git(root, "cat-file", "blob", current[name]), name)
        for combined, bullets in zip(sections, parsed):
            combined.extend(bullets)
    return "\n\n".join(
        heading + "\n\n" + "\n".join("- " + bullet for bullet in bullets)
        for heading, bullets in zip(HEADINGS, sections)
    ) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check", help="lint working-tree notes, including drafts")
    commands.add_parser("version", help="print the committed source's release version")
    command = commands.add_parser("render", help="render committed notes since the latest published tag")
    command.add_argument("--since", required=True)
    command.add_argument("--version", required=True)
    args = parser.parse_args()
    try:
        if args.command == "check":
            print(f"Release notes OK: {check(ROOT)} file(s)")
        elif args.command == "version":
            print(release_version(ROOT))
        else:
            sys.stdout.write(render(ROOT, args.since, args.version))
    except (NotesError, OSError, UnicodeError, subprocess.TimeoutExpired) as error:
        print(f"release-notes: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
