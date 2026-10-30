import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'audio_files.dart';
import 'audio_library.dart';
import 'audio_probe.dart';

/// Audio files on Windows are plain file paths.
class WindowsAudioFiles implements AudioFiles {
  const WindowsAudioFiles();

  @override
  Future<List<PickedFile>?> pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Audiobooks', extensions: audioExtensions),
      ],
    );
    if (file == null) return null;
    return [PickedFile(location: file.path, name: file.name)];
  }

  /// Every audio file in the folder and its subfolders (such as CD 1 and
  /// CD 2). The name used for ordering includes the subfolder.
  @override
  Future<List<PickedFile>?> pickFolder() async {
    final folder = await getDirectoryPath();
    if (folder == null) return null;
    final files = <PickedFile>[];
    await for (final entity in Directory(folder).list(recursive: true)) {
      if (entity is! File || !isAudioFileName(entity.path)) continue;
      files.add(PickedFile(
        location: entity.path,
        name: p.relative(entity.path, from: folder),
      ));
    }
    return files;
  }

  @override
  ByteSource open(String location) => FileByteSource(location);

  @override
  Uri playable(String location) => Uri.file(location);

  @override
  Future<void> release(List<String> locations) async {}
}
