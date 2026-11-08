import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/book.dart';
import 'app_settings.dart';
import 'book_repository.dart';
import 'phone_finder.dart';
import 'sync_three_way.dart';
import 'cover_store.dart';
import 'sync_covers.dart';
import 'sync_crypto.dart';
import 'sync_merge.dart';
import 'sync_phones.dart';
import 'sync_plan.dart';
import 'sync_profiles.dart';
import 'sync_protocol.dart';
import 'perf_log.dart';

/// A sync problem, with a message for the user.
class SyncFailure implements Exception {
  const SyncFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

const unreachableMessage = "Can't reach your phone. Check that Chapterly is "
    'open on the phone, that "Allow sync from my PC" is on, and that both '
    'are on the same Wi-Fi.';

/// A profile that has a PIN on the phone and isn't open there.
class PhoneProfileLocked extends SyncFailure {
  const PhoneProfileLocked()
      : super('It has a PIN on your phone. Open it there to sync it.');
}

const _notChapterly = SyncFailure('That address is not a Chapterly phone.');
const _updatePhone = SyncFailure('Update Chapterly on your phone.');
const _updateWindows = SyncFailure(
  'Your phone has a newer version of Chapterly. Update the Windows app.',
);

/// Turns what the user typed into the phone's address, such as
/// http://192.168.1.20:8765. The port is 8765 unless one is given.
/// Returns null when the text is not an address.
Uri? parsePhoneAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'http' || uri.host.isEmpty) return null;
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return null;
  return Uri(
    scheme: 'http',
    host: uri.host,
    port: uri.hasPort ? uri.port : defaultSyncPort,
  );
}

/// The address as the phone shows it, such as 192.168.1.20:8765.
String formatPhoneAddress(Uri address) => '${address.host}:${address.port}';

/// The pairing code without dashes or spaces, in capitals. Null unless it is
/// 16 letters and digits.
String? normalizeSyncCode(String input) {
  final code = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return RegExp(r'^[A-Z0-9]{16}$').hasMatch(code) ? code : null;
}

/// How many books were added, changed or removed between [before] and [after].
int countSyncChanges(List<Book> before, List<Book> after) {
  final old = {for (final book in before) book.id: book};
  final kept = <String>{};
  var changed = 0;
  for (final book in after) {
    kept.add(book.id);
    final previous = old[book.id];
    if (previous == null || previous.updatedAt != book.updatedAt) changed++;
  }
  for (final id in old.keys) {
    if (!kept.contains(id)) changed++;
  }
  return changed;
}

String? _errorText(String body) {
  try {
    final data = jsonDecode(body);
    if (data is Map && data['error'] is String) return data['error'] as String;
  } on FormatException {
    // Not JSON.
  }
  return null;
}

/// One sync run with the phone: the key made from the pairing code and the
/// phone's challenge. Made by [SyncClient.connect].
class SyncSession {
  SyncSession._(this.address, this.key);

  final Uri address;
  final SyncKey key;
  String? _challenge;
}

/// What the phone answered to a sealed request, opened.
class _Answer {
  const _Answer(this.status, this.text);

  final int status;
  final String text;
}

/// The most the PC reads of an answer from the phone.
const maxSyncReplyBytes = 100 * 1024 * 1024;
const maxCoverReplyBytes = 3 * 1024 * 1024;
const maxOtherReplyBytes = 1024 * 1024;

/// Shown when the phone's ping says it does not speak sync version 2.
const updatePhoneForSyncMessage =
    'Update Chapterly on your phone to sync with this PC.';

const _updatePhoneForSync = SyncFailure(updatePhoneForSyncMessage);

const _wrongCode = SyncFailure(
  'The pairing code is wrong. Check it on your phone under '
  'Settings > Sync with a PC.',
);

/// Shown when an answer is larger than Chapterly reads.
const tooLargeReplyMessage = 'Your phone answered with more than Chapterly '
    'will read, so nothing was changed. Check that the address is your phone.';

class _TooLarge implements Exception {
  const _TooLarge();
}

/// Talks to the phone over the home network. Every request but the ping and
/// the hello is sealed with a key made from the pairing code, and so is
/// every answer: the code never travels, and an answer that was not sealed
/// with it is refused before anything is applied.
class SyncClient {
  SyncClient({
    http.Client? client,
    this.pingTimeout = const Duration(seconds: 6),
    this.syncTimeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration pingTimeout;
  final Duration syncTimeout;

  Future<T> _send<T>(
    Future<T> Function() request,
    Duration timeout,
    String step,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw SyncFailure(_unreachable(step, 'no answer in ${timeout.inSeconds} s'));
    } on SocketException catch (error) {
      throw SyncFailure(_unreachable(step, error));
    } on http.ClientException catch (error) {
      throw SyncFailure(_unreachable(step, error));
    }
  }

  /// The unreachable message, with what Windows reported, so a failure can
  /// be told apart from another.
  String _unreachable(String step, Object reason) =>
      '$unreachableMessage\n\nDetails ($step): $reason';

  /// Sends [request] and reads the answer, at most [limit] bytes of it.
  Future<(int, Uint8List)> _fetch(
    http.BaseRequest request,
    int limit,
    Duration timeout,
    String step,
  ) async {
    try {
      return await _send(() async {
        final response = await _client.send(request);
        final length = response.contentLength;
        if (length != null && length > limit) throw const _TooLarge();
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          builder.add(chunk);
          if (builder.length > limit) throw const _TooLarge();
        }
        return (response.statusCode, builder.takeBytes());
      }, timeout, step);
    } on _TooLarge {
      throw const SyncFailure(tooLargeReplyMessage);
    }
  }

  /// Checks that [address] is a Chapterly phone that speaks this protocol.
  /// Returns whether it syncs every profile with one pairing.
  Future<bool> ping(Uri address) async {
    final request = http.Request('GET', address.replace(path: '/v1/ping'));
    final (status, bytes) =
        await _fetch(request, maxOtherReplyBytes, pingTimeout, 'ping');
    Object? data;
    try {
      data = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      throw _notChapterly;
    }
    if (status != 200 ||
        data is! Map ||
        data['app'] != 'chapterly' ||
        data['protocol'] is! int) {
      throw _notChapterly;
    }
    final protocol = data['protocol'] as int;
    if (protocol > syncProtocolVersion) throw _updateWindows;
    if (protocol < syncProtocolVersion) throw _updatePhone;
    final sync = data['sync'];
    if (sync is! int || sync < 2) throw _updatePhoneForSync;
    final profiles = data['profiles'];
    return profiles is int && profiles >= syncProfilesVersion;
  }

  /// The phone's profiles, after it added [create].
  Future<List<SyncProfileInfo>> profiles(
    SyncSession session, {
    List<NewSyncProfile> create = const [],
  }) async {
    final answer = await _sealed(
      session,
      'POST',
      '/v2/profiles',
      encodeProfileRequest(create),
      limit: maxOtherReplyBytes,
      step: 'profiles',
    );
    if (answer.status != 200) {
      throw SyncFailure(
        _errorText(answer.text) ?? 'Your phone could not list its profiles.',
      );
    }
    try {
      return decodeProfileList(answer.text);
    } on FormatException catch (error) {
      throw SyncFailure(error.message);
    }
  }

  /// Starts a sync run with the phone at [address]: makes the key from
  /// [code] and asks the phone for a challenge.
  Future<SyncSession> connect(Uri address, String code) async {
    final session = SyncSession._(address, await SyncKey.fromCode(code));
    await _hello(session);
    return session;
  }

  Future<String> _hello(SyncSession session) async {
    final request = http.Request(
      'GET',
      session.address.replace(path: '/v2/hello'),
    );
    final (status, bytes) =
        await _fetch(request, maxOtherReplyBytes, pingTimeout, 'hello');
    if (status == 404 || status == 426) throw _updatePhoneForSync;
    Object? data;
    try {
      data = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      data = null;
    }
    final challenge = data is Map ? data['challenge'] : null;
    if (status != 200 || challenge is! String || challenge.isEmpty) {
      throw _notChapterly;
    }
    return session._challenge = challenge;
  }

  SyncFailure _notYourPhone(SyncSession session) => SyncFailure(
        'The phone at ${session.address.host} did not answer with your sync '
        'code. Pair again if you changed the code.',
      );

  /// Sends [plain] sealed to [path] and returns the phone's answer, opened.
  /// An answer that is not sealed with the code is refused, except the
  /// phone's own plain refusals (wrong code, old challenge, update needed).
  Future<_Answer> _sealed(
    SyncSession session,
    String method,
    String path,
    String plain, {
    required int limit,
    required String step,
    bool retried = false,
  }) async {
    final challenge = session._challenge ?? await _hello(session);
    final request = http.Request(method, session.address.replace(path: path))
      ..headers['X-Chapterly-Challenge'] = challenge
      ..headers['Content-Type'] = 'application/octet-stream'
      ..bodyBytes = await session.key.seal(
        utf8.encode(plain),
        requestContext(method, path, challenge),
      );
    final (status, bytes) = await _fetch(request, limit, syncTimeout, step);
    try {
      final opened = await session.key.open(
        bytes,
        responseContext(method, path, challenge),
      );
      return _Answer(status, utf8.decode(opened, allowMalformed: true));
    } on SyncAuthException {
      // Not sealed with the code: only a refusal is taken from it.
    }
    if (status >= 200 && status < 300) throw _notYourPhone(session);
    final error = _errorText(utf8.decode(bytes, allowMalformed: true));
    switch (status) {
      case 401 when error == 'challenge':
        if (retried) {
          throw const SyncFailure(
            'Your phone did not accept the sync. Try again.',
          );
        }
        await _hello(session);
        return _sealed(
          session,
          method,
          path,
          plain,
          limit: limit,
          step: step,
          retried: true,
        );
      case 401 when error == 'code':
        throw _wrongCode;
      case 401:
        throw const SyncFailure(
          'Your phone did not accept the sync. Try again.',
        );
      case 404:
      case 426:
        throw _updatePhoneForSync;
      case 429:
        throw const SyncFailure(
          'Your phone refused too many tries with a wrong pairing code. '
          'Wait a minute and try again.',
        );
      default:
        throw _notYourPhone(session);
    }
  }

  /// Sends this PC's library ([body], made by [encodeSyncPayload]) and
  /// returns the merged library from the phone.
  /// With [profile], the phone's profile of that id; otherwise the one
  /// open on the phone.
  Future<SyncPayload> sync(
    SyncSession session,
    String body, {
    String? profile,
  }) async {
    final path = profileSyncPath(profile, '/sync');
    final _Answer answer;
    try {
      answer = await _sealed(
        session,
        'POST',
        path,
        body,
        limit: maxSyncReplyBytes,
        step: 'sync',
      );
    } on SyncFailure catch (failure) {
      if (!failure.message.startsWith(unreachableMessage) ||
          failure.message.contains('no answer in')) {
        rethrow;
      }
      // A phone that refuses the request answers and hangs up without
      // reading the library, which Windows reports as a broken connection.
      // Ask again with a tiny message to find out which it was.
      var accepted = false;
      try {
        await _sealed(
          session,
          'POST',
          path,
          '{}',
          limit: maxOtherReplyBytes,
          step: 'sync',
        );
        accepted = true;
      } on SyncFailure catch (problem) {
        // A refusal (wrong code, not your phone) is the real reason.
        if (!problem.message.startsWith(unreachableMessage)) rethrow;
      } catch (_) {
        // Could not ask again.
      }
      final size =
          '${(utf8.encode(body).length / 1048576).toStringAsFixed(1)} MB';
      throw SyncFailure(
        accepted
            ? '${failure.message}\n(The pairing code was accepted, but the '
                'phone closed the connection while the library was sent. '
                'Library size: $size.)'
            : '${failure.message}\n(Library size: $size.)',
      );
    }
    final text = answer.text;
    switch (answer.status) {
      case 200:
        break;
      case 401:
        // A phone with profiles says which profile is open there.
        final wrongProfile = _errorText(text);
        if (wrongProfile != null && wrongProfile.contains('profile')) {
          throw SyncFailure(wrongProfile);
        }
        throw _wrongCode;
      case 400:
        final message = _errorText(text);
        if (message != null && message.contains('newer')) throw _updatePhone;
        throw SyncFailure(message ?? 'Your phone could not read the sync.');
      case 404:
        if (profile != null) {
          throw const SyncFailure('It is no longer on your phone.');
        }
        throw _notChapterly;
      case 409:
        throw MissingCovers(_hashesIn(text));
      case 423:
        throw const PhoneProfileLocked();
      default:
        throw SyncFailure(
          _errorText(text) ?? 'Your phone could not finish the sync. Try again.',
        );
    }
    try {
      return clampFutureDates(decodeSyncPayload(text));
    } on FormatException catch (error) {
      if (error.message.contains('newer')) throw _updateWindows;
      throw SyncFailure(error.message);
    }
  }

  /// Which of [hashes] the phone does not have a cover picture for.
  Future<List<String>> missingCovers(
    SyncSession session,
    List<String> hashes, {
    String? profile,
  }) async {
    if (hashes.isEmpty) return const [];
    final answer = await _sealed(
      session,
      'POST',
      profileSyncPath(profile, '/covers/missing'),
      jsonEncode({'hashes': hashes}),
      limit: maxOtherReplyBytes,
      step: 'covers',
    );
    _checkCovers(answer);
    return _hashesIn(answer.text);
  }

  /// Gives the phone one cover picture.
  Future<void> putCover(
    SyncSession session,
    String hash,
    String dataUrl, {
    String? profile,
  }) async {
    final answer = await _sealed(
      session,
      'PUT',
      profileSyncPath(profile, '/covers/$hash'),
      dataUrl,
      limit: maxOtherReplyBytes,
      step: 'covers',
    );
    _checkCovers(answer);
  }

  /// Takes one cover picture from the phone, or null when it has none by
  /// that name.
  Future<String?> getCover(
    SyncSession session,
    String hash, {
    String? profile,
  }) async {
    final answer = await _sealed(
      session,
      'GET',
      profileSyncPath(profile, '/covers/$hash'),
      '',
      limit: maxCoverReplyBytes,
      step: 'covers',
    );
    if (answer.status == 404 && _errorText(answer.text) == 'No such cover.') {
      return null;
    }
    _checkCovers(answer);
    return answer.text;
  }

  void _checkCovers(_Answer answer) {
    switch (answer.status) {
      case 200:
      case 204:
        return;
      case 401:
        throw _wrongCode;
      case 423:
        throw const PhoneProfileLocked();
      case 404:
        throw const SyncFailure(
          'Your phone does not know this way of syncing covers. Update '
          'Chapterly on your phone.',
        );
      default:
        throw SyncFailure(
          _errorText(answer.text) ??
              'Your phone could not take the covers. Try again.',
        );
    }
  }
}

/// The cover names in a reply such as `{"missing": [...]}`.
List<String> _hashesIn(String text) {
  try {
    final data = jsonDecode(text);
    final list = data is Map ? data['missing'] : null;
    if (list is List) {
      return [
        for (final item in list)
          if (item is String && isCoverHash(item)) item,
      ];
    }
  } on FormatException {
    // Not JSON.
  }
  return const [];
}

/// Where the pairing code is kept. The app uses Windows Credential Manager
/// (see secure_code_store.dart); tests use [MemoryCodeStore].
abstract interface class CodeStore {
  Future<String?> read();
  Future<void> write(String code);
  Future<void> delete();
}

class MemoryCodeStore implements CodeStore {
  String? _code;

  @override
  Future<String?> read() async => _code;

  @override
  Future<void> write(String code) async {
    _code = code;
  }

  @override
  Future<void> delete() async {
    _code = null;
  }
}

/// One profile's library on this PC, as a sync uses it.
class SyncTarget {
  SyncTarget({
    required this.repository,
    required this.settings,
    required this.base,
  });

  final BookRepository repository;
  final AppSettings settings;

  /// The books as they were after this profile's last sync.
  final SyncBase base;
}

/// The profiles on this PC, so one pairing syncs them all. Set up in
/// main.dart; tests leave it out and sync only the open profile.
abstract interface class SyncProfileAccess {
  /// The profile that is open on this PC.
  String get openId;

  /// Every profile here. One with a PIN that isn't open is locked.
  List<SyncProfileInfo> list();

  /// Adds a profile from the phone. Returns its id, or null when it could
  /// not be added (a name that is taken, say).
  Future<String?> create(String name, int color);

  /// Opens another profile's library for a sync with [phone] (its own
  /// last-synced copy is used).
  Future<SyncTarget> open(String id, {String phone = ''});

  /// Closes a library [open] gave.
  Future<void> close(SyncTarget target);

  /// Which profile here syncs with which on [phone].
  ProfileLinks linksFor(String phone);
  Future<void> saveLinks(ProfileLinks links, {String phone = ''});
}

/// Pairs with the phone and syncs: when asked, when Chapterly opens, and
/// every few minutes while it is open (see Settings). With [profiles], one
/// pairing syncs every profile on both sides.
class PcSync extends ChangeNotifier {
  PcSync({
    required this.repository,
    required this.settings,
    required this.codeStore,
    SyncClient? client,
    SyncBase? base,
    this.profiles,
    this.codeStoreFor,
    this.baseFor,
  })  : client = client ?? SyncClient(),
        base = base ?? SyncBase();

  final BookRepository repository;
  final AppSettings settings;
  final CodeStore codeStore;
  final SyncClient client;

  /// The books as they were after the last sync, for merging books changed
  /// on both sides field by field (Windows app).
  final SyncBase base;

  /// Every profile on this PC, or null to sync only the open one.
  final SyncProfileAccess? profiles;

  /// Where the pairing code of a phone after the first is kept. The first
  /// phone's is [codeStore].
  final CodeStore Function(String phone)? codeStoreFor;

  /// Loads a phone's last-synced copy of the open profile. The first
  /// phone's is [base].
  final Future<SyncBase> Function(String phone)? baseFor;

  final _extraCodes = <String, CodeStore>{};
  final _extraBases = <String, SyncBase>{};

  /// The phone a sync step is for (empty: the first). A sync runs one phone
  /// at a time, so the steps below use this one.
  String _phone = '';

  bool _busy = false;
  bool _hasCode = false;
  SyncPlan? _pending;
  String? _dismissed;
  Timer? _timer;
  DateTime? _lastAutoAttempt;
  String? _lastNote;

  /// Called after a sync in the background changed books here, with how
  /// many. The library uses it to show a message.
  void Function(int changed)? onBackgroundSync;

  /// Changes an automatic sync held back because they would remove books.
  /// The library offers to review them.
  SyncPlan? get pendingReview => _pending;

  /// What the last sync of every profile has to tell: how many profiles
  /// synced and which were left out, and why. Null when there is nothing.
  String? get lastNote => _lastNote;

  /// Hides [pendingReview] until the changes waiting are different.
  void dismissPending() {
    _dismissed = _pending?.signature;
    _pending = null;
    notifyListeners();
  }

  /// True while connecting or syncing.
  bool get busy => _busy;

  final _here = <String, bool?>{};
  bool _checking = false;

  /// Whether each phone (by id) answered the last check: true is here now,
  /// false is not reachable, missing is not checked yet.
  Map<String, bool?> get phonesHere => Map.unmodifiable(_here);

  /// True while [checkPhones] is looking.
  bool get checking => _checking;

  /// Asks every paired phone whether it is reachable now, without syncing.
  Future<void> checkPhones() async {
    if (_checking) return;
    _checking = true;
    notifyListeners();
    try {
      final all = phones;
      await Future.wait([
        for (final phone in all)
          () async {
            final address = parsePhoneAddress(phone.address);
            var here = false;
            if (address != null) {
              try {
                await client.ping(address);
                here = true;
              } catch (_) {
                // Not reachable, or not a phone that fits this version.
              }
            }
            _here[phone.id] = here;
          }(),
      ]);
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Whether a phone is paired.
  bool get paired => phones.isNotEmpty;

  bool get _firstPaired => _hasCode && settings.syncAddress != null;

  /// The phones this PC is paired with, the first one first.
  List<SyncPhone> get phones => [
        if (_firstPaired)
          SyncPhone(id: '', name: 'Phone 1', address: settings.syncAddress!),
        ...settings.extraPhones,
      ];

  CodeStore _codesOf(String phone) => phone.isEmpty
      ? codeStore
      : _extraCodes[phone] ??=
          codeStoreFor?.call(phone) ?? MemoryCodeStore();

  Future<SyncBase> _baseOf(String phone) async {
    if (phone.isEmpty) return base;
    final known = _extraBases[phone];
    if (known != null) return known;
    return _extraBases[phone] = await (baseFor?.call(phone) ?? Future.value(SyncBase()));
  }

  Future<SyncTarget> _openTarget() async => SyncTarget(
        repository: repository,
        settings: settings,
        base: await _baseOf(_phone),
      );

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  /// Reads whether a pairing code is saved. Call once at start-up.
  Future<void> load() async {
    _hasCode = (await codeStore.read()) != null;
    notifyListeners();
  }

  /// Checks the address, saves the address and code, and syncs once. That
  /// first sync is what proves the code is right. A phone not paired yet is
  /// added to the others; one with the same address is paired again.
  /// Returns null when it worked, or the message to show.
  Future<String?> pair({required String address, required String code}) async {
    if (_busy) return 'A sync is already running.';
    final base = parsePhoneAddress(address);
    if (base == null) {
      return 'Type the address your phone shows, such as 192.168.1.20:8765.';
    }
    final clean = normalizeSyncCode(code);
    if (clean == null) {
      return 'The pairing code has 16 letters and numbers, as your phone '
          'shows it.';
    }
    final text = formatPhoneAddress(base);
    final known = phones;
    SyncPhone? same;
    for (final phone in known) {
      if (phone.address == text) same = phone;
    }
    final id = same?.id ??
        (_firstPaired ? nextPhoneId([for (final p in known) p.id]) : '');
    final name = same?.name ??
        (id.isEmpty
            ? 'Phone 1'
            : nextPhoneName([for (final p in known) p.name]));
    _setBusy(true);
    // A phone that is paired already keeps its code if the new one is wrong
    // (a QR search can try it with another phone's code).
    String? previous;
    try {
      await client.ping(base);
      if (same != null) previous = await _codesOf(id).read();
      await _codesOf(id).write(clean);
    } on SyncFailure catch (error) {
      _setBusy(false);
      return error.message;
    } catch (_) {
      _setBusy(false);
      return 'Windows could not save the pairing code.';
    }
    if (id.isEmpty) {
      settings.setSyncAddress(text);
      _hasCode = true;
    } else {
      settings.setExtraPhones([
        for (final phone in settings.extraPhones)
          if (phone.id != id) phone,
        SyncPhone(id: id, name: name, address: text),
      ]);
    }
    _busy = false;
    // A new pairing starts without a last-synced copy, and works out again
    // which profiles go together.
    if (same == null) {
      await (await _baseOf(id)).save(const []);
      await profiles?.saveLinks(const ProfileLinks(), phone: id);
    }
    final problem = await syncNow(only: {id});
    // Only keep the pairing when the first sync worked, so a wrong code is
    // not saved.
    if (problem != null) {
      if (same == null) {
        await forget(id);
      } else if (previous != null) {
        await _codesOf(id).write(previous);
      }
    }
    return problem;
  }

  /// Sends [body] (books with cover references) after giving the phone the
  /// pictures it lacks, and returns its reply with references too.
  Future<SyncPayload> _exchange(
    SyncSession session,
    String body,
    List<String> covers,
    CoverPool pool,
    String? profile,
    CoverStore store,
  ) async {
    Future<SyncPayload> post() async {
      final reply = await client.sync(session, body, profile: profile);
      return SyncPayload(
        books: withCoverRefs(reply.books, pool),
        tombstones: reply.tombstones,
        features: reply.features,
        wishes: reply.wishes,
      );
    }

    await _giveCovers(session, covers, pool, profile, store);
    try {
      return await post();
    } on MissingCovers catch (lacking) {
      // The phone lost some pictures since it was asked: give them again.
      await _giveCovers(
        session,
        lacking.hashes,
        pool,
        profile,
        store,
        ask: false,
      );
      return await post();
    }
  }

  Future<void> _giveCovers(
    SyncSession session,
    List<String> hashes,
    CoverPool pool,
    String? profile,
    CoverStore store, {
    bool ask = true,
  }) async {
    if (hashes.isEmpty) return;
    final lacking = ask
        ? await client.missingCovers(session, hashes, profile: profile)
        : hashes;
    await forEachLimited(lacking, (hash) async {
      final picture = pool[hash] ?? await store.readCover(hash);
      if (picture == null) {
        throw const SyncFailure('A cover could not be read on this PC.');
      }
      await client.putCover(session, hash, picture, profile: profile);
    });
  }

  /// Fetches the pictures [books] name that this PC does not have yet. A
  /// book whose picture the phone no longer has comes back without a cover
  /// rather than holding up the sync.
  Future<void> _fetchPictures(
    SyncSession session,
    List<Book> books,
    CoverPool pool,
    String? profile,
    CoverStore store,
  ) async {
    final own = await store.coverHashes();
    final fetch = [
      for (final hash in missingCovers(books, pool))
        if (!own.contains(hash)) hash,
    ];
    await forEachLimited(fetch, (hash) async {
      final picture = await client.getCover(session, hash, profile: profile);
      if (picture == null) return;
      try {
        pool.put(hash, picture);
      } on FormatException {
        // A damaged picture: the book is left without a cover.
      }
    });
  }

  /// Whether the phone at [address] syncs every profile, and this PC does.
  Future<bool> _everyProfile(Uri address) async =>
      profiles != null && await client.ping(address);

  /// Sends this library to every paired phone (or just those in [only])
  /// and takes back the merged library; with [profiles], every profile on
  /// both sides. With [skipOpen], the open profile is left for later (its
  /// changes wait for review). Returns null when it worked, or the message
  /// to show.
  Future<String?> syncNow({bool skipOpen = false, Set<String>? only}) async {
    if (_busy) return 'A sync is already running.';
    final all = [
      for (final phone in phones)
        if (only == null || only.contains(phone.id)) phone,
    ];
    if (all.isEmpty) return 'Connect to your phone first, in Settings.';
    _setBusy(true);
    try {
      _lastNote = null;
      final many = phones.length > 1;
      String label(SyncPhone phone, String text) =>
          many ? '${phone.name}: $text' : text;
      final problems = <String>[];
      final notes = <String>[];
      for (final phone in all) {
        final result = await _syncPhone(phone, skipOpen: skipOpen);
        if (result.problem != null) {
          problems.add(label(phone, result.problem!));
        }
        if (result.note != null) notes.add(label(phone, result.note!));
      }
      if (problems.isEmpty && all.length > 1) {
        // What one phone sent reaches the phones synced before it.
        for (final phone in all.take(all.length - 1)) {
          await _syncPhone(phone, skipOpen: skipOpen);
        }
      }
      _lastNote = notes.isEmpty ? null : notes.join('\n');
      if (problems.isNotEmpty) return problems.join('\n');
      if (!skipOpen) _pending = null;
      return null;
    } finally {
      _setBusy(false);
    }
  }

  /// Syncs with one phone. Returns the problem to show, or a note about
  /// profiles that were left out.
  Future<({String? problem, String? note})> _syncPhone(
    SyncPhone phone, {
    bool skipOpen = false,
  }) async {
    _phone = phone.id;
    final address = parsePhoneAddress(phone.address);
    final code = await _codesOf(phone.id).read();
    if (address == null || code == null) {
      return (
        problem: 'Connect to your phone first, in Settings.',
        note: null,
      );
    }
    try {
      final every = await _everyProfile(address);
      // The key and the phone's challenge, for every request of this run.
      final session = await client.connect(address, code);
      String? note;
      if (every) {
        note = await _syncEveryProfile(session, skipOpen: skipOpen);
      } else if (!skipOpen) {
        await _syncTarget(session, await _openTarget(), null);
      }
      settings.setPhoneSynced(phone.id, DateTime.now());
      _here[phone.id] = true;
      return (problem: null, note: note);
    } on SyncFailure catch (error) {
      settings.recordSyncError(error.message);
      return (problem: error.message, note: null);
    } catch (_) {
      const message = 'The sync could not be finished.';
      settings.recordSyncError(message);
      return (problem: message, note: null);
    }
  }

  /// Pairs up the profiles on both sides, adds the ones each side is
  /// missing, and syncs every pair, the open profile first. A profile with a
  /// PIN syncs only while it is open (on each side). Returns what to tell
  /// about the profiles that were left out, or null.
  Future<String?> _syncEveryProfile(
    SyncSession session, {
    bool skipOpen = false,
  }) async {
    final access = profiles!;
    var phone = await client.profiles(session);
    var plan = planProfileLinks(
      pc: access.list(),
      phone: phone,
      saved: access.linksFor(_phone),
    );
    if (plan.createOnPhone.isNotEmpty) {
      phone = await client.profiles(
        session,
        create: [
          for (final profile in plan.createOnPhone)
            (name: profile.name, color: profile.color),
        ],
      );
      plan = planProfileLinks(
        pc: access.list(),
        phone: phone,
        saved: plan.links,
      );
    }
    var added = false;
    for (final profile in plan.createOnPc) {
      if (await access.create(profile.name, profile.color) != null) {
        added = true;
      }
    }
    final here = access.list();
    if (added) {
      plan = planProfileLinks(pc: here, phone: phone, saved: plan.links);
    }
    final before = access.linksFor(_phone);
    await access.saveLinks(plan.links, phone: _phone);
    final links = plan.links.links;
    final onPhone = {for (final profile in phone) profile.id: profile};
    final openId = access.openId;
    final ordered = [
      ...here.where((profile) => profile.id == openId),
      ...here.where((profile) => profile.id != openId),
    ];
    final notes = <String>[];
    var synced = 0;
    for (final profile in ordered) {
      final isOpen = profile.id == openId;
      if (isOpen && skipOpen) continue;
      final phoneId = links[profile.id];
      if (profile.locked) {
        notes.add('${profile.name}: it has a PIN here. Open it to sync it.');
        continue;
      }
      if (phoneId == null) {
        if (!plan.links.leftOnPc.contains(profile.id)) {
          notes.add('${profile.name}: could not be added to your phone.');
        }
        continue;
      }
      if (onPhone[phoneId]?.locked ?? false) {
        notes.add('${profile.name}: ${const PhoneProfileLocked().message}');
        continue;
      }
      final target = isOpen
          ? await _openTarget()
          : await access.open(profile.id, phone: _phone);
      try {
        // A new pair starts without a last-synced copy.
        if (before.links[profile.id] != phoneId) {
          await target.base.save(const []);
        }
        if (!isOpen && target.settings.reviewSync) {
          // Changes that would remove books wait until the profile is
          // opened and they are reviewed there.
          final check = await _planFor(session, target, phoneId);
          if (check.removals > 0) {
            notes.add(
              '${profile.name}: some books would be removed. Open it and '
              'choose Sync now to review the changes.',
            );
            continue;
          }
        }
        await _syncTarget(session, target, phoneId);
        synced++;
      } on SyncFailure catch (error) {
        // A problem with the connection or the code ends the whole sync.
        if (isOpen || error.message.startsWith(unreachableMessage)) rethrow;
        if (error is! PhoneProfileLocked) {
          target.settings.recordSyncError(error.message);
        }
        notes.add('${profile.name}: ${error.message}');
      } catch (_) {
        if (isOpen) rethrow;
        const message = 'The sync could not be finished.';
        target.settings.recordSyncError(message);
        notes.add('${profile.name}: $message');
      } finally {
        if (!isOpen) await access.close(target);
      }
    }
    if (notes.isEmpty) return null;
    final count = synced == 1 ? '1 profile' : '$synced profiles';
    return 'Synced $count. Not synced:\n${notes.join('\n')}';
  }

  /// Syncs one profile's library ([target]) with the phone's profile
  /// [phoneProfile] (null: the one open on the phone).
  Future<void> _syncTarget(
    SyncSession session,
    SyncTarget target,
    String? phoneProfile,
  ) async {
    final repository = target.repository;
    final settings = target.settings;
    final base = target.base;
    // Books travel with cover references; the pictures are given to the
    // phone, or taken from it, only when one side lacks them.
    final pool = CoverPool();
    SyncPayload? phone;
    if (!base.isEmpty) {
      // Ask for the phone's library (sending none changes nothing there)
      // to merge books changed on both sides before sending.
      phone = await _exchange(
        session,
        encodeSyncPayload(const [], const {}),
        const [],
        pool,
        phoneProfile,
        repository,
      );
    }
    // Taken after that, so a change made meanwhile is sent too.
    var sent = repository.snapshot();
    sent = (
      books: withCoverRefs(sent.books, pool),
      tombstones: sent.tombstones,
    );
    if (phone != null) {
      final resolved = resolveConflicts(
        base: base.books,
        local: sent.books,
        remote: phone.books,
        now: DateTime.now(),
        phoneKeepsBookmarks: phone.features.contains('audioBookmarks'),
      );
      if (resolved.isNotEmpty) {
        final byId = {for (final book in resolved) book.id: book};
        sent = (
          books: [for (final book in sent.books) byId[book.id] ?? book],
          tombstones: sent.tombstones,
        );
      }
    }
    final reply = await _exchange(
      session,
      encodeSyncPayload(
        sent.books,
        sent.tombstones,
        wishes: settings.allWishes,
      ),
      coverHashesOf(sent.books),
      pool,
      phoneProfile,
      repository,
    );
    // The pictures this PC does not have yet come from the phone. They
    // are fetched first: from the snapshot below until the library is
    // saved, nothing waits, so a change made meanwhile can't be lost.
    await _fetchPictures(session, reply.books, pool, phoneProfile, repository);
    // The pictures that came in are kept apart from the books (see
    // cover_store.dart); the books keep references.
    final kept = await keepPoolCovers(reply.books, pool, repository);
    // Merge the reply with the library as it is now, so a change made on
    // this PC while the sync was running is not lost. The phone's copy wins
    // a tie, so both sides end up the same.
    final now = repository.snapshot();
    final nowBooks = withCoverRefs(now.books, pool);
    final merged = mergeLibraries(
      local: reply.books,
      localTombstones: reply.tombstones,
      remote: nowBooks,
      remoteTombstones: now.tombstones,
    );
    // A phone app older than 1.15.0 drops audiobook bookmarks: keep this
    // PC's.
    final refBooks = reply.features.contains('audioBookmarks')
        ? merged.books
        : keepPcBookmarks(merged.books, nowBooks);
    final books = withoutLostCovers(refBooks, {
      ...kept,
      ...coverHashesOf(nowBooks),
    });
    final changed = countSyncChanges(now.books, books);
    await repository.applySynced(books, merged.tombstones);
    // The wish list: the newer copy of each wish wins, including a wish
    // changed on this PC while the sync was running.
    settings.mergeWishesFrom(reply.wishes);
    // What the phone holds now. A change made on this PC during the sync
    // is not in it, so the next sync still sees it as a PC change.
    await base.save(reply.books);
    settings.recordSync(at: DateTime.now(), changed: changed);
  }

  /// What a sync of [target] with the phone's profile [phoneProfile] would
  /// change, without changing anything. It asks the phone for its library by
  /// sending an empty one: merging nothing into the phone's library leaves
  /// it as it is. With [phoneEmpty], the phone does not have the profile
  /// yet; with [useBase] false, the last-synced copy is not used (a new
  /// pair).
  Future<SyncPlan> _planFor(
    SyncSession session,
    SyncTarget target,
    String? phoneProfile, {
    bool phoneEmpty = false,
    bool useBase = true,
  }) async {
    final phone = phoneEmpty
        ? const SyncPayload(books: [], tombstones: {})
        : await client.sync(
            session,
            encodeSyncPayload(const [], const {}),
            profile: phoneProfile,
          );
    final now = target.repository.snapshot();
    // Books changed on both sides are shown as the sync will merge them.
    final resolved = target.base.isEmpty || !useBase
        ? const <Book>[]
        : resolveConflicts(
            base: target.base.books,
            local: now.books,
            remote: phone.books,
            now: DateTime.now(),
            phoneKeepsBookmarks: phone.features.contains('audioBookmarks'),
          );
    final byId = {for (final book in resolved) book.id: book};
    return planSync(
      phoneBooks: phone.books,
      phoneTombstones: phone.tombstones,
      pcBooks: [for (final book in now.books) byId[book.id] ?? book],
      pcTombstones: now.tombstones,
    );
  }

  /// Works out what a sync would change on this PC and on the phone, for
  /// the open profile, without changing anything. With several phones, the
  /// first one that has changes to show is used. Returns the plan, or the
  /// message to show.
  Future<({SyncPlan? plan, String? problem})> preview({
    Set<String>? only,
  }) async {
    if (_busy) return (plan: null, problem: 'A sync is already running.');
    final all = [
      for (final phone in phones)
        if (only == null || only.contains(phone.id)) phone,
    ];
    if (all.isEmpty) {
      return (plan: null, problem: 'Connect to your phone first, in Settings.');
    }
    _setBusy(true);
    try {
      var result = (plan: null as SyncPlan?, problem: null as String?);
      for (final phone in all) {
        result = await _previewPhone(phone);
        final plan = result.plan;
        if (plan != null && !plan.isEmpty) break;
      }
      return result;
    } finally {
      _setBusy(false);
    }
  }

  Future<({SyncPlan? plan, String? problem})> _previewPhone(
    SyncPhone phone,
  ) async {
    _phone = phone.id;
    final address = parsePhoneAddress(phone.address);
    final code = await _codesOf(phone.id).read();
    if (address == null || code == null) {
      return (plan: null, problem: 'Connect to your phone first, in Settings.');
    }
    try {
      final every = await _everyProfile(address);
      final session = await client.connect(address, code);
      if (!every) {
        return (
          plan: await _planFor(session, await _openTarget(), null),
          problem: null,
        );
      }
      final access = profiles!;
      final phones = await client.profiles(session);
      final links = planProfileLinks(
        pc: access.list(),
        phone: phones,
        saved: access.linksFor(_phone),
      ).links;
      final phoneId = links.links[access.openId];
      final onPhone = [
        for (final profile in phones)
          if (profile.id == phoneId) profile,
      ];
      if (onPhone.isNotEmpty && onPhone.first.locked) {
        throw const PhoneProfileLocked();
      }
      final plan = await _planFor(
        session,
        await _openTarget(),
        phoneId,
        // A profile the phone doesn't have yet is added there empty.
        phoneEmpty: phoneId == null,
        useBase: access.linksFor(_phone).links[access.openId] == phoneId,
      );
      return (plan: plan, problem: null);
    } on SyncFailure catch (error) {
      settings.recordSyncError(error.message);
      return (plan: null, problem: error.message);
    } catch (_) {
      const message = 'Could not get the library from your phone.';
      settings.recordSyncError(message);
      return (plan: null, problem: message);
    }
  }

  /// Records that both sides already match, after a preview found nothing
  /// to do.
  void recordInSync() {
    settings.recordSync(at: DateTime.now(), changed: 0);
    _pending = null;
    notifyListeners();
  }

  /// A sync nobody asked for: when Chapterly opens or in the background.
  /// When the phone is not there it says nothing and records nothing. With
  /// "Show changes before syncing" on, changes that would remove books are
  /// held back for review instead (the other profiles still sync). Returns
  /// true when it synced.
  Future<bool> autoSync() async {
    if (_busy || !paired) return false;
    return PerfLog.timed('automatic sync', _autoSyncNow);
  }

  Future<bool> _autoSyncNow() async {
    // Only the phones that are here: one that is away is left alone and
    // says nothing.
    final reachable = <SyncPhone>[];
    for (final phone in phones) {
      final address = parsePhoneAddress(phone.address);
      if (address == null) continue;
      try {
        await client.ping(address);
        reachable.add(phone);
      } on SyncFailure {
        // Not on this network now.
      }
    }
    if (reachable.isEmpty) return false;
    final toSync = <String>{};
    final held = <String>{};
    var inSync = false;
    for (final phone in reachable) {
      if (!settings.reviewSync) {
        toSync.add(phone.id);
        continue;
      }
      final plan = (await preview(only: {phone.id})).plan;
      if (plan == null) continue;
      if (plan.removals > 0) {
        if (plan.signature != _dismissed) {
          _pending = plan;
          notifyListeners();
        }
        if (profiles != null) held.add(phone.id);
        continue;
      }
      if (plan.isEmpty && profiles == null) {
        recordInSync();
        inSync = true;
        continue;
      }
      toSync.add(phone.id);
    }
    if (held.isNotEmpty) await syncNow(skipOpen: true, only: held);
    if (held.isNotEmpty) return false;
    if (toSync.isEmpty) return inSync;
    return await syncNow(only: toSync) == null;
  }

  /// Syncs when Chapterly opens, if paired and switched on. Returns true
  /// when it synced.
  Future<bool> syncOnOpen() async {
    if (!settings.syncOnOpen) return false;
    _lastAutoAttempt = DateTime.now();
    return autoSync();
  }

  /// Whether a background sync should run now: paired, switched on, and the
  /// last sync or try was at least [AppSettings.syncEveryMinutes] ago.
  bool backgroundSyncDue(DateTime now) {
    final minutes = settings.syncEveryMinutes;
    if (minutes <= 0 || _busy || !paired) return false;
    DateTime? last = settings.lastSyncAt;
    final tried = _lastAutoAttempt;
    if (tried != null && (last == null || tried.isAfter(last))) last = tried;
    return last == null || now.difference(last) >= Duration(minutes: minutes);
  }

  /// Checks once a [tick] whether a background sync is due. Each tick also
  /// refreshes "Synced 5 min ago" at the top of the library.
  void startBackgroundSync({Duration tick = const Duration(minutes: 1)}) {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => runBackgroundTick());
  }

  /// One background check. Public for tests.
  Future<void> runBackgroundTick([DateTime? at]) async {
    notifyListeners();
    final now = at ?? DateTime.now();
    if (!backgroundSyncDue(now)) return;
    _lastAutoAttempt = now;
    if (await autoSync()) {
      final changed = settings.lastSyncChanged;
      if (changed > 0) onBackgroundSync?.call(changed);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Saves a new address for a paired phone (the first, unless [phone] says
  /// which), for example after the router gave it a new one. Returns null
  /// when it worked, or the message to show.
  Future<String?> changeAddress(String input, {String phone = ''}) async {
    final address = parsePhoneAddress(input);
    if (address == null) {
      return 'Type the address your phone shows, such as 192.168.1.20:8765.';
    }
    try {
      await client.ping(address);
    } on SyncFailure catch (error) {
      return error.message;
    }
    final text = formatPhoneAddress(address);
    if (phone.isEmpty) {
      settings.setSyncAddress(text);
    } else {
      settings.setExtraPhones([
        for (final other in settings.extraPhones)
          if (other.id == phone) other.copyWith(address: text) else other,
      ]);
    }
    notifyListeners();
    return null;
  }

  /// Looks for Chapterly phones on the home network and returns their
  /// addresses, such as 192.168.1.20:8765.
  Future<List<String>> findPhones() async {
    if (_busy) return const [];
    _setBusy(true);
    try {
      return await findPhonesOnNetwork(client);
    } catch (_) {
      return const [];
    } finally {
      _setBusy(false);
    }
  }

  /// Removes a phone's saved address and code, and which profiles go
  /// together (every phone, when [phone] is null).
  Future<void> forget([String? phone]) async {
    final ids = phone != null
        ? [phone]
        : phones.isEmpty
            ? ['']
            : [for (final p in phones) p.id];
    for (final id in ids) {
      try {
        await _codesOf(id).delete();
      } catch (_) {
        // Already gone.
      }
      if (id.isEmpty) {
        settings.setSyncAddress(null);
        _hasCode = false;
      } else {
        settings.setExtraPhones([
          for (final other in settings.extraPhones)
            if (other.id != id) other,
        ]);
        _extraCodes.remove(id);
      }
      settings.setPhoneSynced(id, null);
      _here.remove(id);
      await (await _baseOf(id)).save(const []);
      await profiles?.saveLinks(const ProfileLinks(), phone: id);
    }
    _pending = null;
    notifyListeners();
  }
}
