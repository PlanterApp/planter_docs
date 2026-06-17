// Shared video helpers used by both the doc importer (tool/import_doc.dart) and
// the standalone converter (tool/convert_video.dart).
//
// - pickVideoFile(): open a native "choose file" dialog (macOS/Windows/Linux),
//   falling back to a typed path prompt.
// - transcodeToWebMp4(): ffmpeg -> small, web-optimized H.264 .mp4 (≈10× smaller
//   than an equivalent GIF/animated-WebP for screen recordings).
// - hasCommand(): cross-platform PATH check (`where` on Windows, else `which`).
//
// Requires `ffmpeg` and `ffprobe` on PATH. SDK only — safe to `import` from a
// standalone script without a pubspec.

import 'dart:io';

/// Whether [cmd] resolves on PATH (uses `where` on Windows, `which` elsewhere).
bool hasCommand(String cmd) {
  try {
    final probe = Platform.isWindows ? 'where' : 'which';
    return Process.runSync(probe, [cmd]).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// True when both ffmpeg and ffprobe are available.
bool hasFfmpeg() => hasCommand('ffmpeg') && hasCommand('ffprobe');

/// Open a native file picker and return the chosen video's path, or null if the
/// user cancels / no path is given. Falls back to a typed prompt when no native
/// chooser is available (e.g. Linux without zenity, or a non-interactive shell).
String? pickVideoFile({String prompt = 'Select the screen recording'}) {
  String? out;
  try {
    if (Platform.isMacOS) {
      final r = Process.runSync('osascript', [
        '-e',
        'POSIX path of (choose file with prompt "$prompt (Cancel to skip)" '
            'of type {"public.movie"})',
      ]);
      if (r.exitCode == 0) out = (r.stdout as String).trim();
    } else if (Platform.isWindows) {
      final r = Process.runSync('powershell', [
        '-NoProfile',
        '-STA',
        '-Command',
        'Add-Type -AssemblyName System.Windows.Forms; '
            r"$d = New-Object System.Windows.Forms.OpenFileDialog; "
            r"$d.Title = '" + prompt + r"'; "
            r"$d.Filter = 'Videos|*.mp4;*.mov;*.m4v;*.webm;*.avi;*.mkv|All files|*.*'; "
            r"if ($d.ShowDialog() -eq 'OK') { $d.FileName }",
      ]);
      if (r.exitCode == 0) out = (r.stdout as String).trim();
    } else if (Platform.isLinux && hasCommand('zenity')) {
      final r = Process.runSync('zenity', [
        '--file-selection',
        '--title=$prompt',
      ]);
      if (r.exitCode == 0) out = (r.stdout as String).trim();
    }
  } catch (_) {
    // fall through to the typed prompt
  }

  // No native chooser available, or it errored: ask for a path.
  if (out == null) {
    stdout.write('$prompt (path, blank to skip): ');
    out = stdin.readLineSync()?.trim();
  }

  if (out == null || out.isEmpty) return null;
  // Strip surrounding quotes a user might paste (e.g. drag-and-drop on a shell).
  out = out.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
  if (!File(out).existsSync()) {
    stderr.writeln('  ! not found: $out');
    return null;
  }
  return out;
}

/// Result of a transcode: where it landed and the byte sizes before/after.
class TranscodeResult {
  final String path;
  final int srcBytes;
  final int destBytes;
  TranscodeResult(this.path, this.srcBytes, this.destBytes);

  String get summary {
    String h(int b) => b >= 1 << 20
        ? '${(b / (1 << 20)).toStringAsFixed(1)}M'
        : '${(b / 1024).round()}K';
    final pct = srcBytes == 0 ? 0 : (100 - destBytes * 100 / srcBytes).round();
    return '${h(srcBytes)} → ${h(destBytes)} ($pct% smaller)';
  }
}

/// Transcode [srcPath] into a small web-optimized H.264 .mp4 at [destPath].
/// Downscales to at most [maxWidth] px wide (never upscales), strips audio
/// unless the source has an audio track. Returns null on failure.
TranscodeResult? transcodeToWebMp4(
  String srcPath,
  String destPath, {
  int maxWidth = 480,
  int crf = 30,
}) {
  if (!hasFfmpeg()) {
    stderr.writeln('`ffmpeg`/`ffprobe` not found on PATH — cannot convert video.');
    return null;
  }
  final src = File(srcPath);
  if (!src.existsSync()) {
    stderr.writeln('Video not found: $srcPath');
    return null;
  }

  // Keep audio only if the source actually has an audio stream.
  final probe = Process.runSync('ffprobe', [
    '-v', 'error',
    '-select_streams', 'a',
    '-show_entries', 'stream=codec_type',
    '-of', 'csv=p=0',
    srcPath,
  ]);
  final hasAudio = (probe.stdout as String).contains('audio');

  final args = <String>[
    '-y',
    '-i', srcPath,
    // Cap width to maxWidth, keep aspect, force even height. The comma in
    // min(...) is escaped so ffmpeg doesn't read it as a filter separator.
    '-vf', 'scale=min($maxWidth\\,iw):-2',
    '-c:v', 'libx264',
    '-crf', '$crf',
    '-preset', 'slow',
    '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart',
    ...(hasAudio ? ['-c:a', 'aac', '-b:a', '96k'] : ['-an']),
    destPath,
  ];
  final r = Process.runSync('ffmpeg', args);
  if (r.exitCode != 0) {
    stderr.writeln('  ! ffmpeg failed:\n${r.stderr}');
    return null;
  }
  return TranscodeResult(
    destPath,
    src.lengthSync(),
    File(destPath).lengthSync(),
  );
}
