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
import 'sync_covers.dart';
import 'sync_crypto.dart';
import 'sync_merge.dart';
import 'sync_plan.dart';
import 'sync_protocol.dart';

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
  Future<void> ping(Uri address) async {
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
  Future<SyncPayload> sync(SyncSession session, String body) async {
    final _Answer answer;
    try {
      answer = await _sealed(
        session,
        'POST',
        '/v2/sync',
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
          '/v2/sync',
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
        throw _notChapterly;
      case 409:
        throw MissingCovers(_hashesIn(text));
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
    List<String> hashes,
  ) async {
    if (hashes.isEmpty) return const [];
    final answer = await _sealed(
      session,
      'POST',
      '/v2/covers/missing',
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
    String dataUrl,
  ) async {
    final answer = await _sealed(
      session,
      'PUT',
      '/v2/covers/$hash',
      dataUrl,
      limit: maxOtherReplyBytes,
      step: 'covers',
    );
    _checkCovers(answer);
  }

  /// Takes one cover picture from the phone, or null when it has none by
  /// that name.
  Future<String?> getCover(SyncSession session, String hash) async {
    final answer = await _sealed(
      session,
      'GET',
      '/v2/covers/$hash',
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

/// Pairs with the phone and syncs: when asked, when Chapterly opens, and
/// every few minutes while it is open (see Settings).
class PcSync extends ChangeNotifier {
  PcSync({
    required this.repository,
    required this.settings,
    required this.codeStore,
    SyncClient? client,
    SyncBase? base,
  })  : client = client ?? SyncClient(),
        base = base ?? SyncBase();

  final BookRepository repository;
  final AppSettings settings;
  final CodeStore codeStore;
  final SyncClient client;

  /// The books as they were after the last sync, for merging books changed
  /// on both sides field by field (Windows app).
  final SyncBase base;

  bool _busy = false;
  bool _hasCode = false;
  SyncPlan? _pending;
  String? _dismissed;
  Timer? _timer;
  DateTime? _lastAutoAttempt;

  /// Called after a sync in the background changed books here, with how
  /// many. The library uses it to show a message.
  void Function(int changed)? onBackgroundSync;

  /// Changes an automatic sync held back because they would remove books.
  /// The library offers to review them.
  SyncPlan? get pendingReview => _pending;

  /// Hides [pendingReview] until the changes waiting are different.
  void dismissPending() {
    _dismissed = _pending?.signature;
    _pending = null;
    notifyListeners();
  }

  /// True while connecting or syncing.
  bool get busy => _busy;

  /// Whether an address and a pairing code are saved.
  bool get paired => _hasCode && settings.syncAddress != null;

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
  /// first sync is what proves the code is right. Returns null when it
  /// worked, or the message to show.
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
    _setBusy(true);
    try {
      await client.ping(base);
      await codeStore.write(clean);
    } on SyncFailure catch (error) {
      _setBusy(false);
      return error.message;
    } catch (_) {
      _setBusy(false);
      return 'Windows could not save the pairing code.';
    }
    settings.setSyncAddress(formatPhoneAddress(base));
    _hasCode = true;
    _busy = false;
    // A new pairing starts without a last-synced copy.
    await this.base.save(const []);
    final problem = await syncNow();
    // Only keep the pairing when the first sync worked, so a wrong code is
    // not saved.
    if (problem != null) await forget();
    return problem;
  }

  /// Sends [body] (books with cover references) after giving the phone the
  /// pictures it lacks, and returns its reply with references too.
  Future<SyncPayload> _exchange(
    SyncSession session,
    String body,
    List<String> covers,
    CoverPool pool,
  ) async {
    Future<SyncPayload> post() async {
      final reply = await client.sync(session, body);
      return SyncPayload(
        books: withCoverRefs(reply.books, pool),
        tombstones: reply.tombstones,
        features: reply.features,
        wishes: reply.wishes,
      );
    }

    await _giveCovers(session, covers, pool);
    try {
      return await post();
    } on MissingCovers catch (lacking) {
      // The phone lost some pictures since it was asked: give them again.
      await _giveCovers(session, lacking.hashes, pool, ask: false);
      return await post();
    }
  }

  Future<void> _giveCovers(
    SyncSession session,
    List<String> hashes,
    CoverPool pool, {
    bool ask = true,
  }) async {
    if (hashes.isEmpty) return;
    final lacking =
        ask ? await client.missingCovers(session, hashes) : hashes;
    await forEachLimited(lacking, (hash) async {
      final picture = pool[hash];
      if (picture == null) {
        throw const SyncFailure('A cover could not be read on this PC.');
      }
      await client.putCover(session, hash, picture);
    });
  }

  /// Takes the pictures this PC lacks from the phone. A book whose picture
  /// the phone no longer has comes back without a cover rather than holding
  /// up the sync.
  /// Fetches the pictures [books] name that this PC does not have yet.
  Future<void> _fetchPictures(
    SyncSession session,
    List<Book> books,
    CoverPool pool,
  ) async {
    await forEachLimited(missingCovers(books, pool), (hash) async {
      final picture = await client.getCover(session, hash);
      if (picture == null) return;
      try {
        pool.put(hash, picture);
      } on FormatException {
        // A damaged picture: the book is left without a cover.
      }
    });
  }

  /// [books] with their pictures from [pool]. One it does not have is
  /// left without a cover rather than holding up the sync. Does not wait
  /// for anything, so nothing can change the library in between.
  List<Book> _attachPictures(List<Book> books, CoverPool pool) {
    final lost = missingCovers(books, pool).toSet();
    return withCoverPictures([
      for (final book in books)
        if (lost.contains(hashOfCoverRef(book.coverUrl)))
          book.copyWith(coverUrl: () => null)
        else
          book,
    ], pool);
  }

  /// Sends this library to the phone and takes back the merged library.
  /// Returns null when it worked, or the message to show.
  Future<String?> syncNow() async {
    if (_busy) return 'A sync is already running.';
    final saved = settings.syncAddress;
    final address = saved == null ? null : parsePhoneAddress(saved);
    final code = await codeStore.read();
    if (address == null || code == null) {
      return 'Connect to your phone first, in Settings.';
    }
    _setBusy(true);
    try {
      // Books travel with cover references; the pictures are given to the
      // phone, or taken from it, only when one side lacks them.
      final pool = CoverPool();
      // The key and the phone's challenge, for every request of this run.
      final session = await client.connect(address, code);
      SyncPayload? phone;
      if (!base.isEmpty) {
        // Ask for the phone's library (sending none changes nothing there)
        // to merge books changed on both sides before sending.
        phone = await _exchange(
          session,
          encodeSyncPayload(const [], const {}),
          const [],
          pool,
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
      );
      // The pictures this PC does not have yet come from the phone. They
      // are fetched first: from the snapshot below until the library is
      // saved, nothing waits, so a change made meanwhile can't be lost.
      await _fetchPictures(session, reply.books, pool);
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
      final books = _attachPictures(refBooks, pool);
      final changed = countSyncChanges(now.books, books);
      await repository.applySynced(books, merged.tombstones);
      // The wish list: the newer copy of each wish wins, including a wish
      // changed on this PC while the sync was running.
      settings.mergeWishesFrom(reply.wishes);
      // What the phone holds now. A change made on this PC during the sync
      // is not in it, so the next sync still sees it as a PC change.
      await base.save(reply.books);
      settings.recordSync(at: DateTime.now(), changed: changed);
      _pending = null;
      return null;
    } on SyncFailure catch (error) {
      settings.recordSyncError(error.message);
      return error.message;
    } catch (_) {
      const message = 'The sync could not be finished.';
      settings.recordSyncError(message);
      return message;
    } finally {
      _setBusy(false);
    }
  }

  /// Works out what a sync would change on this PC and on the phone,
  /// without changing anything. It asks the phone for its library by sending
  /// an empty one: merging nothing into the phone's library leaves it as it
  /// is. Returns the plan, or the message to show.
  Future<({SyncPlan? plan, String? problem})> preview() async {
    if (_busy) return (plan: null, problem: 'A sync is already running.');
    final saved = settings.syncAddress;
    final address = saved == null ? null : parsePhoneAddress(saved);
    final code = await codeStore.read();
    if (address == null || code == null) {
      return (plan: null, problem: 'Connect to your phone first, in Settings.');
    }
    _setBusy(true);
    try {
      final phone = await client.sync(
        await client.connect(address, code),
        encodeSyncPayload(const [], const {}),
      );
      final now = repository.snapshot();
      // Books changed on both sides are shown as the sync will merge them.
      final resolved = base.isEmpty
          ? const <Book>[]
          : resolveConflicts(
              base: base.books,
              local: now.books,
              remote: phone.books,
              now: DateTime.now(),
              phoneKeepsBookmarks: phone.features.contains('audioBookmarks'),
            );
      final byId = {for (final book in resolved) book.id: book};
      final plan = planSync(
        phoneBooks: phone.books,
        phoneTombstones: phone.tombstones,
        pcBooks: [for (final book in now.books) byId[book.id] ?? book],
        pcTombstones: now.tombstones,
      );
      return (plan: plan, problem: null);
    } on SyncFailure catch (error) {
      settings.recordSyncError(error.message);
      return (plan: null, problem: error.message);
    } catch (_) {
      const message = 'Could not get the library from your phone.';
      settings.recordSyncError(message);
      return (plan: null, problem: message);
    } finally {
      _setBusy(false);
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
  /// held back for review instead. Returns true when it synced.
  Future<bool> autoSync() async {
    if (_busy || !paired) return false;
    final address = parsePhoneAddress(settings.syncAddress ?? '');
    if (address == null) return false;
    try {
      await client.ping(address);
    } on SyncFailure {
      return false;
    }
    if (settings.reviewSync) {
      final plan = (await preview()).plan;
      if (plan == null) return false;
      if (plan.isEmpty) {
        recordInSync();
        return true;
      }
      if (plan.removals > 0) {
        if (plan.signature != _dismissed) {
          _pending = plan;
          notifyListeners();
        }
        return false;
      }
    }
    return await syncNow() == null;
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

  /// Saves a new address for the paired phone, for example after the router
  /// gave it a new one. Returns null when it worked, or the message to show.
  Future<String?> changeAddress(String input) async {
    final address = parsePhoneAddress(input);
    if (address == null) {
      return 'Type the address your phone shows, such as 192.168.1.20:8765.';
    }
    try {
      await client.ping(address);
    } on SyncFailure catch (error) {
      return error.message;
    }
    settings.setSyncAddress(formatPhoneAddress(address));
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

  /// Removes the saved address and code.
  Future<void> forget() async {
    try {
      await codeStore.delete();
    } catch (_) {
      // Already gone.
    }
    settings.setSyncAddress(null);
    await base.save(const []);
    _hasCode = false;
    _pending = null;
    notifyListeners();
  }
}
