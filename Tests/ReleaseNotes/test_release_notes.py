import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/release-notes.py"
spec = importlib.util.spec_from_file_location("release_notes", SCRIPT)
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)

VALID = "## 日本語\n\n- 起動時の問題を修正しました。\n\n## English\n\n- Fixed a startup issue.\n"
SECOND = "## 日本語\n\n- 画像の保存を修正しました。\n\n## English\n\n- Fixed image saving.\n"


class FormatTests(unittest.TestCase):
    def test_valid_bilingual_note(self):
        self.assertEqual(notes.parse_note(VALID.encode(), "test"), [
            ["起動時の問題を修正しました。"], ["Fixed a startup issue."],
        ])

    def test_invalid_formats(self):
        cases = {
            "empty": "",
            "missing_english": VALID.split("## English")[0],
            "missing_japanese": VALID.split("## English")[1],
            "duplicate_heading": VALID + "\n## English\n\n- Again.\n",
            "wrong_order": VALID.replace("## 日本語", "## English", 1),
            "mismatched_bullets": VALID + "- Another change.\n",
            "empty_bullet": VALID.replace("- Fixed a startup issue.", "- "),
            "empty_section": VALID.replace("- 起動時の問題を修正しました。", ""),
            "trailing_space": VALID.replace("issue.", "issue. "),
            "multiline_bullet": VALID + "  More text.\n",
            "html": VALID.replace("issue.", "<b>issue.</b>"),
            "todo": VALID.replace("issue.", "TODO"),
            "tbd": VALID.replace("issue.", "tbd"),
            "ellipsis": VALID.replace("Fixed a startup issue.", "…"),
            "crlf": VALID.replace("\n", "\r\n"),
            "control": VALID + "\x1b",
            "bidi": VALID.replace("issue.", "\u202eissue."),
            "bom": "\ufeff" + VALID,
            "too_many": "## 日本語\n" + "- 修正しました。\n" * 6 + "## English\n" + "- Fixed.\n" * 6,
        }
        for label, data in cases.items():
            with self.subTest(label=label), self.assertRaises(notes.NotesError):
                notes.parse_note(data.encode(), label)

    def test_bad_encoding_and_size(self):
        for data in (b"\xff", b"x" * (notes.MAX_BYTES + 1)):
            with self.subTest(data_length=len(data)), self.assertRaises(notes.NotesError):
                notes.parse_note(data, "test")


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ttemp-notes-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.run_git("-c", "init.templateDir=", "init", "-q")
        self.run_git("config", "user.name", "Ttemp tests")
        self.run_git("config", "user.email", "tests@example.invalid")
        self.run_git("config", "core.hooksPath", os.devnull)
        self.run_git("config", "commit.gpgsign", "false")
        self.run_git("config", "tag.gpgsign", "false")
        self.write("project.yml", 'settings:\n  base:\n    MARKETING_VERSION: "0.1.0"\n')
        self.commit()
        self.run_git("tag", "v0.1.1")

    def run_git(self, *args, cwd=None):
        result = subprocess.run(
            ["git", *args], cwd=cwd or self.root, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
        )
        return result.stdout.decode().strip()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def commit(self):
        self.run_git("add", "-A")
        self.run_git("commit", "-qm", "Fixture change")

    def add_note(self, name="startup", text=VALID):
        return self.write(f"release-notes/{name}.md", text)

    def render(self, since="v0.1.1", version=None):
        return notes.render(self.root, since, version or notes.release_version(self.root))

    def prepare_build(self, with_note=True):
        scripts = self.root / "scripts"
        scripts.mkdir()
        shutil.copyfile(SCRIPT, scripts / SCRIPT.name)
        shutil.copyfile(SCRIPT.with_name("build-release.sh"), scripts / "build-release.sh")
        if with_note:
            self.add_note()
        # Stop at the signing boundary. These tests never access a real keychain,
        # invoke Xcode, or publish anything, even when valid notes pass preflight.
        tools = self.root / "test-tools"
        tools.mkdir()
        guard = self.write("test-tools/security", "#!/bin/bash\nprintf '%s\\n' SIGNING_REACHED >&2\nexit 1\n")
        guard.chmod(0o755)
        self.commit()

    def run_build(self, previous="v0.1.1", version=None, build=None):
        env = {key: value for key, value in os.environ.items() if not key.startswith("TTEMP_")}
        env["PATH"] = str(self.root / "test-tools") + os.pathsep + env["PATH"]
        if previous is not None:
            env["TTEMP_PREVIOUS_RELEASE"] = previous
        if version is not None:
            env["TTEMP_VERSION"] = version
        if build is not None:
            env["TTEMP_BUILD"] = build
        return subprocess.run(
            ["/bin/bash", str(self.root / "scripts/build-release.sh")], cwd=self.root,
            env=env, capture_output=True, text=True, timeout=30,
        )

    def test_build_rejects_missing_previous_release_before_signing(self):
        self.prepare_build()
        result = self.run_build(previous=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("TTEMP_PREVIOUS_RELEASE", result.stderr)
        self.assertNotIn("SIGNING_REACHED", result.stderr)

    def test_build_rejects_missing_notes_before_signing(self):
        self.prepare_build(with_note=False)
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No new release notes", result.stderr)
        self.assertNotIn("SIGNING_REACHED", result.stderr)

    def test_build_rejects_mismatched_version_and_build_before_signing(self):
        self.prepare_build()
        for version, build in (("0.1.3", "3"), ("0.1.2", "3")):
            with self.subTest(version=version, build=build):
                result = self.run_build(version=version, build=build)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("SIGNING_REACHED", result.stderr)
                self.assertTrue("Version mismatch" in result.stderr or "TTEMP_BUILD" in result.stderr)

    def test_build_rejects_uncommitted_notes_before_signing(self):
        self.prepare_build()
        self.add_note(text=SECOND)
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("未コミット変更", result.stderr)
        self.assertNotIn("SIGNING_REACHED", result.stderr)

    def test_build_with_valid_notes_reaches_signing(self):
        self.prepare_build()
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)  # The fake keychain deliberately stops here.
        self.assertIn("SIGNING_REACHED", result.stderr)
        self.assertNotIn("release-notes:", result.stderr)

    def test_new_notes_are_rendered_exactly(self):
        self.add_note()
        self.commit()
        self.assertEqual(self.render(), VALID)
        self.assertEqual(notes.release_version(self.root), "0.1.2")

    def test_all_pending_notes_group_by_language_in_filename_order(self):
        self.add_note("z-startup")
        self.add_note("a-images", SECOND)
        self.commit()
        output = self.render()
        self.assertEqual(output.count("## 日本語"), 1)
        self.assertEqual(output.count("## English"), 1)
        self.assertLess(output.index("画像の保存"), output.index("起動時の問題"))
        self.assertLess(output.index("起動時の問題"), output.index("## English"))
        self.assertLess(output.index("Fixed image"), output.index("Fixed a startup"))

    def test_no_new_notes_fails_even_with_new_code(self):
        self.write("source.txt", "new code")
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "No new release notes"):
            self.render()

    def test_readme_alone_is_not_release_notes(self):
        self.write("release-notes/README.md", "How to write notes")
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "No new release notes"):
            self.render()

    def test_published_notes_are_not_reused(self):
        self.add_note()
        self.commit()
        self.run_git("tag", "v0.1.2")
        self.add_note("images", SECOND)
        self.commit()
        self.assertEqual(self.render(since="v0.1.2"), SECOND)

    def test_modifying_deleting_or_renaming_published_notes_fails(self):
        path = self.add_note()
        self.commit()
        self.run_git("tag", "v0.1.2")
        self.add_note("images", SECOND)
        path.write_text(SECOND, encoding="utf-8")
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "Published note was changed"):
            self.render(since="v0.1.2")
        path.rename(path.with_name("renamed.md"))
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "Published note was changed"):
            self.render(since="v0.1.2")
        path.with_name("renamed.md").unlink()
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "Published note was changed"):
            self.render(since="v0.1.2")

    def test_unpublished_notes_may_be_edited(self):
        path = self.add_note()
        self.commit()
        path.write_text(SECOND, encoding="utf-8")
        self.commit()
        self.assertEqual(self.render(), SECOND)

    def test_render_uses_committed_content_only(self):
        path = self.add_note()
        self.commit()
        path.write_text("Not committed", encoding="utf-8")
        self.add_note("untracked", SECOND)
        self.assertEqual(self.render(), VALID)

    def test_bad_version_fails(self):
        self.add_note()
        self.commit()
        for version in ("0.1.1", "0.1.3", "1.0.0", "v0.1.2", "0.1.2\nextra", "0.1.02"):
            with self.subTest(version=version), self.assertRaisesRegex(notes.NotesError, "Version mismatch"):
                self.render(version=version)

    def test_bad_previous_tag_fails(self):
        self.add_note()
        self.commit()
        for tag in ("--help", "HEAD", "v01.1.1", "v0.1.1\n", "v0.1.1;echo nope"):
            with self.subTest(tag=tag), self.assertRaisesRegex(notes.NotesError, "--since"):
                self.render(since=tag)
        with self.assertRaisesRegex(notes.NotesError, "Missing v0.1.99"):
            self.render(since="v0.1.99")

    def test_unrelated_tag_fails(self):
        original = self.run_git("rev-parse", "HEAD")
        self.write("other.txt", "different history")
        self.commit()
        self.run_git("tag", "v0.1.2")
        self.run_git("checkout", "--detach", original)
        self.add_note()
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "not an ancestor"):
            self.render(since="v0.1.2")

    def test_downgrade_fails(self):
        self.run_git("tag", "v1.0.1")
        self.add_note()
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "must be newer"):
            self.render(since="v1.0.1")

    def test_annotated_published_tag_works(self):
        self.run_git("tag", "-a", "v0.1.0", "-m", "Published")
        self.add_note()
        self.commit()
        self.assertEqual(self.render(since="v0.1.0"), VALID)

    def test_merge_does_not_require_predicting_version(self):
        original = self.run_git("rev-parse", "HEAD")
        self.run_git("checkout", "-b", "notes-work")
        self.add_note()
        self.commit()
        self.assertEqual(notes.release_version(self.root), "0.1.2")
        self.run_git("checkout", "--detach", original)
        self.run_git("merge", "--no-ff", "notes-work", "-m", "Merge notes")
        self.assertEqual(notes.release_version(self.root), "0.1.3")
        self.assertEqual(self.render(), VALID)

    def test_minor_version_change_preserves_commit_count(self):
        self.write("project.yml", 'MARKETING_VERSION: "0.2.0"\n')
        self.add_note()
        self.commit()
        self.assertEqual(notes.release_version(self.root), "0.2.2")
        self.assertEqual(self.render(), VALID)

    def test_ambiguous_marketing_version_fails(self):
        self.write("project.yml", 'MARKETING_VERSION: "0.1.0"\nMARKETING_VERSION: "0.2.0"\n')
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "one quoted MARKETING_VERSION"):
            notes.release_version(self.root)

    def test_shallow_clone_fails(self):
        self.add_note()
        self.commit()
        clone = self.root / "shallow"
        self.run_git("clone", "--depth", "1", self.root.as_uri(), str(clone))
        with self.assertRaisesRegex(notes.NotesError, "full git history"):
            notes.release_version(clone)

    def test_invalid_committed_format_fails(self):
        self.add_note(text="## 日本語\n\n- 未完成\n")
        self.commit()
        with self.assertRaises(notes.NotesError):
            self.render()

    def test_symlink_and_nested_paths_fail(self):
        directory = self.root / "release-notes"
        directory.mkdir()
        (directory / "symlink.md").symlink_to("../project.yml")
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "Invalid committed note"):
            self.render()
        with self.assertRaisesRegex(notes.NotesError, "Invalid note path"):
            notes.check(self.root)
        (directory / "symlink.md").unlink()
        self.write("release-notes/nested/change.md", VALID)
        self.commit()
        with self.assertRaisesRegex(notes.NotesError, "Invalid committed note"):
            self.render()

    def test_working_tree_lint_includes_untracked_notes(self):
        self.add_note()
        self.write("release-notes/README.md", "Instructions, not a note")
        self.assertEqual(notes.check(self.root), 1)
        self.add_note("draft", "TODO")
        with self.assertRaises(notes.NotesError):
            notes.check(self.root)

    def test_cli_output_and_exit_status(self):
        self.add_note()
        script = self.root / "scripts/release-notes.py"
        script.parent.mkdir()
        shutil.copyfile(SCRIPT, script)
        self.commit()
        args = [sys.executable, "-B", str(script), "render", "--since", "v0.1.1", "--version"]
        result = subprocess.run(args + ["0.1.2"], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, VALID)
        result = subprocess.run(args + ["0.1.3"], capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("Version mismatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
