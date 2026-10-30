import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/audio_progress.dart';

/// Audio files Chapterly can play.
const audioExtensions = [
  'm4b', 'm4a', 'mp4', 'aac', 'mp3', 'ogg', 'oga', 'opus', 'flac', 'wav',
];

/// Whether [name] looks like an audio file Chapterly can play.
bool isAudioFileName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return audioExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Compares file names the way people expect: "2 Intro" before "10 End".
int naturalCompare(String a, String b) {
  final pattern = RegExp(r'(\d+)|(\D+)');
  final partsA = pattern.allMatches(a.toLowerCase()).toList();
  final partsB = pattern.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < partsA.length && i < partsB.length; i++) {
    final x = partsA[i].group(0)!;
    final y = partsB[i].group(0)!;
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final result = nx != null && ny != null
        ? (nx != ny ? nx.compareTo(ny) : x.length.compareTo(y.length))
        : x.compareTo(y);
    if (result != 0) return result;
  }
  return partsA.length.compareTo(partsB.length);
}

/// A file name without its folder and extension, as a chapter title.
String trackTitle(String name) {
  final slash = name.lastIndexOf(RegExp(r'[/\\]'));
  final base = slash >= 0 ? name.substring(slash + 1) : name;
  final dot = base.lastIndexOf('.');
  return (dot > 0 ? base.substring(0, dot) : base).trim();
}

/// One audio file of a book.
class AudioTrack {
  const AudioTrack({required this.location, required this.name, this.lengthMs});

  /// A file path on Windows, or a content:// address on Android.
  final String location;
  final String name;
  final int? lengthMs;

  AudioTrack withLength(int? ms) =>
      AudioTrack(location: location, name: name, lengthMs: ms);

  Map<String, Object?> toJson() =>
      {'location': location, 'name': name, 'lengthMs': lengthMs};

  static AudioTrack? fromJson(Object? value) {
    if (value is! Map) return null;
    final location = value['location'];
    final name = value['name'];
    if (location is! String || name is! String) return null;
    final length = value['lengthMs'];
    return AudioTrack(
      location: location,
      name: name,
      lengthMs: length is int && length > 0 ? length : null,
    );
  }
}

/// A chapter: which file it is in and where it starts in that file.
class AudioChapter {
  const AudioChapter({
    required this.title,
    required this.track,
    required this.startMs,
  });

  final String title;
  final int track;
  final int startMs;

  Map<String, Object?> toJson() =>
      {'title': title, 'track': track, 'startMs': startMs};

  static AudioChapter? fromJson(Object? value) {
    if (value is! Map) return null;
    final title = value['title'];
    final track = value['track'];
    final start = value['startMs'];
    if (title is! String || track is! int || start is! int) return null;
    return AudioChapter(title: title, track: track, startMs: start);
  }
}

/// The audio for one book on this device: its files and chapters.
class AudioLink {
  const AudioLink({required this.tracks, this.chapters = const []});

  final List<AudioTrack> tracks;

  /// Chapters found in the file. A book made of several files without
  /// chapters of its own uses one chapter per file (see [allChapters]).
  final List<AudioChapter> chapters;

  /// The whole length, or null while any file's length is unknown.
  int? get lengthMs {
    var total = 0;
    for (final track in tracks) {
      final length = track.lengthMs;
      if (length == null) return null;
      total += length;
    }
    return total;
  }

  /// The chapters to show: the file's own, or one per file.
  List<AudioChapter> get allChapters {
    if (chapters.isNotEmpty) return chapters;
    if (tracks.length < 2) return const [];
    return [
      for (var i = 0; i < tracks.length; i++)
        AudioChapter(title: trackTitle(tracks[i].name), track: i, startMs: 0),
    ];
  }

  /// Milliseconds from the start of the book to the start of [track]. Files
  /// of unknown length count as 0.
  int startOfTrack(int track) {
    var total = 0;
    for (var i = 0; i < track && i < tracks.length; i++) {
      total += tracks[i].lengthMs ?? 0;
    }
    return total;
  }

  /// The progress to save for a place in the book.
  AudioProgress progressAt(int track, int trackMs) => AudioProgress(
        positionMs: startOfTrack(track) + trackMs,
        lengthMs: lengthMs,
        track: track,
        trackMs: trackMs,
        trackCount: tracks.length,
      );

  /// Where to carry on from [progress] (which may have been saved on another
  /// device with other copies of the files).
  ({int track, int trackMs}) resumeAt(AudioProgress? progress) {
    if (progress == null || tracks.isEmpty) return (track: 0, trackMs: 0);
    if (progress.trackCount == tracks.length &&
        progress.track < tracks.length) {
      return (track: progress.track, trackMs: progress.trackMs);
    }
    var left = progress.positionMs;
    for (var i = 0; i < tracks.length; i++) {
      final length = tracks[i].lengthMs;
      if (length == null) return (track: i, trackMs: left);
      if (left < length || i == tracks.length - 1) {
        return (track: i, trackMs: left < length ? left : length);
      }
      left -= length;
    }
    return (track: 0, trackMs: 0);
  }

  /// The chapter playing at a place in the book, or null without chapters.
  int? chapterAt(int track, int trackMs) {
    final list = allChapters;
    int? found;
    for (var i = 0; i < list.length; i++) {
      final chapter = list[i];
      if (chapter.track < track ||
          (chapter.track == track && chapter.startMs <= trackMs)) {
        found = i;
      } else {
        break;
      }
    }
    return found ?? (list.isEmpty ? null : 0);
  }

  AudioLink withTrackLength(int track, int ms) => AudioLink(
        tracks: [
          for (var i = 0; i < tracks.length; i++)
            i == track ? tracks[i].withLength(ms) : tracks[i],
        ],
        chapters: chapters,
      );

  Map<String, Object?> toJson() => {
        'tracks': [for (final t in tracks) t.toJson()],
        'chapters': [for (final c in chapters) c.toJson()],
      };

  static AudioLink? fromJson(Object? value) {
    if (value is! Map) return null;
    final tracks = [
      if (value['tracks'] case final List list)
        for (final item in list) ?AudioTrack.fromJson(item),
    ];
    if (tracks.isEmpty) return null;
    return AudioLink(
      tracks: tracks,
      chapters: [
        if (value['chapters'] case final List list)
          for (final item in list) ?AudioChapter.fromJson(item),
      ],
    );
  }
}

/// Which audio belongs to which book on this device, and the playback speed.
/// Kept in a small JSON file next to the library. It is never synced or
/// backed up: the files are only on this device.
class AudioLibrary extends ChangeNotifier {
  AudioLibrary({this.file});

  /// Where it is saved, or null to keep it in memory only (tests).
  final File? file;
  final _links = <String, AudioLink>{};
  double _speed = 1.0;

  static Future<AudioLibrary> load(File file) async {
    final library = AudioLibrary(file: file);
    try {
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          final links = data['links'];
          if (links is Map) {
            for (final entry in links.entries) {
              final link = AudioLink.fromJson(entry.value);
              if (link != null) library._links[entry.key.toString()] = link;
            }
          }
          final speed = data['speed'];
          if (speed is num && speed >= 0.5 && speed <= 3) {
            library._speed = speed.toDouble();
          }
        }
      }
    } catch (_) {
      // A damaged file only loses the links; the books are untouched.
    }
    return library;
  }

  AudioLink? linkFor(String bookId) => _links[bookId];

  bool hasAudio(String bookId) => _links.containsKey(bookId);

  double get speed => _speed;

  Future<void> setLink(String bookId, AudioLink link) async {
    _links[bookId] = link;
    notifyListeners();
    await _save();
  }

  Future<void> remove(String bookId) async {
    if (_links.remove(bookId) == null) return;
    notifyListeners();
    await _save();
  }

  /// Remembers a file's length once the player knows it exactly.
  Future<void> setTrackLength(String bookId, int track, int ms) async {
    final link = _links[bookId];
    if (link == null || track < 0 || track >= link.tracks.length) return;
    _links[bookId] = link.withTrackLength(track, ms);
    notifyListeners();
    await _save();
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final target = file;
    if (target == null) return;
    try {
      await target.parent.create(recursive: true);
      await target.writeAsString(jsonEncode({
        'speed': _speed,
        'links': {
          for (final entry in _links.entries) entry.key: entry.value.toJson(),
        },
      }));
    } catch (_) {
      // Not saved; it is tried again on the next change.
    }
  }
}
