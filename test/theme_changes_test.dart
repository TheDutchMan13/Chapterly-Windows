import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/widgets/theme_changes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app is rebuilt for a new look, not for other settings',
      (tester) async {
    final settings = AppSettings();
    var builds = 0;
    await tester.pumpWidget(ThemeChanges(
      settings: settings,
      builder: (context) {
        builds++;
        return const SizedBox();
      },
    ));
    expect(builds, 1);

    // Settings that do not change how the app looks.
    settings.setListPaneShare(0.5);
    await tester.pump();
    expect(builds, 1);

    // Ones that do.
    settings.setAccent(0xFF43A047);
    await tester.pump();
    expect(builds, 2);
    settings.setFontFamily('serif');
    await tester.pump();
    expect(builds, 3);
    settings.setThemeMode(ThemeMode.dark);
    await tester.pump();
    expect(builds, 4);
  });
}
