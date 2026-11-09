import 'dart:convert';
import 'dart:io';

import 'package:chapterly/screens/server_devices_screen.dart';
import 'package:chapterly/server/server_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ServerClient _client(MockClient mock, {String? device, String? name}) =>
    ServerClient(
      address: Uri.parse('http://100.1.2.3:8780'),
      token: 'token',
      client: mock,
      device: device,
      deviceName: name,
    );

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('why the server cannot be reached', () {
    test('a refused connection means the server is not running', () {
      for (final code in [111, 61, 10061]) {
        final failure = unreachableBecause(
            SocketException('x', osError: OSError('Connection refused', code)));
        expect(failure.unreachable, isTrue);
        expect(failure.message, contains('not running'));
      }
      expect(unreachableBecause(http.ClientException('Connection refused')).message,
          contains('not running'));
    });

    test('an address that is not found says so', () {
      final failure = unreachableBecause(
          const SocketException('Failed host lookup: \'pc.example\''));
      expect(failure.message, contains('address was not found'));
    });

    test('anything else points at Tailscale and the PC', () {
      final failure = unreachableBecause(
          SocketException('x', osError: OSError('Network is unreachable', 101)));
      expect(failure.unreachable, isTrue);
      expect(failure.message, contains('Tailscale'));
      expect(failure.message, contains('PC'));
    });

    test('a refused call is reported by the client', () async {
      final client = _client(MockClient((_) async => throw http.ClientException(
          'SocketException: Connection refused (OS Error: Connection refused, errno = 10061)')));
      await expectLater(
        client.me(),
        throwsA(isA<ServerFailure>()
            .having((f) => f.message, 'message', contains('not running'))
            .having((f) => f.unreachable, 'unreachable', isTrue)),
      );
    });
  });

  group('devices', () {
    test('the app names itself, in plain header characters', () async {
      late http.Request seen;
      final client = _client(
        MockClient((request) async {
          seen = request;
          return _json({'name': 'hans'});
        }),
        device: 'd-abcdef123456',
        name: 'Windows PC (Hans’s)',
      );
      await client.me();
      expect(seen.headers['X-Chapterly-Device'], 'd-abcdef123456');
      expect(seen.headers['X-Chapterly-Device-Name'], 'Windows PC (Hans?s)');
    });

    test('without a device id nothing extra is sent', () async {
      late http.Request seen;
      final client = _client(MockClient((request) async {
        seen = request;
        return _json({'name': 'hans'});
      }));
      await client.me();
      expect(seen.headers.keys.where((k) => k.startsWith('X-Chapterly')), isEmpty);
    });

    test('the list is read, and a device is taken off with its person', () async {
      final calls = <String>[];
      final client = _client(MockClient((request) async {
        calls.add('${request.method} ${request.url.path}?${request.url.query}');
        if (request.method == 'DELETE') return _json({'ok': true});
        return _json({
          'devices': [
            {
              'id': 'd-one123456',
              'name': 'Hans phone',
              'person': 'hans',
              'lastSeen': '2026-11-09T20:00:00+00:00',
              'thisDevice': false,
            },
          ],
        });
      }));
      final devices = await client.devices();
      expect(devices.single.name, 'Hans phone');
      expect(devices.single.lastSeen, isNotNull);
      await client.forgetDevice(devices.single);
      expect(calls.last, 'DELETE /v1/devices/d-one123456?person=hans');
    });
  });

  test('last seen is said in plain words', () {
    final now = DateTime(2026, 11, 9, 12, 0);
    expect(lastSeenText(null, now), 'never');
    expect(lastSeenText(now.subtract(const Duration(minutes: 2)), now), 'active now');
    expect(lastSeenText(now.subtract(const Duration(minutes: 30)), now), '30 min ago');
    expect(lastSeenText(now.subtract(const Duration(hours: 5)), now), '5 h ago');
    expect(lastSeenText(DateTime(2026, 11, 1, 9, 5), now), '2026-11-01 09:05');
  });

  testWidgets('the screen lists devices and takes one off', (tester) async {
    var devices = [
      {
        'id': 'd-pc12345678',
        'name': 'Windows PC (HANS)',
        'person': 'hans',
        'lastSeen': DateTime.now().toUtc().toIso8601String(),
        'thisDevice': true,
      },
      {
        'id': 'd-phone123456',
        'name': 'Android phone',
        'person': 'hans',
        'lastSeen': DateTime.now()
            .subtract(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
        'thisDevice': false,
      },
    ];
    final client = _client(MockClient((request) async {
      if (request.method == 'DELETE') {
        devices = [devices.first];
        return _json({'ok': true});
      }
      return _json({'devices': devices});
    }));
    await tester.pumpWidget(MaterialApp(home: ServerDevicesScreen(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('Windows PC (HANS) (this one)'), findsOneWidget);
    expect(find.text('Android phone'), findsOneWidget);
    expect(find.textContaining('last connected active now'), findsOneWidget);
    expect(find.textContaining('last connected 3 h ago'), findsOneWidget);
    // This device can't be taken off its own list.
    expect(find.byTooltip('Take off the list'), findsOneWidget);

    await tester.tap(find.byTooltip('Take off the list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take off'));
    await tester.pumpAndSettle();
    expect(find.text('Android phone'), findsNothing);
  });

  testWidgets('a server that cannot be reached is explained', (tester) async {
    final client = _client(
        MockClient((_) async => throw http.ClientException('Connection refused')));
    await tester.pumpWidget(MaterialApp(home: ServerDevicesScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.textContaining('not running'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
