// Standalone video converter: turn any clip (e.g. a screen recording downloaded
// from Whale, or an old .gif) into a small, web-optimized H.264 .mp4 — the same
// conversion tool/import_doc.dart uses inline, usable on its own.
//
// Usage:
//   dart run tool/convert_video.dart [input] [output.mp4]
//     input        video to convert; if omitted, a native file picker opens.
//     output.mp4   destination; defaults to "<input-stem>-web.mp4" beside input.
//
// Requires `ffmpeg` and `ffprobe` on PATH.

import 'dart:io';

import 'video.dart';

void main(List<String> args) {
  final src = args.isNotEmpty ? args.first : pickVideoFile();
  if (src == null) {
    stderr.writeln('No input video — nothing to do.');
    exit(64);
  }

  final dest = args.length > 1 ? args[1] : _defaultDest(src);
  stdout.writeln('Converting:\n  $src\n→ $dest');

  final result = transcodeToWebMp4(src, dest);
  if (result == null) exit(1);
  stdout.writeln('✅ ${result.summary}');
}

/// "/path/to/My Clip.mov" -> "/path/to/My Clip-web.mp4"
String _defaultDest(String src) {
  final dot = src.lastIndexOf('.');
  final stem = dot > src.lastIndexOf(RegExp(r'[/\\]')) && dot != -1
      ? src.substring(0, dot)
      : src;
  return '$stem-web.mp4';
}
