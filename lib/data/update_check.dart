import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_info.dart';
import 'app_settings.dart';

/// GitHub's page about the newest release. Only the version number and the
/// link are read; nothing about you or your books is sent.
const latestReleaseApi =
    'https://api.github.com/repos/TheDutchMan13/Chapterly-Windows/releases/latest';

/// Where this app's releases live. A link anywhere else is not used.
const _releasePages = 'https://github.com/TheDutchMan13/Chapterly-Windows/';
const _releaseFiles =
    'https://github.com/TheDutchMan13/Chapterly-Windows/releases/download/';

class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.url,
    this.installerUrl,
    this.installerBytes,
    this.installerSha256,
  });

  /// Such as 1.2.0.
  final String version;

  /// The release page on GitHub.
  final String url;

  /// The release's `Chapterly-Setup-<version>.exe`, when it has one, so the
  /// update can be downloaded and installed from inside Chapterly.
  final String? installerUrl;

  /// Its size, for the progress bar.
  final int? installerBytes;

  /// The SHA-256 GitHub gives for the file (64 hex characters). The
  /// download is checked against it before it is run, and an installer
  /// without one is never downloaded here.
  final String? installerSha256;
}

final _installerName = RegExp(r'^Chapterly-Setup-[0-9][0-9.]*\.exe$');
final _sha256Digest = RegExp(r'^sha256:([0-9a-fA-F]{64})$');

/// The installer among a release's files: the right name, from this app's
/// releases on GitHub, with a checksum to check it against.
({String url, int? bytes, String sha256})? _installerAsset(Object? assets) {
  if (assets is! List) return null;
  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = asset['name'];
    final url = asset['browser_download_url'];
    final size = asset['size'];
    final digest = asset['digest'];
    final sha = digest is String ? _sha256Digest.firstMatch(digest) : null;
    if (name is String &&
        url is String &&
        sha != null &&
        _installerName.hasMatch(name) &&
        url.startsWith(_releaseFiles) &&
        !url.contains('..')) {
      return (
        url: url,
        bytes: size is int ? size : null,
        sha256: sha.group(1)!.toLowerCase(),
      );
    }
  }
  return null;
}

/// GitHub could not be asked.
class UpdateCheckFailure implements Exception {
  const UpdateCheckFailure();
}

List<int>? _versionParts(String text) {
  var clean = text.trim();
  if (clean.startsWith('v') || clean.startsWith('V')) clean = clean.substring(1);
  clean = clean.split('+').first.split('-').first;
  final parts = clean.split('.');
  if (parts.length > 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0) return null;
    numbers.add(value);
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}

/// Whether [latest] (such as "v1.2.0") is newer than [current] ("1.1.0").
bool isNewerVersion(String latest, String current) {
  final a = _versionParts(latest);
  final b = _versionParts(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Reads GitHub's reply. Returns the update when it is newer than [current].
AvailableUpdate? parseLatestRelease(String body, {String current = appVersion}) {
  Object? data;
  try {
    data = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (data is! Map) return null;
  final tag = data['tag_name'];
  final url = data['html_url'];
  if (tag is! String || url is! String) return null;
  if (!url.startsWith(_releasePages)) return null;
  if (data['draft'] == true || data['prerelease'] == true) return null;
  if (!isNewerVersion(tag, current)) return null;
  // Built from the numbers only: the version names a file on disk, so
  // nothing else from the tag may end up in it.
  final version = _versionParts(tag)!.join('.');
  final installer = _installerAsset(data['assets']);
  return AvailableUpdate(
    version: version,
    url: url,
    installerUrl: installer?.url,
    installerBytes: installer?.bytes,
    installerSha256: installer?.sha256,
  );
}

/// Once a day at most.
bool updateCheckDue(DateTime? last, DateTime now) =>
    last == null || now.difference(last) >= const Duration(days: 1);

/// Asks GitHub for the newest release. Returns null when this is the newest
/// (or there are no releases yet). Throws [UpdateCheckFailure] when GitHub
/// cannot be reached.
Future<AvailableUpdate?> checkForUpdate({
  http.Client? client,
  String current = appVersion,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(
      Uri.parse(latestReleaseApi),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Chapterly-Windows/$current',
      },
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw const UpdateCheckFailure();
    return parseLatestRelease(response.body, current: current);
  } on UpdateCheckFailure {
    rethrow;
  } catch (_) {
    throw const UpdateCheckFailure();
  } finally {
    if (client == null) httpClient.close();
  }
}

/// The daily check when Chapterly opens: only when switched on and not done
/// in the last day. Never throws.
Future<AvailableUpdate?> checkForUpdateIfDue(
  AppSettings settings, {
  http.Client? client,
  DateTime? now,
  String current = appVersion,
}) async {
  final time = now ?? DateTime.now();
  if (!settings.checkUpdates) return null;
  if (!updateCheckDue(settings.lastUpdateCheck, time)) return null;
  settings.setLastUpdateCheck(time);
  try {
    return await checkForUpdate(client: client, current: current);
  } on UpdateCheckFailure {
    return null;
  }
}
