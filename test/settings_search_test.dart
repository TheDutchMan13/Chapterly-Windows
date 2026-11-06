import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    final settings = AppSettings();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        repository: repository,
        settings: settings,
        pcSync: PcSync(
          repository: repository,
          settings: settings,
          codeStore: MemoryCodeStore(),
        ),
        fileIo: FileIo(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('typing shows only the sections that have the words',
      (tester) async {
    await open(tester);
    expect(find.text('Search settings'), findsOneWidget);
    // The groups are folded until a search opens them.
    expect(find.text('Export backup'), findsNothing);

    await tester.enterText(find.byType(TextField), 'goodreads');
    await tester.pumpAndSettle();
    // Found by a word in a description, so the whole section shows.
    expect(find.text('Export as CSV'), findsOneWidget);
    expect(find.text('Export backup'), findsNothing);
    expect(find.text('No settings match "goodreads".'), findsNothing);

    await tester.enterText(find.byType(TextField), 'export backup');
    await tester.pumpAndSettle();
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Export as CSV'), findsNothing);
  });

  testWidgets('words can be in any order and case, and nothing found says so',
      (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'BACKUP export');
    await tester.pumpAndSettle();
    expect(find.text('Export backup'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzzqx');
    await tester.pumpAndSettle();
    expect(find.text('No settings match "zzzzqx".'), findsOneWidget);
    expect(find.text('Export backup'), findsNothing);
  });

  testWidgets('clearing the search brings everything back', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'zzzzqx');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Export backup'), findsNothing);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.textContaining('No settings match'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
