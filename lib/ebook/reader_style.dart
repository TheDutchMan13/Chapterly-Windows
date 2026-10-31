import 'package:flutter/widgets.dart';

import 'ebook_library.dart';

/// The colours of one reader theme.
@immutable
class ReaderColors {
  const ReaderColors({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.bar,
    required this.highlight,
  });

  final Color background;
  final Color foreground;

  /// Small text such as the page number.
  final Color muted;

  /// The tool bars shown when you tap the middle of the page.
  final Color bar;

  /// Marked passages.
  final Color highlight;

  bool get isDark => background.computeLuminance() < 0.3;
}

ReaderColors readerColors(ReaderTheme theme) => switch (theme) {
      ReaderTheme.paper => const ReaderColors(
          background: Color(0xFFF4ECD8),
          foreground: Color(0xFF2B211B),
          muted: Color(0xFF66574B),
          bar: Color(0xFFFFFBF2),
          highlight: Color(0xFFE8C766),
        ),
      ReaderTheme.white => const ReaderColors(
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF1C1B1F),
          muted: Color(0xFF5E5E62),
          bar: Color(0xFFF6F3F0),
          highlight: Color(0xFFF2D35B),
        ),
      ReaderTheme.dark => const ReaderColors(
          background: Color(0xFF2B2622),
          foreground: Color(0xFFE8DFD0),
          muted: Color(0xFFB8AE9F),
          bar: Color(0xFF39322D),
          highlight: Color(0xFF8C6D1F),
        ),
      ReaderTheme.black => const ReaderColors(
          background: Color(0xFF000000),
          foreground: Color(0xFFD8D8D8),
          muted: Color(0xFFA0A0A0),
          bar: Color(0xFF1C1C1C),
          highlight: Color(0xFF7A6118),
        ),
    };

/// A highlight's colour, solid, for drawing behind the text: a light one on
/// the light themes and a deep one on the dark themes, so the text stays
/// easy to read.
Color highlightColour(HighlightColour colour, ReaderTheme theme) {
  final dark = theme == ReaderTheme.dark || theme == ReaderTheme.black;
  return switch (colour) {
    HighlightColour.yellow =>
      dark ? const Color(0xFF7A6118) : const Color(0xFFF2D35B),
    HighlightColour.green =>
      dark ? const Color(0xFF3B6534) : const Color(0xFFB5E0A4),
    HighlightColour.blue =>
      dark ? const Color(0xFF2D5576) : const Color(0xFFA9CDF2),
    HighlightColour.pink =>
      dark ? const Color(0xFF7A3553) : const Color(0xFFF4B3CB),
  };
}

/// A highlight's colour for the EPUB viewer, which lays it over the text
/// at a low opacity: always the bright one.
Color highlightSwatch(HighlightColour colour) =>
    highlightColour(colour, ReaderTheme.white);

String readerThemeLabel(ReaderTheme theme) => switch (theme) {
      ReaderTheme.paper => 'Paper',
      ReaderTheme.white => 'White',
      ReaderTheme.dark => 'Dark',
      ReaderTheme.black => 'Black',
    };

String readerSpacingLabel(ReaderSpacing spacing) => switch (spacing) {
      ReaderSpacing.small => 'Small',
      ReaderSpacing.normal => 'Normal',
      ReaderSpacing.large => 'Large',
    };

/// Space between lines, as a multiple of the text size.
double readerLineHeight(ReaderSpacing spacing) => switch (spacing) {
      ReaderSpacing.small => 1.35,
      ReaderSpacing.normal => 1.6,
      ReaderSpacing.large => 1.9,
    };

/// Space on the left and right of the text, in logical pixels.
double readerMargin(ReaderSpacing spacing) => switch (spacing) {
      ReaderSpacing.small => 8,
      ReaderSpacing.normal => 20,
      ReaderSpacing.large => 36,
    };

String _cssColour(Color colour) {
  String part(double value) =>
      (value * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${part(colour.r)}${part(colour.g)}${part(colour.b)}';
}

/// The style the reader puts over the book's own: the typeface, the space
/// between lines and the colours. Keyed by selector, as the EPUB viewer
/// wants it. "!important" wins over the book's own style.
Map<String, dynamic> readerCss(ReaderPrefs prefs) {
  final colours = readerColors(prefs.theme);
  final family = switch (prefs.font) {
    ReaderFont.serif => 'Georgia, "Noto Serif", serif',
    ReaderFont.sans => 'Roboto, "Noto Sans", sans-serif',
  };
  final text = {
    'font-family': '$family !important',
    'line-height': '${readerLineHeight(prefs.lineSpacing)} !important',
  };
  return {
    'body': {
      ...text,
      'color': '${_cssColour(colours.foreground)} !important',
      'background': '${_cssColour(colours.background)} !important',
    },
    'p': text,
    'div': {'font-family': '$family !important'},
    'span': {'font-family': '$family !important'},
    'li': text,
    'a': {'color': '${_cssColour(colours.foreground)} !important'},
  };
}

/// Splits a tap on the page into a zone: the left quarter goes back a
/// page, the right quarter goes forward, and the middle shows or hides the
/// tools. [x] is from 0 (left edge) to 1 (right edge).
enum TapZone { back, middle, forward }

TapZone tapZone(double x) {
  if (x < 0.25) return TapZone.back;
  if (x > 0.75) return TapZone.forward;
  return TapZone.middle;
}

/// "38%".
String percentText(double progress) {
  final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
  return '${(p * 100).round()}%';
}
