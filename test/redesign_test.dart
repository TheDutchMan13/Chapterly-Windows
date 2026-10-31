import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/file_io.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:chapterly/screens/book_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the cover size stays between the smallest and biggest', () {
    final settings = AppSettings();
    expect(settings.coverScale, 1.0);
    settings.setCoverScale(1.3);
    expect(settings.coverScale, 1.3);
    settings.setCoverScale(5);
    expect(settings.coverScale, AppSettings.maxCoverScale);
    settings.setCoverScale(0.1);
    expect(settings.coverScale, AppSettings.minCoverScale);
  });

  testWidgets('the book page has Overview, Reading and Notes tabs',
      (tester) async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(
      title: 'Emma',
      author: 'Jane Austen',
      shelf: Shelf.forLater,
    );
    final id = repository.books.single.id;
    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailScreen(
          repository: repository,
          settings: AppSettings(),
          fileIo: const FileIo(),
          bookId: id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('Jane Austen'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    // A book that is not being read opens on Overview.
    expect(find.text('Format'), findsOneWidget);

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('No notes yet.'), findsOneWidget);

    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();
    expect(find.text('Started'), findsOneWidget);
  });
}
