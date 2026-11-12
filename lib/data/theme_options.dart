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

/// Font families that come with Windows, for the names the font list stores.
/// The list keeps the Android names so a saved choice still means the same
/// thing; here they are turned into fonts Windows really has (the Android
/// names do not exist on Windows, so they fell back to the default font).
const _windowsFonts = {
  'serif': 'Georgia',
  'monospace': 'Consolas',
  'sans-serif-condensed': 'Arial Narrow',
  'casual': 'Comic Sans MS',
  'cursive': 'Segoe Script',
};

/// The font to draw with for a saved font choice.
String? fontFor(String? choice) =>
    choice == null ? null : (_windowsFonts[choice] ?? choice);

/// The font choices, by name.
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

/// The font that comes with the app for the Midnight look.
const midnightFont = 'Manrope';

/// The Midnight colours: deep navy and teal at night, and cool off-white
/// with a deeper teal by day.
ColorScheme midnightScheme(Brightness brightness, {bool black = false}) {
  if (brightness == Brightness.dark) {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF3DD6C6),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF3DD6C6),
      onPrimary: const Color(0xFF04201D),
      primaryContainer: const Color(0xFF1B3F44),
      onPrimaryContainer: const Color(0xFFC5E8E4),
      secondary: const Color(0xFF9DB4F0),
      onSecondary: const Color(0xFF0B1530),
      secondaryContainer: const Color(0xFF22346B),
      onSecondaryContainer: const Color(0xFFEAF0FF),
      tertiary: const Color(0xFFF2B66D),
      onTertiary: const Color(0xFF2B1700),
      surface: black ? Colors.black : const Color(0xFF0B1530),
      onSurface: const Color(0xFFEAF0FF),
      onSurfaceVariant: const Color(0xFFA3B2D6),
      surfaceContainerLowest: black ? Colors.black : const Color(0xFF08102A),
      surfaceContainerLow: black ? const Color(0xFF0A1022) : const Color(0xFF0F1B3A),
      surfaceContainer: black ? const Color(0xFF0E1630) : const Color(0xFF131F40),
      surfaceContainerHigh: black ? const Color(0xFF131D3A) : const Color(0xFF16234A),
      surfaceContainerHighest: const Color(0xFF22346B),
      outline: const Color(0xFF5A6C9C),
      outlineVariant: const Color(0xFF26356A),
      inverseSurface: const Color(0xFFEAF0FF),
      onInverseSurface: const Color(0xFF0B1530),
      inversePrimary: const Color(0xFF0B7A70),
      surfaceTint: Colors.transparent,
    );
  }
  return ColorScheme.fromSeed(
    seedColor: const Color(0xFF0B7A70),
    brightness: Brightness.light,
  ).copyWith(
    primary: const Color(0xFF0B7A70),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFD6F0EC),
    onPrimaryContainer: const Color(0xFF0B5E57),
    secondary: const Color(0xFF3A4D80),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFE1E8F5),
    onSecondaryContainer: const Color(0xFF0E1A33),
    tertiary: const Color(0xFFA0601A),
    onTertiary: Colors.white,
    surface: const Color(0xFFF4F7FB),
    onSurface: const Color(0xFF0E1A33),
    onSurfaceVariant: const Color(0xFF55637F),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: const Color(0xFFEEF2F8),
    surfaceContainerHigh: const Color(0xFFE8EEF6),
    surfaceContainerHighest: const Color(0xFFDCE3EF),
    outline: const Color(0xFF8A97B0),
    outlineVariant: const Color(0xFFDCE3EF),
    inverseSurface: const Color(0xFF0E1A33),
    onInverseSurface: const Color(0xFFEAF0FF),
    inversePrimary: const Color(0xFF3DD6C6),
    surfaceTint: Colors.transparent,
  );
}

/// The app theme for the chosen look, accent colour and font.
ThemeData buildTheme(AppSettings settings, Brightness brightness) {
  if (settings.look == AppLook.midnight) {
    return _midnightTheme(settings, brightness);
  }
  return _classicTheme(settings, brightness);
}

ThemeData _midnightTheme(AppSettings settings, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = midnightScheme(
    brightness,
    black: dark && settings.pureBlack,
  );
  final font = fontFor(settings.fontFamily) ?? midnightFont;
  final base = ThemeData(
    colorScheme: scheme,
    fontFamily: font,
    useMaterial3: true,
  );
  final text = base.textTheme.copyWith(
    displaySmall: base.textTheme.displaySmall
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
    headlineLarge: base.textTheme.headlineLarge
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
    headlineMedium: base.textTheme.headlineMedium
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
    headlineSmall: base.textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
    titleLarge: base.textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
    titleMedium:
        base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall:
        base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge:
        base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );
  final card = dark
      ? (settings.pureBlack ? const Color(0xFF0E1630) : const Color(0xFF16234A))
      : Colors.white;
  final rounded14 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall?.copyWith(
        color: scheme.onSurface,
        fontSize: 24,
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? scheme.surfaceContainer : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 66,
      indicatorColor: scheme.primary,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.primary,
      indicatorShape: const StadiumBorder(),
      selectedIconTheme: IconThemeData(color: scheme.onPrimary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: text.labelMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      indicator: _PillIndicator(scheme.primaryContainer),
      indicatorSize: TabBarIndicatorSize.tab,
      labelPadding: const EdgeInsets.symmetric(horizontal: 16),
      dividerColor: Colors.transparent,
      labelColor: scheme.onPrimaryContainer,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: text.titleSmall,
      splashBorderRadius: BorderRadius.circular(24),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 48),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 44),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 44),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: dark ? scheme.surfaceContainer : Colors.white,
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.onPrimaryContainer,
      labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
      secondaryLabelStyle:
          text.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainer : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? scheme.surfaceContainerHigh : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? scheme.surfaceContainer : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? scheme.surfaceContainerHigh : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: rounded14,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          dark ? scheme.surfaceContainerHigh : Colors.white,
        ),
        shape: WidgetStatePropertyAll(rounded14),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: rounded14,
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: scheme.primaryContainer,
      selectedColor: scheme.onPrimaryContainer,
      iconColor: scheme.onSurfaceVariant,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.outlineVariant,
      circularTrackColor: scheme.outlineVariant,
      borderRadius: BorderRadius.circular(4),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: scheme.primaryContainer,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onPrimaryContainer,
      ),
    ),
  );
}

/// The look Chapterly had before Midnight: Material colours made from the
/// chosen accent, with the paper and pure black options.
ThemeData _classicTheme(AppSettings settings, Brightness brightness) {
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
    fontFamily: fontFor(settings.fontFamily),
    useMaterial3: true,
  );
}

/// The tab marker in the Midnight look: a rounded pill a little shorter than
/// the tab.
class _PillIndicator extends Decoration {
  const _PillIndicator(this.color);

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _PillPainter(color);
}

class _PillPainter extends BoxPainter {
  _PillPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = (offset & size).deflate(6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      Paint()..color = color,
    );
  }
}
