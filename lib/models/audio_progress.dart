/// Where you are in an audiobook. It is part of the book, so it syncs and
/// you can carry on listening on another device. The audio files themselves
/// stay on each device (see audio_library.dart).
class AudioProgress {
  const AudioProgress({
    required this.positionMs,
    this.lengthMs,
    this.track = 0,
    this.trackMs = 0,
    this.trackCount = 1,
  });

  /// From the start of the whole book.
  final int positionMs;

  /// The length of the whole book, when known.
  final int? lengthMs;

  /// Which file (0 is the first) for a book made of several files, and how
  /// far into that file.
  final int track;
  final int trackMs;

  /// How many files the book had where this was saved. When another device
  /// has the same number of files, it resumes by file; otherwise by
  /// [positionMs].
  final int trackCount;

  /// From 0 to 1, or null when the length is not known.
  double? get fraction {
    final length = lengthMs;
    if (length == null || length <= 0) return null;
    final value = positionMs / length;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  Map<String, Object?> toJson() => {
        'positionMs': positionMs,
        'lengthMs': lengthMs,
        'track': track,
        'trackMs': trackMs,
        'trackCount': trackCount,
      };

  /// Reads [toJson]. Null for anything that is not a progress.
  static AudioProgress? fromJson(Object? value) {
    if (value is! Map) return null;
    final position = value['positionMs'];
    if (position is! int) return null;
    int orZero(Object? v) => v is int && v >= 0 ? v : 0;
    final length = value['lengthMs'];
    final count = value['trackCount'];
    return AudioProgress(
      positionMs: position < 0 ? 0 : position,
      lengthMs: length is int && length > 0 ? length : null,
      track: orZero(value['track']),
      trackMs: orZero(value['trackMs']),
      trackCount: count is int && count > 0 ? count : 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioProgress &&
      other.positionMs == positionMs &&
      other.lengthMs == lengthMs &&
      other.track == track &&
      other.trackMs == trackMs &&
      other.trackCount == trackCount;

  @override
  int get hashCode =>
      Object.hash(positionMs, lengthMs, track, trackMs, trackCount);
}

/// "3 h 5 min", "12 min" or "40 s", for listening times.
String formatListenTime(int ms) {
  final totalSeconds = ms ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours > 0) return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  if (minutes > 0) return '$minutes min';
  return '$totalSeconds s';
}

/// "1:02:03" or "2:03", for the player's clock.
String formatPlayerClock(Duration duration) {
  final total = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '$minutes:${two(seconds)}';
}
