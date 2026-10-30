import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/file_io.dart';

/// Takes a picture of the widget under [boundaryKey] (a [RepaintBoundary])
/// and opens the share sheet with it. Throws if the picture cannot be made.
Future<void> shareBoundaryAsImage(
  GlobalKey boundaryKey,
  FileIo fileIo, {
  required String fileName,
  String? subject,
}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw StateError('Card not ready');
  final image = await boundary.toImage(pixelRatio: 3);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('No image data');
  await fileIo.shareImage(
    fileName: fileName,
    bytes: data.buffer.asUint8List(),
    subject: subject,
  );
}
