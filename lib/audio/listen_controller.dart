import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/book_repository.dart';
import '../models/audio_progress.dart';
import '../models/book.dart';
import 'audio_engine.dart';
import 'audio_files.dart';
import 'audio_library.dart';

/// Plays one book's audio at a time. Saves where you are every few seconds
/// (so it syncs), adds the time you listen to the book's reading log, and
/// has a sleep timer and chapter controls.
class ListenController extends ChangeNotifier {
  ListenController({
    required this.repository,
    required this.library,
    required this.files,
    AudioEngine Function()? engine,
    DateTime Function()? now,
    this.saveEvery = const Duration(seconds: 15),
    this.logEvery = const Duration(minutes: 5),
  })  : _makeEngine = engine ?? JustAudioEngine.new,
        _now = now ?? DateTime.now;

  final BookRepository repository;
  final AudioLibrary library;
  final AudioFiles files;
  final Duration saveEvery;
  final Duration logEvery;
  final AudioEngine Function() _makeEngine;
  final DateTime Function() _now;

  /// Called when a book has been listened to the end.
  void Function(Book book)? onFinished;

  /// Windows app: going back a few seconds when you play again after a
  /// pause, more the longer the pause (see [rewindAfterPause]). Set from
  /// the settings in main.dart; off in tests.
  bool smartRewind = false;
  DateTime? _pausedAt;

  AudioEngine? _engine;
  StreamSubscription<void>? _changes;
  StreamSubscription<void>? _done;
  String? _bookId;
  bool _wasPlaying = false;
  bool _finished = false;
  Timer? _saveTimer;
  Timer? _sleepTimer;
  DateTime? _sleepAt;
  bool _sleepAtChapterEnd = false;
  int? _sleepChapter;
  DateTime? _playingSince;
  DateTime? _lastLog;
  int _unloggedMs = 0;
  AudioProgress? _lastSaved;

  /// The book playing (or paused), or null.
  String? get bookId => _bookId;
  Book? get book {
    final id = _bookId;
    return id == null ? null : repository.byId(id);
  }

  AudioLink? get link {
    final id = _bookId;
    return id == null ? null : library.linkFor(id);
  }

  bool get active => _bookId != null;
  bool get playing => _engine?.playing ?? false;
  int get track => _engine?.index ?? 0;
  Duration get trackPosition => _engine?.position ?? Duration.zero;

  /// The length of the file playing now, when known.
  Duration? get trackLength {
    final engine = _engine?.duration;
    if (engine != null && engine > Duration.zero) return engine;
    final tracks = link?.tracks;
    if (tracks == null || track >= tracks.length) return null;
    final ms = tracks[track].lengthMs;
    return ms == null ? null : Duration(milliseconds: ms);
  }

  /// Where you are in the whole book.
  AudioProgress? get progress =>
      link?.progressAt(track, trackPosition.inMilliseconds);

  List<AudioChapter> get chapters => link?.allChapters ?? const [];

  /// The chapter playing now, or null when the book has no chapters.
  int? get chapterIndex =>
      link?.chapterAt(track, trackPosition.inMilliseconds);

  /// The part of the file the current chapter covers, for the slider.
  ({Duration start, Duration end})? get chapterSpan {
    final list = chapters;
    final index = chapterIndex;
    final length = trackLength;
    if (length == null) return null;
    if (index == null) return (start: Duration.zero, end: length);
    final chapter = list[index];
    final next = index + 1 < list.length ? list[index + 1] : null;
    final start = chapter.track == track
        ? Duration(milliseconds: chapter.startMs)
        : Duration.zero;
    final end = next != null && next.track == track
        ? Duration(milliseconds: next.startMs)
        : length;
    return (start: start, end: end > start ? end : length);
  }

  double get speed => library.speed;

  /// Time left on the sleep timer, or null when it is off.
  Duration? get sleepLeft {
    final at = _sleepAt;
    if (at == null) return null;
    final left = at.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether playing stops at the end of this chapter.
  bool get sleepAtChapterEnd => _sleepAtChapterEnd;

  /// Opens a book's audio where you left off (on any device). Returns null
  /// when it worked, or the message to show.
  Future<String?> open(String bookId, {bool autoplay = true}) async {
    if (_bookId == bookId && _engine != null) {
      if (autoplay) await play();
      return null;
    }
    await close();
    final link = library.linkFor(bookId);
    final book = repository.byId(bookId);
    if (link == null || book == null) {
      return 'This book has no audio on this device.';
    }
    final engine = _makeEngine();
    final start = link.resumeAt(book.audio);
    try {
      await engine.load(
        [for (final track in link.tracks) files.playable(track.location)],
        index: start.track,
        position: Duration(milliseconds: start.trackMs),
      );
      await engine.setSpeed(library.speed);
    } catch (_) {
      await engine.dispose();
      return "Chapterly can't open the audio. The file may have been moved "
          'or deleted; add it again.';
    }
    _engine = engine;
    _bookId = bookId;
    _finished = false;
    _lastSaved = book.audio;
    // When it was last saved: the end of the last listen, roughly.
    _pausedAt = book.audio == null ? null : book.updatedAt;
    _lastLog = _now();
    _changes = engine.changes.listen((_) => _onChange());
    _done = engine.completed.listen((_) => _onCompleted());
    notifyListeners();
    if (autoplay) await play();
    return null;
  }

  /// Starts the book again from the beginning and plays it. Returns null
  /// when it worked, or the message to show.
  Future<String?> restart(String bookId) async {
    final link = library.linkFor(bookId);
    if (link == null) return 'This book has no audio on this device.';
    final engine = _engine;
    if (_bookId == bookId && engine != null) {
      _finished = false;
      await engine.seek(0, Duration.zero);
      notifyListeners();
      await play();
      return null;
    }
    await repository.setAudioProgress(bookId, link.progressAt(0, 0));
    return open(bookId);
  }

  Future<void> play() async {
    final engine = _engine;
    if (engine == null) return;
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (_finished) {
      _finished = false;
      await engine.seek(0, Duration.zero);
    } else if (smartRewind && pausedAt != null) {
      final back = rewindAfterPause(_now().difference(pausedAt));
      if (back > Duration.zero) await skip(-back);
    }
    await engine.play();
  }

  Future<void> pause() async {
    await _engine?.pause();
  }

  Future<void> toggle() => playing ? pause() : play();

  /// Jumps forward (or back, with a negative [delta]), into the next or
  /// previous file when needed.
  Future<void> skip(Duration delta) async {
    _pausedAt = null;
    final engine = _engine;
    final link = this.link;
    if (engine == null || link == null) return;
    final index = engine.index;
    final target = engine.position + delta;
    if (target.isNegative) {
      if (index == 0) return engine.seek(0, Duration.zero);
      final previous = link.tracks[index - 1].lengthMs;
      final position = previous == null
          ? Duration.zero
          : Duration(milliseconds: previous) + target;
      return engine.seek(
        index - 1,
        position.isNegative ? Duration.zero : position,
      );
    }
    final length = trackLength;
    if (length != null && target >= length) {
      if (index + 1 < link.tracks.length) {
        return engine.seek(index + 1, target - length);
      }
      return engine.seek(index, length);
    }
    await engine.seek(index, target);
  }

  /// Jumps to a place in the book: a file and where in it.
  Future<void> seekTo(int track, Duration position) async {
    _pausedAt = null;
    final engine = _engine;
    final link = this.link;
    if (engine == null || link == null) return;
    if (track < 0 || track >= link.tracks.length) return;
    _finished = false;
    await engine.seek(
      track,
      position < Duration.zero ? Duration.zero : position,
    );
    notifyListeners();
  }

  /// Moves within the file playing now.
  Future<void> seekInTrack(Duration position) async {
    _pausedAt = null;
    await _engine?.seek(
      track,
      position < Duration.zero ? Duration.zero : position,
    );
    notifyListeners();
  }

  Future<void> goToChapter(int index) async {
    _pausedAt = null;
    final list = chapters;
    if (index < 0 || index >= list.length) return;
    final chapter = list[index];
    await _engine?.seek(chapter.track, Duration(milliseconds: chapter.startMs));
    notifyListeners();
    await _save();
  }

  Future<void> nextChapter() async {
    final index = chapterIndex;
    if (index != null && index + 1 < chapters.length) {
      await goToChapter(index + 1);
    }
  }

  /// Back to the start of this chapter, or to the previous one when this
  /// one has only just begun.
  Future<void> previousChapter() async {
    final index = chapterIndex;
    if (index == null) return;
    final chapter = chapters[index];
    final into = chapter.track == track
        ? trackPosition.inMilliseconds - chapter.startMs
        : trackPosition.inMilliseconds;
    await goToChapter(into > 3000 || index == 0 ? index : index - 1);
  }

  Future<void> setSpeed(double speed) async {
    await library.setSpeed(speed);
    await _engine?.setSpeed(speed);
    notifyListeners();
  }

  /// Stops playing after [after], or turns the timer off when null.
  void setSleepTimer(Duration? after) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt = null;
    _sleepAtChapterEnd = false;
    _sleepChapter = null;
    if (after != null) {
      _sleepAt = _now().add(after);
      _sleepTimer = Timer(after, () {
        _sleepAt = null;
        _sleepTimer = null;
        pause();
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Stops playing when this chapter ends.
  void sleepAtEndOfChapter() {
    setSleepTimer(null);
    _sleepAtChapterEnd = true;
    _sleepChapter = chapterIndex;
    notifyListeners();
  }

  /// Saves where you are and the time listened, and closes the player.
  Future<void> close() async {
    final engine = _engine;
    if (engine == null) return;
    _countListening();
    await _save();
    await _log(flush: true);
    _saveTimer?.cancel();
    _saveTimer = null;
    setSleepTimer(null);
    await _changes?.cancel();
    await _done?.cancel();
    _changes = null;
    _done = null;
    _engine = null;
    _bookId = null;
    _wasPlaying = false;
    _playingSince = null;
    try {
      await engine.stop();
      await engine.dispose();
    } catch (_) {
      // Already gone.
    }
    notifyListeners();
  }

  /// Forgets a book's audio on this device. Where you are in it is kept.
  Future<void> removeAudio(String bookId) async {
    if (_bookId == bookId) await close();
    final link = library.linkFor(bookId);
    await library.remove(bookId);
    if (link != null) {
      await files.release([for (final t in link.tracks) t.location]);
    }
  }

  // ---- inside

  void _onChange() {
    final engine = _engine;
    final id = _bookId;
    if (engine == null || id == null) return;
    final nowPlaying = engine.playing;
    if (nowPlaying && !_wasPlaying) {
      _playingSince = _now();
      _saveTimer?.cancel();
      _saveTimer = Timer.periodic(saveEvery, (_) => _tick());
    } else if (!nowPlaying && _wasPlaying) {
      _pausedAt = _now();
      _countListening();
      _saveTimer?.cancel();
      _saveTimer = null;
      unawaited(_save());
      unawaited(_log());
    }
    _wasPlaying = nowPlaying;

    // Learn each file's exact length from the player.
    final duration = engine.duration;
    final link = library.linkFor(id);
    if (duration != null &&
        duration > Duration.zero &&
        link != null &&
        engine.index < link.tracks.length) {
      final known = link.tracks[engine.index].lengthMs;
      final ms = duration.inMilliseconds;
      if (known == null || (known - ms).abs() > 2000) {
        unawaited(library.setTrackLength(id, engine.index, ms));
      }
    }

    if (_sleepAtChapterEnd && nowPlaying) {
      final current = chapterIndex;
      if (current != null && current != _sleepChapter) {
        _sleepAtChapterEnd = false;
        _sleepChapter = null;
        unawaited(pause());
      }
    }
    notifyListeners();
  }

  void _onCompleted() {
    final id = _bookId;
    final link = this.link;
    if (id == null || link == null) return;
    _countListening();
    _finished = true;
    final last = link.tracks.length - 1;
    final end = link.tracks[last].lengthMs ?? trackPosition.inMilliseconds;
    final progress = link.progressAt(last, end);
    _lastSaved = progress;
    unawaited(repository.setAudioProgress(id, progress));
    unawaited(_log(flush: true));
    unawaited(_engine?.pause());
    final finished = book;
    if (finished != null) onFinished?.call(finished);
  }

  Future<void> _tick() async {
    _countListening();
    await _save();
    final last = _lastLog;
    if (last == null || _now().difference(last) >= logEvery) await _log();
  }

  /// Adds the time since playing started (or since the last count).
  void _countListening() {
    final since = _playingSince;
    if (since == null) return;
    final now = _now();
    _unloggedMs += now.difference(since).inMilliseconds;
    _playingSince = (_engine?.playing ?? false) ? now : null;
  }

  Future<void> _save() async {
    final id = _bookId;
    final progress = this.progress;
    if (id == null || progress == null || progress == _lastSaved) return;
    _lastSaved = progress;
    await repository.setAudioProgress(id, progress);
  }

  /// Writes whole minutes listened to the reading log. [flush] also writes
  /// a last part of half a minute or more.
  Future<void> _log({bool flush = false}) async {
    final id = _bookId;
    if (id == null) return;
    var minutes = _unloggedMs ~/ 60000;
    var rest = _unloggedMs - minutes * 60000;
    if (flush && rest >= 30000) {
      minutes++;
      rest = 0;
    }
    _lastLog = _now();
    if (minutes <= 0) return;
    _unloggedMs = flush ? 0 : rest;
    await repository.addListeningMinutes(id, _now(), minutes);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _sleepTimer?.cancel();
    _changes?.cancel();
    _done?.cancel();
    _engine?.dispose();
    super.dispose();
  }
}

/// Windows app: how far to go back when playing again after a pause of
/// [paused]: nothing for a few seconds, then 2 seconds, up to 30 seconds
/// after a day or more, so you pick up the thread again.
Duration rewindAfterPause(Duration paused) {
  final seconds = paused.inSeconds;
  if (seconds < 10) return Duration.zero;
  if (seconds < 60) return const Duration(seconds: 2);
  if (seconds < 10 * 60) return const Duration(seconds: 5);
  if (seconds < 60 * 60) return const Duration(seconds: 10);
  if (seconds < 24 * 60 * 60) return const Duration(seconds: 20);
  return const Duration(seconds: 30);
}
