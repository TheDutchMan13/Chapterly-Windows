import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// The player underneath [ListenController]. The app uses [JustAudioEngine]
/// (ExoPlayer on Android, media_kit on Windows); tests use a fake.
abstract interface class AudioEngine {
  /// Loads the files of one book and goes to [index] at [position].
  Future<void> load(
    List<Uri> tracks, {
    required int index,
    required Duration position,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seek(int index, Duration position);
  Future<void> setSpeed(double speed);
  Future<void> stop();
  Future<void> dispose();

  bool get playing;
  int get index;
  Duration get position;

  /// The length of the file playing now, once known.
  Duration? get duration;

  /// Fires when anything above changes, and regularly while playing.
  Stream<void> get changes;

  /// Fires when the last file has played to the end.
  Stream<void> get completed;
}

class JustAudioEngine implements AudioEngine {
  JustAudioEngine() {
    void changed(Object? _) => _changes.add(null);
    _subscriptions.addAll([
      _player.playingStream.listen(changed),
      _player.currentIndexStream.listen(changed),
      _player.durationStream.listen(changed),
      _player.positionStream.listen(changed),
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) _completed.add(null);
        _changes.add(null);
      }),
    ]);
  }

  final _player = AudioPlayer();
  final _changes = StreamController<void>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  Future<void> load(
    List<Uri> tracks, {
    required int index,
    required Duration position,
  }) async {
    await _player.setAudioSources(
      [for (final uri in tracks) AudioSource.uri(uri)],
      initialIndex: index,
      initialPosition: position,
    );
  }

  // just_audio's play() only finishes when playback stops, so it is not
  // waited for.
  @override
  Future<void> play() async {
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(int index, Duration position) =>
      _player.seek(position, index: index);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _changes.close();
    await _completed.close();
  }

  @override
  bool get playing => _player.playing;

  @override
  int get index => _player.currentIndex ?? 0;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<void> get completed => _completed.stream;
}
