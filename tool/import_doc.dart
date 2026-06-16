// Import a screen-recording doc (Google Doc -> Markdown export) into the Hugo
// site as a page bundle.
//
// The exporter produces Markdown that does NOT match the site's conventions:
//   * screenshots are embedded as base64 reference-style images
//       **![Alt text][image1]**         (usage, often wrapped in bold)
//       [image1]: <data:image/png;base64,iVBOR...>   (definition at the bottom)
//   * a literal `<<EMBED RECORDING>>` marks where the screen recording goes
//   * Google-Docs escaping noise (\!  \<\<  13\.  etc.)
//   * no front matter; the file lives at the repo root
//
// This tool turns one such file into:
//   content/docs/<section>/<NNN_slug>/
//     index.md            front matter + body using site shortcodes
//     NN-<slug>.webp       one sibling WebP per screenshot
//
// Images become {{< screenshot file.webp "Alt" >}}; the recording placeholder
// becomes {{< youtube ID >}} (or a visible TODO when no id is given).
//
// Full-resolution images: the Markdown export DOWNSAMPLES screenshots. The Word
// (.docx) export keeps them at full size in word/media/. So images are sourced
// from a .docx (matched to the MD's images by document order); the MD is used
// only for text/structure. Provide the .docx with --docx <path>, or just name
// it like the .md (doc.md -> doc.docx) and it's found automatically. With no
// .docx, the tool falls back to the MD's low-res base64 images (with a warning).
//
// Usage:  dart run tool/import_doc.dart "3. Combine Multiple Garden Beds.md"
//         dart run tool/import_doc.dart doc.md --docx doc.docx
//
// Requires `cwebp` (brew install webp) and `unzip` on PATH. No package deps.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/import_doc.dart "<exported>.md" [--docx <file>]');
    exit(64);
  }

  // Parse args: first non-flag positional = the .md; --docx <path> = images.
  String? srcPath;
  String? docxArg;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--docx') {
      docxArg = (i + 1 < args.length) ? args[++i] : null;
    } else if (srcPath == null) {
      srcPath = a;
    }
  }
  if (srcPath == null) {
    stderr.writeln('Missing source .md file.');
    exit(64);
  }

  final srcFile = File(srcPath);
  if (!srcFile.existsSync()) {
    stderr.writeln('Source file not found: $srcPath');
    exit(66);
  }

  final docsDir = Directory('content/docs');
  if (!docsDir.existsSync()) {
    stderr.writeln(
        'Run this from the repo root — content/docs not found from ${Directory.current.path}');
    exit(66);
  }
  if (!_hasCommand('cwebp')) {
    stderr.writeln('`cwebp` not found on PATH. Install it: brew install webp');
    exit(69);
  }

  // Locate the .docx that holds the full-resolution images: --docx, else a
  // sibling file with the same basename (doc.md -> doc.docx).
  File? docxFile;
  if (docxArg != null) {
    docxFile = File(docxArg);
    if (!docxFile.existsSync()) {
      stderr.writeln('--docx file not found: $docxArg');
      exit(66);
    }
  } else {
    final sibling = File(srcPath.replaceFirst(RegExp(r'\.md$', caseSensitive: false), '.docx'));
    if (sibling.path != srcPath && sibling.existsSync()) docxFile = sibling;
  }
  if (docxFile != null && !_hasCommand('unzip')) {
    stderr.writeln('`unzip` not found on PATH but needed to read the .docx.');
    exit(69);
  }

  final raw = srcFile.readAsStringSync();

  // 1. Split reference-image definitions out of the body.
  //    [image1]: <data:image/png;base64,....>
  final defRe = RegExp(
      r'^\s*\[([^\]]+)\]:\s*<?\s*data:image/(\w+);base64,([A-Za-z0-9+/=\s]+?)\s*>?\s*$');
  final imageData = <String, _ImageDef>{};
  final bodyLines = <String>[];
  for (final line in const LineSplitter().convert(raw)) {
    final m = defRe.firstMatch(line);
    if (m != null) {
      imageData[m.group(1)!] =
          _ImageDef(m.group(2)!, m.group(3)!.replaceAll(RegExp(r'\s'), ''));
    } else {
      bodyLines.add(line);
    }
  }
  if (imageData.isEmpty) {
    stdout.writeln('Note: no base64 image definitions found in source.');
  }

  // 2. Pull the title from the first H1 and drop that line.
  String title = '';
  final h1Re = RegExp(r'^\s*#\s+(.+?)\s*$');
  for (var i = 0; i < bodyLines.length; i++) {
    final m = h1Re.firstMatch(bodyLines[i]);
    if (m != null) {
      title = _unescape(m.group(1)!.trim());
      bodyLines.removeAt(i);
      break;
    }
  }

  // 3. Discovery pass: walk the body, assign each referenced image a sequence
  //    number + filename (slug from its alt text, else the current step title).
  final imageRe = RegExp(r'!\[([^\]]*)\]\[([^\]]+)\]');
  final stepTitleRe = RegExp(r'^\s*(?:\d+\\?\.\s+)?\*\*(.+?)\*\*\s*$');
  final order = <String>[]; // ref ids, first-appearance order
  final slugSource = <String, String>{};
  {
    String? stepTitle;
    for (final line in bodyLines) {
      final imgMatches = imageRe.allMatches(line).toList();
      final isImageLine = imgMatches.isNotEmpty && _isImageOnly(line);
      if (!isImageLine) {
        final tm = stepTitleRe.firstMatch(line);
        if (tm != null) stepTitle = _cleanStepTitle(tm.group(1)!);
      }
      for (final im in imgMatches) {
        final alt = im.group(1)!.trim();
        final ref = im.group(2)!;
        if (!order.contains(ref)) {
          order.add(ref);
          final source = alt.isNotEmpty ? alt : (stepTitle ?? ref);
          slugSource[ref] = source;
        }
      }
    }
  }

  // 4. Gather metadata interactively.
  stdout.writeln('\nTitle: $title');
  final sections = docsDir
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.split(Platform.pathSeparator).last)
      .where((n) => !n.startsWith('.'))
      .toList()
    ..sort();
  final section = _pickSection(sections, '100_gardens');
  final sectionDir = Directory('${docsDir.path}/$section');
  if (!sectionDir.existsSync()) {
    stderr.writeln('Section folder does not exist: ${sectionDir.path}');
    exit(66);
  }

  final nextPrefix = _nextPrefix(sectionDir);
  // Default the slug from the file name (e.g. "3. Combine Multiple Garden
  // Beds.md" -> "combine-multiple-garden-beds"), dropping the export's leading
  // "N. " number. Fall back to the H1 title if the file name has no words.
  final fileStem = _baseName(srcPath)
      .replaceFirst(RegExp(r'\.md$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^\s*\d+\s*[.)\-_]*\s*'), '');
  final defaultSlug = _slugify(fileStem.trim().isEmpty ? title : fileStem);
  final slug = _ask('URL/folder slug', defaultSlug);
  final prefix = _ask('Folder number prefix', nextPrefix.toString().padLeft(3, '0'));
  final weight = _ask('Weight (ordering)', int.tryParse(prefix)?.toString() ?? prefix);

  final sectionUrl = _readUrl(File('${sectionDir.path}/_index.md'));
  final defaultUrl = sectionUrl.isEmpty ? slug : '$sectionUrl/$slug';
  final url = _ask('URL', defaultUrl);
  final description = _ask('Description', title.replaceAll(RegExp(r'[?.!]+$'), ''));
  final youtubeId = _ask('YouTube video id for <<EMBED RECORDING>> (blank = TODO)', '');

  final bundleName = '${prefix}_$slug';
  final bundleDir = Directory('${sectionDir.path}/$bundleName');

  // 4b. Handle a folder-number-prefix collision before writing anything.
  //     Returns any other paths it touched (renamed/deleted) so they can be
  //     staged alongside the new bundle.
  final touchedPaths = _resolvePrefixCollision(sectionDir, prefix, bundleName);

  // 5. Convert images to WebP siblings, sourced from the .docx (full-res) and
  //    matched to the MD's refs by document order, or falling back to the MD's
  //    own low-res base64 images when no .docx is available.
  final fileFor = <String, String>{};
  if (order.isNotEmpty) {
    bundleDir.createSync(recursive: true);
    final tmp = Directory.systemTemp.createTempSync('import_doc_');
    try {
      // Map each MD ref -> the path of its source image on disk.
      final srcImageFor = <String, String>{};
      if (docxFile != null) {
        final media = _docxImagesInOrder(docxFile, tmp.path);
        if (media.length != order.length) {
          stderr.writeln('  ! image-count mismatch: MD has ${order.length} image(s), '
              '.docx has ${media.length}. Mapping by order; any extra ref is left as a TODO.');
        }
        for (var i = 0; i < order.length && i < media.length; i++) {
          srcImageFor[order[i]] = media[i];
        }
        stdout.writeln('Using full-resolution images from ${docxFile.path}');
      } else {
        stderr.writeln('⚠️  No .docx supplied — using the Markdown\'s low-resolution '
            'base64 images. Export the gdoc as Word (.docx) for full resolution.');
        for (final ref in order) {
          final def = imageData[ref];
          if (def == null) continue;
          final p = '${tmp.path}/$ref.${def.format}';
          File(p).writeAsBytesSync(base64.decode(def.b64));
          srcImageFor[ref] = p;
        }
      }

      var seq = 0;
      for (final ref in order) {
        seq++;
        final name =
            '${seq.toString().padLeft(2, '0')}-${_slugify(slugSource[ref] ?? ref)}.webp';
        fileFor[ref] = name;
        final src = srcImageFor[ref];
        if (src == null) {
          stderr.writeln('  ! no image source for [$ref] — left as a TODO in the doc');
          continue;
        }
        final out = '${bundleDir.path}/$name';
        final r = Process.runSync('cwebp', ['-quiet', '-q', '80', src, '-o', out]);
        if (r.exitCode != 0) {
          stderr.writeln('  ! cwebp failed for [$ref]: ${r.stderr}');
        } else {
          stdout.writeln('  wrote $name');
        }
      }
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  // 6. Rewrite pass: replace image usages + the recording placeholder, and
  //    strip Google-Docs escaping from prose lines.
  final embedRe = RegExp(r'EMBED\s+RECORDING');
  final out = StringBuffer();
  String? stepTitle;
  for (var line in bodyLines) {
    if (embedRe.hasMatch(line)) {
      out.writeln(youtubeId.isEmpty
          ? '<!-- TODO: embed the screen recording, e.g. {{< youtube VIDEO_ID >}} -->'
          : '{{< youtube $youtubeId >}}');
      continue;
    }

    final isImageLine = _isImageOnly(line);
    if (!isImageLine) {
      final tm = stepTitleRe.firstMatch(line);
      if (tm != null) stepTitle = _cleanStepTitle(tm.group(1)!);
    }

    if (imageRe.hasMatch(line)) {
      final indent = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
      final replaced = line.replaceAllMapped(imageRe, (m) {
        final alt = m.group(1)!.trim();
        final ref = m.group(2)!;
        final file = fileFor[ref] ?? '$ref.webp';
        final altText = alt.isNotEmpty ? alt : (stepTitle ?? 'Screenshot');
        return '{{< screenshot $file "${_escapeQuotes(_unescape(altText))}" >}}';
      });
      if (isImageLine) {
        // Give the screenshot its own block, separated by blank lines from the
        // step title and description (otherwise goldmark folds title + image +
        // text into one paragraph). Indentation keeps it inside the list item;
        // the blank-line collapse in step 7 dedupes any doubled blanks.
        out
          ..writeln()
          ..writeln(indent + replaced.trim().replaceAll(RegExp(r'^\*+|\*+$'), ''))
          ..writeln();
      } else {
        out.writeln(_unescape(replaced).replaceAll(RegExp(r'\s+$'), ''));
      }
      continue;
    }

    out.writeln(_unescape(line).replaceAll(RegExp(r'\s+$'), ''));
  }

  // 7. Assemble front matter + body and write index.md.
  final body = out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trimRight();
  final frontMatter = StringBuffer()
    ..writeln('---')
    ..writeln('title: "${_escapeQuotes(title)}"')
    ..writeln('description: "${_escapeQuotes(description)}"')
    ..writeln('draft: false')
    ..writeln('weight: $weight')
    ..writeln('url: "$url"')
    ..writeln('---')
    ..writeln();

  bundleDir.createSync(recursive: true);
  final indexFile = File('${bundleDir.path}/index.md');
  indexFile.writeAsStringSync('$frontMatter$body\n');

  stdout.writeln('\n✅ Wrote ${indexFile.path}');
  stdout.writeln('   ${order.length} image(s) → ${bundleDir.path}');
  if (youtubeId.isEmpty && embedRe.hasMatch(raw)) {
    stdout.writeln('   ⚠️  recording left as a TODO — add a {{< youtube ID >}} when ready');
  }
  stdout.writeln('   Preview: npm run dev  →  /$url');

  // 8. Optionally stage the new bundle (and any folders the insert/replace step
  //    renamed or deleted) with git.
  if (_hasCommand('git')) {
    final addGit = _ask('\nStage the created files with git add? [y/N]', 'n');
    if (addGit.toLowerCase().startsWith('y')) {
      final paths = {bundleDir.path, ...touchedPaths}.toList();
      final r = Process.runSync('git', ['add', ...paths]);
      if (r.exitCode == 0) {
        stdout.writeln('   staged ${paths.length} path(s) — review with `git status`');
      } else {
        stderr.writeln('   ! git add failed: ${r.stderr}');
      }
    }
  }
}

/// A line whose only meaningful content is image reference(s) — optionally
/// wrapped in bold markers and indented (a list-item continuation).
bool _isImageOnly(String line) =>
    RegExp(r'^\s*\*{0,2}!\[[^\]]*\]\[[^\]]+\]\*{0,2}\s*$').hasMatch(line);

String _cleanStepTitle(String s) =>
    _unescape(s).replaceFirst(RegExp(r'^\d+\\?\.\s*'), '').trim();

/// Strip Google-Docs backslash escapes before punctuation (\! \. \< \> ...).
String _unescape(String s) =>
    s.replaceAllMapped(RegExp(r'\\([!<>.()\[\]#+\-])'), (m) => m.group(1)!);

String _escapeQuotes(String s) => s.replaceAll('"', r'\"');

String _slugify(String s) => s
    .toLowerCase()
    .replaceAll(RegExp("['\"‘’“”]"), '')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'(^-+)|(-+$)'), '');

/// Next free NNN_ folder prefix in a section (max existing + 1, min 1).
int _nextPrefix(Directory sectionDir) {
  var max = 0;
  for (final e in sectionDir.listSync().whereType<Directory>()) {
    final n = _prefixOf(e);
    if (n != null && n > max) max = n;
  }
  return max + 1;
}

String _baseName(String path) => path.split(Platform.pathSeparator).last;

/// The leading NNN_ number of a bundle folder, or null if it has none.
int? _prefixOf(Directory d) {
  final m = RegExp(r'^(\d+)_').firstMatch(_baseName(d.path));
  return m == null ? null : int.parse(m.group(1)!);
}

/// If a folder already uses [prefix] in [sectionDir], ask whether to Insert
/// (renumber this and every higher-numbered folder +1, bumping their weight) or
/// Replace (delete the occupying folder(s)). No-op when the prefix is free.
/// Returns the paths it renamed or deleted, so callers can stage them in git.
List<String> _resolvePrefixCollision(
    Directory sectionDir, String prefix, String newBundleName) {
  final prefixNum = int.tryParse(prefix);
  if (prefixNum == null) return const [];
  final dirs = sectionDir.listSync().whereType<Directory>().toList();
  final occupying = dirs
      .where((d) => _prefixOf(d) == prefixNum && _baseName(d.path) != newBundleName)
      .toList();
  // Also treat an identically-named existing bundle as a collision to resolve.
  final sameName = dirs.where((d) => _baseName(d.path) == newBundleName).toList();
  if (occupying.isEmpty && sameName.isEmpty) return const [];

  final occupied = [...occupying, ...sameName].map((d) => _baseName(d.path)).join(', ');
  stdout.writeln('\n⚠️  Folder number $prefix is already in use by: $occupied');
  stdout.writeln('  A) Insert  — shift this and every higher-numbered folder +1 (renumber + bump weight)');
  stdout.writeln('  B) Replace — delete the existing folder(s) and take its place');
  final choice = _ask('Insert or replace? [A/B]', 'A').toUpperCase();

  final touched = <String>[];
  if (choice == 'B') {
    for (final d in [...occupying, ...sameName]) {
      stdout.writeln('  deleting ${_baseName(d.path)}');
      touched.add(d.path);
      d.deleteSync(recursive: true);
    }
    return touched;
  }

  // Insert: renumber every folder with prefix >= prefixNum, highest first so
  // renames never collide. An identically-named folder is shifted up too.
  final toShift = dirs.where((d) => (_prefixOf(d) ?? -1) >= prefixNum).toList()
    ..sort((a, b) => _prefixOf(b)!.compareTo(_prefixOf(a)!));
  for (final d in toShift) {
    final base = _baseName(d.path);
    final m = RegExp(r'^(\d+)(_.*)$').firstMatch(base)!;
    final newName =
        '${(int.parse(m.group(1)!) + 1).toString().padLeft(m.group(1)!.length, '0')}${m.group(2)}';
    final newPath = '${sectionDir.path}/$newName';
    _bumpWeight(d, 1);
    d.renameSync(newPath);
    touched..add(d.path)..add(newPath); // old (now a deletion) + new path
    stdout.writeln('  shifted $base → $newName (weight +1)');
  }
  return touched;
}

/// Add [delta] to the `weight:` value in a bundle's index.md (if present).
void _bumpWeight(Directory dir, int delta) {
  final f = File('${dir.path}/index.md');
  if (!f.existsSync()) return;
  final txt = f.readAsStringSync();
  final m = RegExp(r'^(\s*weight:\s*)(\d+)', multiLine: true).firstMatch(txt);
  if (m == null) return;
  final bumped = int.parse(m.group(2)!) + delta;
  f.writeAsStringSync(txt.replaceRange(m.start, m.end, '${m.group(1)}$bumped'));
}

String _readUrl(File indexMd) {
  if (!indexMd.existsSync()) return '';
  final m = RegExp(r'^\s*url:\s*"?([^"\n]+)"?\s*$', multiLine: true)
      .firstMatch(indexMd.readAsStringSync());
  return m?.group(1)?.trim() ?? '';
}

String _ask(String label, String def) {
  stdout.write(def.isEmpty ? '$label: ' : '$label [$def]: ');
  final line = stdin.readLineSync()?.trim() ?? '';
  return line.isEmpty ? def : line;
}

/// Choose a section. On a real terminal this is an arrow-key (↑/↓ or j/k) menu;
/// otherwise (piped input) it falls back to a typed prompt.
String _pickSection(List<String> sections, String preferred) {
  var initial = sections.indexOf(preferred);
  if (initial < 0) initial = 0;
  if (!stdin.hasTerminal) {
    stdout.writeln('\nSections under content/docs:');
    for (final s in sections) {
      stdout.writeln('  $s');
    }
    return _ask('Section folder', sections[initial]);
  }
  stdout.writeln('\nSelect a section (↑/↓ to move, Enter to choose):');
  return sections[_pickIndex(sections, initial)];
}

/// Raw-mode arrow-key menu over [options]; returns the chosen index.
int _pickIndex(List<String> options, int initial) {
  var idx = initial;
  stdin.echoMode = false;
  stdin.lineMode = false;
  try {
    _drawMenu(options, idx, redraw: false);
    loop:
    while (true) {
      final key = stdin.readByteSync();
      switch (key) {
        case 0x03: // Ctrl-C
          stdin
            ..lineMode = true
            ..echoMode = true;
          stdout.writeln();
          exit(130);
        case 0x0A: // Enter (LF)
        case 0x0D: // Enter (CR)
          break loop;
        case 0x6B: // k
          idx = (idx - 1 + options.length) % options.length;
        case 0x6A: // j
          idx = (idx + 1) % options.length;
        case 0x1B: // ESC — start of an arrow-key sequence "ESC [ A/B"
          if (stdin.readByteSync() == 0x5B) {
            final code = stdin.readByteSync();
            if (code == 0x41) idx = (idx - 1 + options.length) % options.length;
            if (code == 0x42) idx = (idx + 1) % options.length;
          }
      }
      _drawMenu(options, idx, redraw: true);
    }
  } finally {
    stdin
      ..lineMode = true
      ..echoMode = true;
  }
  return idx;
}

/// Render the menu; when [redraw] move the cursor back up over the prior render.
void _drawMenu(List<String> options, int idx, {required bool redraw}) {
  if (redraw) stdout.write('\x1B[${options.length}A'); // cursor up N lines
  for (var i = 0; i < options.length; i++) {
    final line = i == idx
        ? '\x1B[36m❯ ${options[i]}\x1B[0m' // cyan, arrow
        : '  ${options[i]}';
    stdout.write('\r\x1B[K$line\n'); // clear line, then write
  }
}

bool _hasCommand(String cmd) {
  try {
    return Process.runSync('which', [cmd]).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Extract a .docx's embedded images and return their on-disk paths in
/// document order, de-duplicated by first appearance (a screenshot reused in
/// the Doc yields one file, matching how the MD reuses a single ref).
///
/// A .docx is a zip: word/document.xml references images by relationship id
/// (`r:embed="rIdN"`); word/_rels/document.xml.rels maps each rId to a file
/// under word/media/. We read the embed order from document.xml and resolve it
/// through the rels map — robust against arbitrary media filenames.
List<String> _docxImagesInOrder(File docx, String tmpDir) {
  final dest = Directory('$tmpDir/docx');
  dest.createSync(recursive: true);
  final unzip =
      Process.runSync('unzip', ['-o', '-q', docx.path, '-d', dest.path]);
  if (unzip.exitCode != 0) {
    stderr.writeln('  ! unzip failed for ${docx.path}: ${unzip.stderr}');
    return const [];
  }

  final relsFile = File('${dest.path}/word/_rels/document.xml.rels');
  final docXml = File('${dest.path}/word/document.xml');
  if (!relsFile.existsSync() || !docXml.existsSync()) {
    stderr.writeln('  ! ${docx.path} is missing word/document.xml or its rels — '
        'is it a Word .docx?');
    return const [];
  }

  // rId -> media path (relationship Targets are relative to word/).
  final rels = <String, String>{};
  for (final m in RegExp(r'Id="(rId\d+)"[^>]*?Target="([^"]+)"')
      .allMatches(relsFile.readAsStringSync())) {
    final target = m.group(2)!;
    if (target.contains('media/')) {
      rels[m.group(1)!] = '${dest.path}/word/${target.replaceAll('../', '')}';
    }
  }

  // Embed references in document order, de-duplicated by first appearance.
  final seen = <String>{};
  final paths = <String>[];
  for (final m
      in RegExp(r'r:embed="(rId\d+)"').allMatches(docXml.readAsStringSync())) {
    final path = rels[m.group(1)!];
    if (path != null && seen.add(path)) paths.add(path);
  }
  return paths;
}

class _ImageDef {
  final String format;
  final String b64;
  _ImageDef(this.format, this.b64);
}
