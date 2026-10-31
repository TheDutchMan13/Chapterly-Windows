import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/shelf.dart';

// The same file is in the Android and the Windows app.

/// Where to look up [text] (a word or a few): Wiktionary's search, which
/// opens the word's page when there is one.
Uri dictionaryUri(String text) {
  final words = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return Uri.https('en.wiktionary.org', '/w/index.php', {'search': words});
}

/// Whether [text] is short enough to look up: a word or a short phrase.
bool canLookUp(String text) {
  final words = text.trim();
  return words.isNotEmpty && words.length <= 60 && !words.contains('\n');
}

/// The shelf a book moves to when you open its book file: from For later or
/// Unfinished to In progress. Null when it stays where it is.
Shelf? shelfOnOpen(Shelf shelf) => switch (shelf) {
      Shelf.forLater || Shelf.unfinished => Shelf.inProgress,
      Shelf.inProgress || Shelf.finished => null,
    };

/// Whether a place in the book counts as its end.
bool reachedEnd(double progress) => !progress.isNaN && progress >= 0.995;

final _sentenceEnd = RegExp(r'(?<=[.!?…:;"”’)\]])\s+');
final _spaces = RegExp(r'\s+');
final _paragraphBreak = RegExp(r'\n\s*\n');

/// Splits text into pieces to read aloud: whole sentences, joined up to
/// about [size] characters, so a long chapter does not go to the voice in
/// one go and you can see roughly where it is.
List<String> speechChunks(String text, {int size = 400}) {
  final sentences = text
      .split(_paragraphBreak)
      .expand((p) => p.replaceAll(_spaces, ' ').split(_sentenceEnd))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  final chunks = <String>[];
  final current = StringBuffer();
  void flush() {
    if (current.isNotEmpty) chunks.add(current.toString());
    current.clear();
  }

  for (final sentence in sentences) {
    var rest = sentence;
    // A "sentence" with no stop in it can be very long: cut it at a space.
    while (rest.length > size * 2) {
      var cut = rest.lastIndexOf(' ', size * 2);
      if (cut <= 0) cut = size * 2;
      flush();
      chunks.add(rest.substring(0, cut).trim());
      rest = rest.substring(cut).trim();
    }
    if (rest.isEmpty) continue;
    if (current.isNotEmpty && current.length + 1 + rest.length > size) flush();
    if (current.isNotEmpty) current.write(' ');
    current.write(rest);
  }
  flush();
  return chunks;
}

/// A voice that reads text aloud.
abstract interface class Speaker {
  /// Reads [text] aloud. Completes when it has been read, or when [stop] is
  /// called.
  Future<void> speak(String text);

  /// Stops reading at once.
  Future<void> stop();

  /// 1 is normal speed.
  Future<void> setRate(double rate);

  /// Lets go of the voice.
  Future<void> dispose();
}

/// Reads a book aloud, one piece after another, asking for more (the next
/// page or chapter) when it runs out.
class ReadAloud extends ChangeNotifier {
  ReadAloud(this.speaker);

  final Speaker speaker;
  int _session = 0;
  bool _playing = false;
  bool _disposed = false;

  bool get playing => _playing;

  void _set(bool playing) {
    if (_playing == playing || _disposed) return;
    _playing = playing;
    notifyListeners();
  }

  /// Reads [pieces] aloud. [onPiece] is told which piece of the current
  /// batch is being read. When a batch is done, [more] is asked for the
  /// next one (after turning the page); null means the end of the book.
  Future<void> start({
    required List<String> pieces,
    required Future<List<String>?> Function() more,
    void Function(int index)? onPiece,
  }) async {
    await stop();
    final session = ++_session;
    _set(true);
    var batch = pieces;
    var emptyBatches = 0;
    try {
      while (_session == session) {
        for (var i = 0; i < batch.length; i++) {
          if (_session != session) return;
          onPiece?.call(i);
          await speaker.speak(batch[i]);
        }
        if (_session != session) return;
        // Pages with no words (pictures) are passed over, but not forever.
        emptyBatches = batch.isEmpty ? emptyBatches + 1 : 0;
        if (emptyBatches > 20) break;
        final next = await more();
        if (next == null) break;
        batch = next;
      }
    } catch (_) {
      // The voice failed; stop quietly.
    } finally {
      if (_session == session) _set(false);
    }
  }

  /// Stops reading.
  Future<void> stop() async {
    _session++;
    final was = _playing;
    _set(false);
    if (was) {
      try {
        await speaker.stop();
      } catch (_) {
        // Already stopped.
      }
    }
  }

  Future<void> setRate(double rate) async {
    try {
      await speaker.setRate(rate);
    } catch (_) {
      // The voice keeps its own speed.
    }
  }

  @override
  void dispose() {
    _session++;
    _disposed = true;
    unawaited(() async {
      try {
        await speaker.stop();
        await speaker.dispose();
      } catch (_) {
        // Gone already.
      }
    }());
    super.dispose();
  }
}
