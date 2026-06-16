# tool/

## import_doc.dart

Imports a screen-recording doc into the Hugo site as a page
bundle, handling images and the video placeholder.

### Exporting from the Google Doc

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
and an (optional) YouTube id, and writes
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
- **Git:** at the end it offers to `git add` the new bundle (and any folders the
  insert/replace step renamed or deleted).

Images are matched MD↔DOCX by document order; both come from the same Doc, so the
order is identical (the tool warns if the counts differ).

What it converts:

- base64 reference images (`![Alt][image1]` + `[image1]: <data:image/png;base64,…>`)
  → `{{< screenshot NN-alt-slug.webp "Alt" >}}` with the PNG decoded and
  re-encoded to WebP.
- `<<EMBED RECORDING>>` → `{{< youtube ID >}}` (or a visible `<!-- TODO -->`
  when no id is supplied).
- Google-Docs escaping noise (`\!`, `\.`, `\<\<` …) is stripped from prose.

Requires `cwebp` (`brew install webp`), `unzip`, and the Dart SDK (`git` too, if
you use the staging prompt). Run it from the repo root. Review the generated `index.md` before committing — alt text
comes from the recording tool and may need polish, and the recording TODO needs
a real video id.
