import 'audio_library.dart';
import 'audio_probe.dart';

/// A file the user picked.
class PickedFile {
  const PickedFile({required this.location, required this.name});

  /// A file path on Windows, or a content:// address on Android.
  final String location;
  final String name;
}

/// Picking and reading audio files. Each app has its own: Windows uses file
/// paths, Android uses the system file picker and content:// addresses
/// that the app keeps permission to read.
abstract interface class AudioFiles {
  /// One audio file (such as an .m4b), or null if cancelled.
  Future<List<PickedFile>?> pickFile();

  /// Every audio file in a folder (such as one .mp3 per chapter), or null
  /// if cancelled.
  Future<List<PickedFile>?> pickFolder();

  /// For reading lengths and chapters.
  ByteSource open(String location);

  /// For the player.
  Uri playable(String location);

  /// Called when a book's audio is removed, so the app can let go of its
  /// permission to read the files.
  Future<void> release(List<String> locations);
}

/// Turns picked files into a book's audio: audio files only, in name order
/// ("2" before "10"), with their lengths, and the chapters inside a single
/// file. Null when there is no audio file among them.
Future<AudioLink?> buildAudioLink(
  AudioFiles files,
  List<PickedFile> picked,
) async {
  final audio = [
    for (final file in picked)
      if (isAudioFileName(file.name)) file,
  ]..sort((a, b) => naturalCompare(a.name, b.name));
  if (audio.isEmpty) return null;
  final tracks = <AudioTrack>[];
  var chapters = <AudioChapter>[];
  for (final file in audio) {
    final source = files.open(file.location);
    try {
      final info = await probeAudio(source);
      tracks.add(AudioTrack(
        location: file.location,
        name: file.name,
        lengthMs: info.lengthMs,
      ));
      if (audio.length == 1) {
        chapters = [
          for (final chapter in info.chapters)
            AudioChapter(
              title: chapter.title.isEmpty
                  ? 'Chapter ${info.chapters.indexOf(chapter) + 1}'
                  : chapter.title,
              track: 0,
              startMs: chapter.startMs,
            ),
        ];
      }
    } finally {
      await source.close();
    }
  }
  return AudioLink(tracks: tracks, chapters: chapters);
}
