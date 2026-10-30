import 'package:flutter/material.dart';

import 'app_settings.dart';

class AccentChoice {
  const AccentChoice(this.name, this.color);

  final String name;
  final Color color;
}

class FontChoice {
  const FontChoice(this.label, this.family);

  final String label;

  /// An Android system font family, or null for the app's normal font.
  final String? family;
}

const accentChoices = [
  AccentChoice('Brown', Color(AppSettings.defaultAccent)),
  AccentChoice('Red', Color(0xFFE53935)),
  AccentChoice('Pink', Color(0xFFD81B60)),
  AccentChoice('Purple', Color(0xFF8E24AA)),
  AccentChoice('Indigo', Color(0xFF3949AB)),
  AccentChoice('Blue', Color(0xFF1E88E5)),
  AccentChoice('Teal', Color(0xFF00897B)),
  AccentChoice('Green', Color(0xFF43A047)),
  AccentChoice('Orange', Color(0xFFFB8C00)),
  AccentChoice('Grey', Color(0xFF607D8B)),
];

/// Fonts built into Android, so the app needs no downloads and stays offline.
const fontChoices = [
  FontChoice('Default', null),
  FontChoice('Serif (like a printed book)', 'serif'),
  FontChoice('Monospace', 'monospace'),
  FontChoice('Condensed', 'sans-serif-condensed'),
  FontChoice('Casual', 'casual'),
  FontChoice('Cursive', 'cursive'),
];

/// A warm, cream page colour for the paper look in light mode.
const paperColor = Color(0xFFF6EEDC);

/// The app theme for the chosen accent colour and font.
ThemeData buildTheme(AppSettings settings, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Color(settings.accent),
    brightness: brightness,
  );
  final black = brightness == Brightness.dark && settings.pureBlack;
  final paper = brightness == Brightness.light && settings.paperLight;
  final background = black
      ? Colors.black
      : paper
          ? paperColor
          : null;
  return ThemeData(
    colorScheme: paper
        ? scheme.copyWith(
            surface: paperColor,
            surfaceContainerLow: const Color(0xFFF1E7D0),
            surfaceContainer: const Color(0xFFEDE2C8),
            surfaceContainerHigh: const Color(0xFFE8DCBF),
            surfaceContainerHighest: const Color(0xFFE3D6B7),
          )
        : black
            ? scheme.copyWith(surface: Colors.black)
            : scheme,
    scaffoldBackgroundColor: background,
    fontFamily: settings.fontFamily,
    useMaterial3: true,
  );
}
