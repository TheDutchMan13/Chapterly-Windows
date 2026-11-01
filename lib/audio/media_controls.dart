import 'dart:async';
import 'dart:io';

import 'package:flutter_media_session/flutter_media_session.dart';

import '../data/cover_image.dart';
import 'audio_library.dart';
import 'listen_controller.dart';

// Windows app only.

/// The app's id for Windows. The installer gives the Start menu shortcut the
/// same id, so the media pop-up shows "Chapterly" with its icon.
const chapterlyAppUserModelId = 'HansDeKryger.Chapterly';

/// The place in [link] that is [positionMs] from the start of the book.
({int track, int trackMs}) placeInBook(AudioLink link, int positionMs) {
  var start = 0;
  for (var i = 0; i < link.tracks.length; i++) {
    final length = link.tracks[i].lengthMs;
    final last = i == link.tracks.length - 1;
    if (length == null || last || positionMs < start + length) {
      final inTrack = positionMs - start;
      return (track: i, trackMs: inTrack < 0 ? 0 : inTrack);
    }
    start += length;
  }
  return (track: 0, trackMs: 0);
}

/// Shows the audiobook in Windows' media controls (the pop-up by the volume
/// and the lock screen) and lets the keyboard's media keys, headphone
/// buttons and those controls play, pause, skip and seek.
///
/// Previous and next go by chapter; rewind and fast forward by 30 seconds.
class SystemMediaControls {
  SystemMediaControls(this.controller);

  final ListenController controller;

  bool _started = false;
  String? _bookId;
  int? _chapter;
  bool? _playing;
  int _sentPositionMs = -1;
  DateTime _sentAt = DateTime.fromMillisecondsSinceEpoch(0);
  File? _coverFile;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final session = FlutterMediaSession();
    try {
      await session.setWindowsAppUserModelId(chapterlyAppUserModelId);
      await session.activate();
      session.setActionHandler(
        onPlay: controller.play,
        onPause: controller.pause,
        onStop: controller.pause,
        onSkipToNext: controller.nextChapter,
        onSkipToPrevious: controller.previousChapter,
        onFastForward: () => controller.skip(const Duration(seconds: 30)),
        onRewind: () => controller.skip(const Duration(seconds: -30)),
        onSeekTo: _seekInBook,
      );
      await FlutterMediaSessionPlatform.instance.updateAvailableActions({
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.fastForward,
        MediaAction.rewind,
        MediaAction.seekTo,
      });
    } catch (_) {
      // Older Windows, or the controls are not available: the app works
      // without them.
      return;
    }
    controller.addListener(_sync);
    _sync();
  }

  Future<void> _seekInBook(Duration position) async {
    final link = controller.link;
    if (link == null) return;
    final place = placeInBook(link, position.inMilliseconds);
    await controller.seekTo(place.track, Duration(milliseconds: place.trackMs));
  }

  /// Sends what changed: the book and chapter, playing or paused, and the
  /// place (when it jumped, or every few seconds while playing).
  void _sync() {
    final book = controller.book;
    if (!controller.active || book == null) {
      if (_bookId != null) {
        _bookId = null;
        _playing = null;
        unawaited(_send(() => FlutterMediaSessionPlatform.instance
            .updatePlaybackState(
                const PlaybackState(status: PlaybackStatus.idle))));
      }
      return;
    }
    final chapter = controller.chapterIndex;
    if (book.id != _bookId || chapter != _chapter) {
      final newBook = book.id != _bookId;
      _bookId = book.id;
      _chapter = chapter;
      unawaited(_sendMetadata(newBook: newBook));
    }
    final progress = controller.progress;
    final position = progress?.positionMs ?? 0;
    final playing = controller.playing;
    final now = DateTime.now();
    final expected = _playing == true
        ? _sentPositionMs +
            (now.difference(_sentAt).inMilliseconds * controller.speed).round()
        : _sentPositionMs;
    final jumped = (position - expected).abs() > 2000;
    final due = playing && now.difference(_sentAt) > const Duration(seconds: 5);
    if (playing == _playing && !jumped && !due) return;
    _playing = playing;
    _sentPositionMs = position;
    _sentAt = now;
    unawaited(_send(() => FlutterMediaSessionPlatform.instance
        .updatePlaybackState(PlaybackState(
          status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
          position: Duration(milliseconds: position),
          speed: controller.speed,
        ))));
  }

  Future<void> _sendMetadata({required bool newBook}) async {
    final book = controller.book;
    if (book == null) return;
    final chapters = controller.chapters;
    final chapter = controller.chapterIndex;
    final length = controller.link?.lengthMs;
    if (newBook) _coverFile = await _coverFor(book.id, book.coverUrl);
    final cover = book.coverUrl;
    await _send(() => FlutterMediaSessionPlatform.instance.updateMetadata(
          MediaMetadata(
            title: book.title,
            artist: book.author,
            album: chapter != null && chapter < chapters.length
                ? chapters[chapter].title
                : book.title,
            artworkUri: _coverFile?.path ??
                (cover != null && cover.startsWith('https://') ? cover : null),
            duration: length == null ? null : Duration(milliseconds: length),
          ),
        ));
  }

  /// Windows reads the picture from a file or a web address. A cover kept
  /// inside the book (a data: address) is written to a small file first.
  Future<File?> _coverFor(String bookId, String? coverUrl) async {
    if (coverUrl == null || !isDataCover(coverUrl)) return null;
    final bytes = bytesFromDataCover(coverUrl);
    if (bytes == null) return null;
    try {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'chapterly-cover-${bookId.hashCode.toUnsigned(32)}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _send(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {
      // The media controls are a nice extra; playing goes on without them.
    }
  }
}

/// The media controls for the whole app, set up in main.dart.
class MediaControlsHolder {
  MediaControlsHolder._();

  static SystemMediaControls? controls;
}
