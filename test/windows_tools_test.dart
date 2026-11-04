import 'dart:convert';
import 'dart:io';

import 'package:chapterly/audio/audio_library.dart';
import 'package:chapterly/audio/media_controls.dart';
import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/update_check.dart';
import 'package:chapterly/data/update_install.dart';
import 'package:chapterly/data/window_control.dart';
import 'package:chapterly/screens/mini_player.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

AudioLink _threeFiles() => const AudioLink(tracks: [
      AudioTrack(location: 'a', name: 'a.mp3', lengthMs: 60000),
      AudioTrack(location: 'b', name: 'b.mp3', lengthMs: 120000),
      AudioTrack(location: 'c', name: 'c.mp3', lengthMs: 30000),
    ]);

String _release({
  List<Map<String, Object?>> assets = const [],
  String tag = 'v9.0.0',
}) =>
    jsonEncode({
      'tag_name': tag,
      'html_url': 'https://github.com/TheDutchMan13/Chapterly-Windows/releases/tag/v9.0.0',
      'draft': false,
      'prerelease': false,
      'assets': assets,
    });

void main() {
  test('a place in the whole book becomes a file and a place in it', () {
    final link = _threeFiles();
    expect(placeInBook(link, 0), (track: 0, trackMs: 0));
    expect(placeInBook(link, 59999), (track: 0, trackMs: 59999));
    expect(placeInBook(link, 60000), (track: 1, trackMs: 0));
    expect(placeInBook(link, 185000), (track: 2, trackMs: 5000));
    // Past the end stays in the last file.
    expect(placeInBook(link, 999999).track, 2);
  });

  group('update installer', () {
    test('is found among the release files', () {
      final update = parseLatestRelease(
        _release(assets: [
          {
            'name': 'notes.txt',
            'browser_download_url': 'https://github.com/x/notes.txt',
          },
          {
            'name': 'Chapterly-Setup-9.0.0.exe',
            'size': 30000000,
            'digest': 'sha256:${'AB' * 32}',
            'browser_download_url':
                'https://github.com/TheDutchMan13/Chapterly-Windows/releases/download/v9.0.0/Chapterly-Setup-9.0.0.exe',
          },
        ]),
        current: '1.0.0',
      )!;
      expect(update.installerUrl, endsWith('Chapterly-Setup-9.0.0.exe'));
      expect(update.installerBytes, 30000000);
      expect(update.installerSha256, 'ab' * 32);
    });

    test('an installer without a checksum, or from another repository, is not used', () {
      const good =
          'https://github.com/TheDutchMan13/Chapterly-Windows/releases/download/v9.0.0/Chapterly-Setup-9.0.0.exe';
      AvailableUpdate parse(Map<String, Object?> asset) =>
          parseLatestRelease(_release(assets: [asset]), current: '1.0.0')!;
      expect(
        parse({'name': 'Chapterly-Setup-9.0.0.exe', 'browser_download_url': good})
            .installerUrl,
        isNull,
      );
      expect(
        parse({
          'name': 'Chapterly-Setup-9.0.0.exe',
          'digest': 'sha256:${'ab' * 32}',
          'browser_download_url':
              'https://github.com/someone/else/releases/download/v9/Chapterly-Setup-9.0.0.exe',
        }).installerUrl,
        isNull,
      );
    });

    test('the version is only numbers, whatever the tag says', () {
      final update = parseLatestRelease(
        _release(tag: r'v9.0.0-..\..\evil'),
        current: '1.0.0',
      )!;
      expect(update.version, '9.0.0');
    });

    test('files from elsewhere or with other names are ignored', () {
      final update = parseLatestRelease(
        _release(assets: [
          {
            'name': 'Chapterly-Setup-9.0.0.exe',
            'browser_download_url': 'https://example.com/evil.exe',
          },
          {
            'name': 'Setup.exe',
            'browser_download_url': 'https://github.com/x/Setup.exe',
          },
        ]),
        current: '1.0.0',
      )!;
      expect(update.installerUrl, isNull);
    });

    test('is downloaded with progress', () async {
      final temp = Directory.systemTemp.createTempSync('update_test');
      addTearDown(() => temp.deleteSync(recursive: true));
      final body = List<int>.filled(2 * 1024 * 1024, 7);
      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.fromIterable([body.sublist(0, 1024 * 1024), body.sublist(1024 * 1024)]),
          200,
          contentLength: body.length,
        );
      });
      final progress = <double?>[];
      final file = await downloadInstaller(
        AvailableUpdate(
          version: '9.0.0',
          url: 'https://github.com/x',
          installerUrl: 'https://github.com/x/Chapterly-Setup-9.0.0.exe',
          installerSha256: sha256.convert(body).toString(),
        ),
        client: client,
        folder: temp,
        onProgress: progress.add,
      );
      expect(file, isNotNull);
      expect(await file!.length(), body.length);
      expect(progress.last, 1.0);
    });

    test('a download that does not match its checksum is deleted', () async {
      final temp = Directory.systemTemp.createTempSync('update_test');
      addTearDown(() => temp.deleteSync(recursive: true));
      final body = List<int>.filled(2 * 1024 * 1024, 7);
      final client = MockClient((request) async => http.Response.bytes(body, 200));
      await expectLater(
        downloadInstaller(
          AvailableUpdate(
            version: '9.0.0',
            url: 'https://github.com/x',
            installerUrl: 'https://github.com/x/Chapterly-Setup-9.0.0.exe',
            installerSha256: 'ab' * 32,
          ),
          client: client,
          folder: temp,
        ),
        throwsA(isA<UpdateDownloadFailure>()),
      );
      expect(
        temp.listSync(recursive: true).whereType<File>(),
        isEmpty,
      );
    });

    test('a tiny download is refused', () async {
      final temp = Directory.systemTemp.createTempSync('update_test');
      addTearDown(() => temp.deleteSync(recursive: true));
      final client = MockClient((request) async => http.Response('oops', 200));
      await expectLater(
        downloadInstaller(
          AvailableUpdate(
            version: '9.0.0',
            url: 'https://github.com/x',
            installerUrl: 'https://github.com/x/Chapterly-Setup-9.0.0.exe',
            installerSha256: 'ab' * 32,
          ),
          client: client,
          folder: temp,
        ),
        throwsA(isA<UpdateDownloadFailure>()),
      );
    });
  });

  test('the tray setting is kept', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    expect(settings.closeToTray, isFalse);
    settings.setCloseToTray(true);
    expect((await AppSettings.load()).closeToTray, isTrue);
  });

  test('the mini player shrinks the window and puts it back', () async {
    final window = NoWindowControl()..maximized = true;
    final mini = MiniPlayer(window: window);
    await mini.enter();
    expect(mini.active, isTrue);
    expect(window.onTop, isTrue);
    expect(window.bounds.size, MiniPlayer.size);
    await mini.leave();
    expect(mini.active, isFalse);
    expect(window.onTop, isFalse);
    expect(window.maximized, isTrue);
    expect(window.minimumSize, normalMinimumSize);
  });
}
