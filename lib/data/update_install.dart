import 'dart:async';
import 'dart:io';

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

/// Downloads the update's installer into the temporary folder, telling
/// [onProgress] how far it is (0.0 to 1.0, or null while the size is not
/// known). Stops early when [cancelled] says so (and returns null).
Future<File?> downloadInstaller(
  AvailableUpdate update, {
  void Function(double? fraction)? onProgress,
  bool Function()? cancelled,
  http.Client? client,
  Directory? folder,
}) async {
  final url = update.installerUrl;
  if (url == null) throw const UpdateDownloadFailure('No installer found.');
  final httpClient = client ?? http.Client();
  final target = File(
    '${(folder ?? Directory.systemTemp).path}${Platform.pathSeparator}'
    'Chapterly-Setup-${update.version}.exe',
  );
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
        await target.delete();
        return null;
      }
      out.add(chunk);
      received += chunk.length;
      onProgress?.call(total == null || total <= 0 ? null : received / total);
    }
    sink = null;
    await out.close();
    // An installer is several megabytes; anything tiny is an error page.
    if (await target.length() < 1024 * 1024) {
      await target.delete();
      throw const UpdateDownloadFailure('The download was not complete.');
    }
    return target;
  } on UpdateDownloadFailure {
    rethrow;
  } catch (_) {
    throw const UpdateDownloadFailure(
      "Couldn't download the update. Check your connection.",
    );
  } finally {
    await sink?.close();
    if (client == null) httpClient.close();
  }
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
