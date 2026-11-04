import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'update_check.dart';

// Windows app only.

/// The installer could not be downloaded.
class UpdateDownloadFailure implements Exception {
  const UpdateDownloadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads the update's installer into a new folder of its own in the
/// temporary folder, telling [onProgress] how far it is (0.0 to 1.0, or
/// null while the size is not known). Stops early when [cancelled] says so
/// (and returns null). The file is checked against the SHA-256 GitHub
/// gives for it; one that doesn't match is deleted, never run.
Future<File?> downloadInstaller(
  AvailableUpdate update, {
  void Function(double? fraction)? onProgress,
  bool Function()? cancelled,
  http.Client? client,
  Directory? folder,
}) async {
  final url = update.installerUrl;
  final expected = update.installerSha256;
  if (url == null || expected == null) {
    throw const UpdateDownloadFailure('No installer found.');
  }
  final httpClient = client ?? http.Client();
  // Each download gets its own folder, so two can never write one file.
  final Directory place;
  try {
    place = await (folder ?? Directory.systemTemp)
        .createTemp('chapterly-update-');
  } catch (_) {
    if (client == null) httpClient.close();
    throw const UpdateDownloadFailure("Couldn't save the update.");
  }
  final target = File(
    '${place.path}${Platform.pathSeparator}'
    'Chapterly-Setup-${update.version}.exe',
  );
  final digests = _DigestSink();
  final hasher = sha256.startChunkedConversion(digests);
  IOSink? sink;
  try {
    final request = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = 'Chapterly-Windows';
    final response =
        await httpClient.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw UpdateDownloadFailure(
        'GitHub answered ${response.statusCode}. Try again later.',
      );
    }
    final total = response.contentLength ?? update.installerBytes;
    var received = 0;
    final out = target.openWrite();
    sink = out;
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 60))) {
      if (cancelled?.call() ?? false) {
        sink = null;
        await out.close();
        await _remove(place);
        return null;
      }
      out.add(chunk);
      hasher.add(chunk);
      received += chunk.length;
      onProgress?.call(total == null || total <= 0 ? null : received / total);
    }
    sink = null;
    await out.close();
    hasher.close();
    // An installer is several megabytes; anything tiny is an error page.
    if (await target.length() < 1024 * 1024) {
      await _remove(place);
      throw const UpdateDownloadFailure('The download was not complete.');
    }
    if (digests.value?.toString() != expected.toLowerCase()) {
      await _remove(place);
      throw const UpdateDownloadFailure(
        "The download doesn't match the release on GitHub, so it wasn't "
        'installed. Try again, or get it from the release page.',
      );
    }
    return target;
  } on UpdateDownloadFailure {
    rethrow;
  } catch (_) {
    await sink?.close();
    sink = null;
    await _remove(place);
    throw const UpdateDownloadFailure(
      "Couldn't download the update. Check your connection.",
    );
  } finally {
    await sink?.close();
    if (client == null) httpClient.close();
  }
}

Future<void> _remove(Directory place) async {
  try {
    await place.delete(recursive: true);
  } catch (_) {
    // Left for Windows to clear with the other temporary files.
  }
}

/// Collects the one digest a hash gives when it is closed.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Starts the installer quietly (it shows only a progress bar), closing
/// Chapterly so its files can be replaced; the installer opens Chapterly
/// again when it is done.
Future<void> startInstaller(File installer) async {
  await Process.start(
    installer.path,
    const ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
    mode: ProcessStartMode.detached,
  );
}
