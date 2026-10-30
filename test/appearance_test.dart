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
      ..setAccent(0xFF43A047)
      ..setFontFamily('monospace');
    final theme = buildTheme(settings, Brightness.light);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'monospace');
    expect(theme.colorScheme.primary, isNot(const Color(0xFF795548)));
  });
}
