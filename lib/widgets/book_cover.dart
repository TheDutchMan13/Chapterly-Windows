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

/// Calm colours for books without a cover picture, picked by title so a
/// book always gets the same one.
const _placeholderColours = [
  Color(0xFF2C6E6A),
  Color(0xFF2A4C9A),
  Color(0xFF7A3B6B),
  Color(0xFF8A5A1E),
  Color(0xFF4A3F8A),
  Color(0xFF5B6B2E),
  Color(0xFF2F5B7A),
  Color(0xFF8A4B2A),
];

Color placeholderColour(String title) {
  var hash = 0;
  for (final unit in title.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _placeholderColours[hash % _placeholderColours.length];
}

/// A cover from the web, or one stored in the book as a data: address
/// (a picture added on the PC). Without one it shows the title on a
/// coloured card, or a plain book icon when there is no title either.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    this.coverUrl,
    this.width = 44,
    this.height = 64,
    this.title,
    this.shadow = false,
  });

  final String? coverUrl;
  final double width;
  final double height;

  /// Shown on the coloured card when there is no cover picture.
  final String? title;

  /// A soft shadow under the cover, for the bigger covers.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      width >= 120 ? 12 : (width >= 70 ? 10 : 6),
    );
    final Widget placeholder;
    final name = title?.trim() ?? '';
    if (name.isNotEmpty && width >= 40) {
      placeholder = Container(
        width: width,
        height: height,
        alignment: Alignment.bottomLeft,
        padding: EdgeInsets.all(width >= 70 ? 10 : 4),
        color: placeholderColour(name),
        child: Text(
          name,
          maxLines: width >= 70 ? 5 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFFEAF0FF),
            fontWeight: FontWeight.w800,
            fontSize: (width / 7.5).clamp(6.0, 22.0),
            height: 1.1,
          ),
        ),
      );
    } else {
      placeholder = SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.menu_book)),
        ),
      );
    }
    Widget errorBuilder(BuildContext context, Object error, StackTrace? stack) =>
        placeholder;
    final url = coverUrl;
    Widget picture = placeholder;
    if (url != null && url.startsWith('data:')) {
      final bytes = _dataCoverBytes(url);
      if (bytes != null) {
        picture = Image.memory(
          bytes,
          width: width,
          height: height,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: errorBuilder,
        );
      }
    } else if (url != null) {
      picture = Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: errorBuilder,
      );
    }
    final clipped = ClipRRect(borderRadius: radius, child: picture);
    if (!shadow) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: clipped,
    );
  }
}
