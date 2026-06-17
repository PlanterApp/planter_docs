# import_doc.dart

Imports a screen-recording doc into the Hugo site as a page
bundle, handling images and the video placeholder.

## Exporting from the Google Doc

The Markdown export **downsamples screenshots**, so export the Doc **twice** into
the same folder (`File > Download`):

- **Markdown (.md)** — used for the text/structure.
- **Microsoft Word (.docx)** — used for the **full-resolution** images.

Give the two files the same base name (e.g. `combine-beds.md` + `combine-beds.docx`)
and move them to the `planter_docs` repo root.

```sh
# .docx auto-detected as the sibling of the .md:
dart run tool/import_doc.dart combine-beds.md
# or point at it explicitly:
dart run tool/import_doc.dart combine-beds.md --docx combine-beds.docx
```

If no `.docx` is found it falls back to the Markdown's low-res base64 images and
warns. It then prompts for the target section, slug, weight, URL, description,
and the recording (see below), and writes
`content/docs/<section>/<NNN_slug>/index.md` plus one sibling `.webp` per
screenshot.

- **Section** is chosen from an arrow-key menu (↑/↓ or j/k, Enter to confirm).
  With piped/non-interactive input it falls back to a typed prompt.
- **Slug** defaults from the file name with its leading number dropped
  (`3. Combine Multiple Garden Beds.md` → `combine-multiple-garden-beds`); the
  page title comes from the doc's `# H1` heading. Both are editable at the prompt.
- **Folder-number collisions:** if the chosen `NNN` prefix is already taken, you
  pick **Insert** (renumber that folder and every higher one `+1`, bumping their
  `weight`) or **Replace** (delete the occupying folder and take its place).
- **Recording:** when the doc has `<<EMBED RECORDING>>`, it asks you to **select
  the recording video** via a native file picker (macOS/Windows/Linux). Download
  the clip from the Whale card first (select the video → gear → **Download**).
  The picked file is transcoded to a small `recording.mp4` in the bundle and
  embedded with `{{< video >}}` (click-to-play, ~10× smaller than a GIF). Skip the
  picker to fall back to a YouTube id, or pass `--video <file>` to bypass it.
- **Git:** at the end it offers to `git add` the new bundle (and any folders the
  insert/replace step renamed or deleted).

Images are matched MD↔DOCX by document order; both come from the same Doc, so the
order is identical (the tool warns if the counts differ).

What it converts:

- base64 reference images (`![Alt][image1]` + `[image1]: <data:image/png;base64,…>`)
  → `{{< screenshot NN-alt-slug.webp "Alt" >}}` with the PNG decoded and
  re-encoded to WebP.
- `<<EMBED RECORDING>>` → a self-hosted `{{< video >}}` (if you select a
  recording), else `{{< youtube ID >}}`, else a visible `<!-- TODO -->`.
- Google-Docs escaping noise (`\!`, `\.`, `\<\<` …) is stripped from prose.

## convert_video.dart (standalone)

The video conversion is also usable on its own — handy for recompressing any clip
(or an old `.gif`) without running a full import:

```sh
dart run tool/convert_video.dart [input] [output.mp4]
# no input → opens the native file picker
# default output → "<input-stem>-web.mp4" next to the input
```

It downscales to ≤480px wide and encodes H.264 (CRF 30, faststart), keeping audio
only if the source has it. Example: a 4.9 MB GIF → ~250 KB MP4 (95% smaller).

## Requirements & platforms

Runs on **macOS and Windows** (and Linux). Dependencies on `PATH`:

- `cwebp` — image → WebP. macOS: `brew install webp`. Windows: `winget install Google.libwebp` (or scoop/choco).
- `tar` (preferred) or `unzip` — read the `.docx`. Ships with macOS and Windows 10+ (`tar`).
- `ffmpeg` + `ffprobe` — only when self-hosting a recording. macOS: `brew install ffmpeg`. Windows: `winget install Gyan.FFmpeg`.
- `git` — optional, for the staging prompt.
- Dart SDK.

Run it from the repo root. On Windows use **Windows Terminal** (or Windows 10+)
so the arrow-key section menu renders; otherwise the typed fallback still works.

Review the generated `index.md` before committing — alt text comes from the
recording tool and may need polish, and (if you skipped the video) the recording
TODO needs a real video id.
