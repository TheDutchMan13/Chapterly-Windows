import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/theme_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('accent colour and font are saved and loaded', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(settings.accent, AppSettings.defaultAccent);
    expect(settings.fontFamily, isNull);

    settings.setAccent(0xFF1E88E5);
    settings.setFontFamily('serif');
    final reloaded = await AppSettings.load();
    expect(reloaded.accent, 0xFF1E88E5);
    expect(reloaded.fontFamily, 'serif');

    reloaded.setFontFamily(null);
    expect((await AppSettings.load()).fontFamily, isNull);
  });

  test('the theme uses the chosen accent and font', () {
    final settings = AppSettings()
      ..setLook(AppLook.classic)
      ..setAccent(0xFF43A047)
      ..setFontFamily('monospace');
    final theme = buildTheme(settings, Brightness.light);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'monospace');
    expect(theme.colorScheme.primary, isNot(const Color(0xFF795548)));
  });

  test('Midnight is the look a new install starts with', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(settings.look, AppLook.midnight);
    expect(settings.continueCard, isTrue);
    settings.setLook(AppLook.classic);
    settings.setContinueCard(false);
    final reloaded = await AppSettings.load();
    expect(reloaded.look, AppLook.classic);
    expect(reloaded.continueCard, isFalse);
  });

  test('Midnight is navy and teal in dark mode and off-white by day', () {
    final settings = AppSettings();
    final dark = buildTheme(settings, Brightness.dark);
    final light = buildTheme(settings, Brightness.light);
    expect(dark.colorScheme.surface, const Color(0xFF0B1530));
    expect(dark.colorScheme.primary, const Color(0xFF3DD6C6));
    expect(light.colorScheme.surface, const Color(0xFFF4F7FB));
    expect(light.colorScheme.primary, const Color(0xFF0B7A70));
    expect(dark.textTheme.bodyMedium?.fontFamily, midnightFont);
    settings.setFontFamily('serif');
    expect(
      buildTheme(settings, Brightness.dark).textTheme.bodyMedium?.fontFamily,
      'serif',
    );
  });
}
