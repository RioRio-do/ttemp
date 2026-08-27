# Release notes

## 日本語

変更時に、新しい `short-lowercase-name.md` へ日英のノートを書く。名前は英小文字・数字・ハイフン、本文はUTF-8/LF。各言語1〜5項目、同じ内容・順番にし、ユーザーに関係する変更と必要な操作だけを簡潔に記す。

形式は [startup-and-images.md](startup-and-images.md) を参照。未公開のファイルは編集できる。公開済みのファイルは編集・削除・改名せず、訂正も新しいファイルへ書く。

CIは前回の公開tag以降に追加されたファイルだけをまとめ、採番後の `dist/release-notes-vX.Y.N.md` をGitHub Release本文へ掲載する。履歴はこのdirectoryと各公開tagに残る。番号をファイル名へ先取りする必要はない。

`python3 scripts/release-notes.py check` で形式を確認する。ノートなしの公開は失敗する。公開不要のpushは、最後のコミット件名を `[skip release]` で始める。

## English

For each change, add a new `short-lowercase-name.md` with matching Japanese and English notes. Use lowercase letters, digits, and hyphens in names, and UTF-8/LF for text. Use 1–5 bullets per language, in the same order. Include only user-facing changes and necessary actions.

See [startup-and-images.md](startup-and-images.md) for the format. Unpublished files may be edited. Never edit, delete, or rename published notes; put corrections in a new file.

CI combines only files added since the previous published tag, then publishes `dist/release-notes-vX.Y.N.md` as the GitHub Release body. History remains in this directory and each release tag. There is no need to predict a version before merging.

Run `python3 scripts/release-notes.py check` to validate the format. Publishing without new notes fails. To skip publishing, start the final push commit's subject with `[skip release]`.
