import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Decoded data: covers, kept so a long list does not decode the same
/// picture again on every frame. Reusing the same bytes also lets Flutter's
/// image cache find the picture.
final _dataCovers = <String, Uint8List>{};
const _maxDataCovers = 300;

Uint8List? _dataCoverBytes(String url) {
  final cached = _dataCovers[url];
  if (cached != null) return cached;
  Uint8List bytes;
  try {
    bytes = UriData.parse(url).contentAsBytes();
  } on FormatException {
    return null;
  }
  if (_dataCovers.length >= _maxDataCovers) {
    _dataCovers.remove(_dataCovers.keys.first);
  }
  _dataCovers[url] = bytes;
  return bytes;
}

/// A cover from the web, or one stored in the book as a data: address
/// (a picture added on the PC), or a plain placeholder when there is none.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    this.coverUrl,
    this.width = 44,
    this.height = 64,
  });

  final String? coverUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.menu_book)),
      ),
    );
    final url = coverUrl;
    if (url == null) return placeholder;
    Widget errorBuilder(BuildContext context, Object error, StackTrace? stack) =>
        placeholder;
    final Widget picture;
    if (url.startsWith('data:')) {
      final bytes = _dataCoverBytes(url);
      if (bytes == null) return placeholder;
      picture = Image.memory(
        bytes,
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: errorBuilder,
      );
    } else {
      picture = Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: errorBuilder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: picture,
    );
  }
}
