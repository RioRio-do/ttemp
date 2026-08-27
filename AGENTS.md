# Repository work

- Keep user-facing text minimal. Keep Japanese and English content equivalent.
- Update `SPEC.md` when behavior or the release pipeline changes; keep both READMEs aligned.
- Every release needs short, factual Japanese and English notes in `release-notes/`. Read its README before writing them. Review changes since the latest **published GitHub Release**, not merely the newest local tag. Include required user actions and known relevant limitations; do not claim unverified fixes.
- Add a new note file, or update an unpublished one. Never modify, rename, or remove published notes. Do not use generic placeholders or raw commit lists as release notes.
- Before finishing, run `python3 scripts/release-notes.py check` and `python3 -B -m unittest discover -s Tests/ReleaseNotes -v`. For a release, also render notes from the final committed source using the actual previous published tag; see `docs/SIGNING.md`.
- Keep the current `major.minor.<commit count>` numbering unless the user requests a policy change. Repository publication alone is not a reason to move to 1.x.
- Do not push, publish a Release, or replace an installed app without the user's authorization. Use disposable keys for release tests; never run `scripts/setup-release-keys.sh` merely to validate a build.
