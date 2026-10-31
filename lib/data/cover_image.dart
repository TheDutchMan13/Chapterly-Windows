import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Covers taken from the PC are made this wide (in pixels), so they stay
/// small enough to sync to the phone.
const coverWidth = 400;

/// Picture files that can be used as a cover.
const coverExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];

/// Whether [path] looks like a picture file that can be a cover.
bool isCoverImageFile(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return coverExtensions.contains(path.substring(dot + 1).toLowerCase());
}

/// Whether [url] is a cover stored inside the book itself.
bool isDataCover(String? url) => url != null && url.startsWith('data:image/');

/// The picture bytes of a data: cover, or null if it is not one.
Uint8List? bytesFromDataCover(String url) {
  if (!isDataCover(url)) return null;
  try {
    return UriData.parse(url).contentAsBytes();
  } on FormatException {
    return null;
  }
}

/// Turns the picture in [bytes] (JPEG, PNG, BMP, GIF or WebP) into a small
/// JPEG, [coverWidth] pixels wide at most, as a data: address that can be
/// saved as a book's cover and synced. Returns null if it is not a picture.
String? shrinkToDataCover(Uint8List bytes) {
  // The picture library can throw, not just return null, on bytes that are
  // not a picture at all (a few stray bytes, say).
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  var picture = img.bakeOrientation(decoded);
  if (picture.width > coverWidth) {
    picture = img.copyResize(
      picture,
      width: coverWidth,
      interpolation: img.Interpolation.average,
    );
  }
  final jpeg = img.encodeJpg(picture, quality: 82);
  return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
}

/// [shrinkToDataCover] on a background thread, so the window does not
/// freeze on a big photo.
Future<String?> makeDataCover(Uint8List bytes) =>
    compute(shrinkToDataCover, bytes);
