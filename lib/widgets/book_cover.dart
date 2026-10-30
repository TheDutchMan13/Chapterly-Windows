import 'package:flutter/material.dart';

/// A cover from the web, or a plain placeholder when there is none.
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}
