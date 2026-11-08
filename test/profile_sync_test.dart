import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/pc_sync.dart';
import 'package:chapterly/data/sync_profiles.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/data/sync_three_way.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phone_sync_core.dart';

const _code = 'ABCDEFGHJKMNPQRS';

Book _book(String id) => Book(
      id: id,
      title: 'Book $id',
      author: 'Author',
      shelf: Shelf.forLater,
      addedAt: DateTime(2026),
      updatedAt: DateTime(2026, 1, 1),
    );

List<String> _ids(List<Book> books) => [for (final b in books) b.id]..sort();

SyncProfileInfo _info(String id, String name, {bool locked = false}) =>
    SyncProfileInfo(id: id, name: name, color: 0, locked: locked);

/// One profile's library: on the phone or on the PC.
class _Library {
  final repository = BookRepository(InMemoryBookStore());
  final settings = AppSettings();
  final base = SyncBase();
  final _bases = <String, SyncBase>{};
  bool pin = false;

  /// The last-synced copy for a phone (empty: the first).
  SyncBase baseFor(String phone) =>
      phone.isEmpty ? base : _bases[phone] ??= SyncBase();

  Future<void> load(List<String> books) async {
    await repository.load();
    await repository.replaceAll([for (final id in books) _book(id)]);
  }

  List<String> get books => _ids(repository.allBooks);
}

/// A phone with profiles, running the real sync server and the phone app's
/// own merge code for each profile.
class _Phone implements SyncProfileHost {
  _Phone({this.everyProfile = true});

  final bool everyProfile;
  final names = <String, String>{};
  final libraries = <String, _Library>{};
  final _cores = <String, PhoneSyncCore>{};
  String open = 'main';
  late final SyncServer server;
  var added = 0;

  Future<void> add(String id, String name, List<String> books) async {
    final library = _Library();
    await library.load(books);
    names[id] = name;
    libraries[id] = library;
  }

  PhoneSyncCore _core(String id) => _cores[id] ??= PhoneSyncCore(
        repository: libraries[id]!.repository,
        settings: libraries[id]!.settings,
      );

  Future<void> start() async {
    server = SyncServer(
      token: _code,
      handleSync: (body) => _core(open).handleSync(body),
      covers: _core(open),
      profiles: everyProfile ? this : null,
    );
    await server.start(port: 0);
  }

  String get address => '127.0.0.1:${server.boundPort}';

  bool _locked(String id) => id != open && libraries[id]!.pin;

  @override
  Future<String> profiles(String body) async {
    for (final wanted in decodeProfileRequest(body)) {
      final id = 'new${added++}';
      await add(id, wanted.name, const []);
    }
    return encodeProfileList([
      for (final id in names.keys)
        _info(id, names[id]!, locked: _locked(id)),
    ]);
  }

  @override
  Future<SyncEndpoint?> endpoint(String id) async {
    if (!names.containsKey(id)) return null;
    if (_locked(id)) throw const ProfileLocked();
    return _core(id);
  }

  String? idOf(String name) {
    for (final entry in names.entries) {
      if (entry.value == name) return entry.key;
    }
    return null;
  }
}

/// The profiles on the PC.
class _PcProfiles implements SyncProfileAccess {
  final names = <String, String>{};
  final libraries = <String, _Library>{};
  @override
  String openId = 'main';
  final _saved = <String, ProfileLinks>{};
  ProfileLinks get saved => _saved[''] ?? const ProfileLinks();
  var opened = 0;
  var closed = 0;

  Future<_Library> add(String id, String name, List<String> books) async {
    final library = _Library();
    await library.load(books);
    names[id] = name;
    libraries[id] = library;
    return library;
  }

  @override
  List<SyncProfileInfo> list() => [
        for (final id in names.keys)
          _info(id, names[id]!, locked: id != openId && libraries[id]!.pin),
      ];

  @override
  Future<String?> create(String name, int color) async {
    final id = 'pc${names.length}';
    await add(id, name, const []);
    return id;
  }

  @override
  Future<SyncTarget> open(String id, {String phone = ''}) async {
    opened++;
    final library = libraries[id]!;
    return SyncTarget(
      repository: library.repository,
      settings: library.settings,
      base: library.baseFor(phone),
    );
  }

  @override
  Future<void> close(SyncTarget target) async => closed++;

  @override
  ProfileLinks linksFor(String phone) => _saved[phone] ?? const ProfileLinks();

  @override
  Future<void> saveLinks(ProfileLinks links, {String phone = ''}) async =>
      _saved[phone] = links;

  String? idOf(String name) {
    for (final entry in names.entries) {
      if (entry.value == name) return entry.key;
    }
    return null;
  }
}

void main() {
  group('pairing up profiles', () {
    test('same names pair up, and the first profiles pair with each other',
        () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Hans'), _info('a1', 'Anna')],
        phone: [_info('main', 'Me'), _info('b1', 'anna ')],
      );
      expect(plan.links.links, {'a1': 'b1', 'main': 'main'});
      expect(plan.createOnPhone, isEmpty);
      expect(plan.createOnPc, isEmpty);
    });

    test('a name beats the first profile', () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Hans')],
        phone: [_info('main', 'Me'), _info('b1', 'Hans')],
      );
      expect(plan.links.links, {'main': 'b1'});
      expect([for (final p in plan.createOnPc) p.name], ['Me']);
    });

    test('profiles left over are added on the other side, but not with a PIN',
        () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Me'), _info('a1', 'Anna'), _info('s1', 'Secret', locked: true)],
        phone: [_info('main', 'Me'), _info('b1', 'Bob'), _info('k1', 'Kid', locked: true)],
      );
      expect([for (final p in plan.createOnPhone) p.name], ['Anna']);
      expect([for (final p in plan.createOnPc) p.name], ['Bob']);
    });

    test('a profile removed on one side is not added back', () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Me'), _info('a1', 'Anna')],
        phone: [_info('main', 'Me'), _info('b1', 'Bob')],
        saved: const ProfileLinks(
          links: {'main': 'main', 'a1': 'gone', 'gone2': 'b1'},
        ),
      );
      expect(plan.links.links, {'main': 'main'});
      expect(plan.createOnPhone, isEmpty);
      expect(plan.createOnPc, isEmpty);
      expect(plan.links.leftOnPc, {'a1'});
      expect(plan.links.leftOnPhone, {'b1'});
    });

    test('pairs from last time are kept after a rename', () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Me'), _info('a1', 'Annie')],
        phone: [_info('main', 'Me'), _info('b1', 'Anna')],
        saved: const ProfileLinks(links: {'main': 'main', 'a1': 'b1'}),
      );
      expect(plan.links.links, {'main': 'main', 'a1': 'b1'});
    });

    test('the pairs are saved and read back', () {
      const links = ProfileLinks(
        links: {'main': 'main'},
        leftOnPc: {'a1'},
        leftOnPhone: {'b1'},
      );
      final back = ProfileLinks.fromJson(links.toJson());
      expect(back.links, links.links);
      expect(back.leftOnPc, links.leftOnPc);
      expect(back.leftOnPhone, links.leftOnPhone);
      expect(ProfileLinks.fromJson('not json').isEmpty, isTrue);
    });

    test('profile paths', () {
      expect(profileSyncPath(null, '/sync'), '/v2/sync');
      expect(profileSyncPath('main', '/covers/x'), '/v2/p/main/covers/x');
      final split = splitProfilePath('/v2/p/k3x9q2ab/covers/missing');
      expect(split?.id, 'k3x9q2ab');
      expect(split?.path, '/v2/covers/missing');
      expect(splitProfilePath('/v2/p/../sync'), isNull);
      expect(splitProfilePath('/v2/p/main'), isNull);
    });
  });

  group('one pairing syncs every profile', () {
    late _Phone phone;
    late _PcProfiles pcProfiles;
    late _Library pcMain;
    late PcSync sync;

    Future<void> setUpSync({bool everyProfile = true}) async {
      phone = _Phone(everyProfile: everyProfile);
      await phone.add('main', 'Me', ['phone-me']);
      await phone.add('b1', 'Bob', ['phone-bob']);
      await phone.add('k1', 'Kid', ['phone-kid']);
      phone.libraries['k1']!.pin = true;
      await phone.start();
      pcProfiles = _PcProfiles();
      pcMain = await pcProfiles.add('main', 'Me', ['pc-me']);
      await pcProfiles.add('a1', 'Anna', ['pc-anna']);
      sync = PcSync(
        repository: pcMain.repository,
        settings: pcMain.settings,
        codeStore: MemoryCodeStore(),
        base: pcMain.base,
        client: SyncClient(pingTimeout: const Duration(seconds: 2)),
        profiles: pcProfiles,
      );
    }

    tearDown(() => phone.server.stop());

    test('profiles are added on both sides and every library syncs', () async {
      await setUpSync();

      final problem = await sync.pair(address: phone.address, code: _code);

      expect(problem, isNull);
      expect(sync.lastNote, isNull);
      // Your own profile.
      expect(pcMain.books, ['pc-me', 'phone-me']);
      expect(phone.libraries['main']!.books, ['pc-me', 'phone-me']);
      // Anna was added on the phone, Bob on the PC.
      final anna = phone.idOf('Anna');
      expect(anna, isNotNull);
      expect(phone.libraries[anna]!.books, ['pc-anna']);
      final bob = pcProfiles.idOf('Bob');
      expect(bob, isNotNull);
      expect(pcProfiles.libraries[bob]!.books, ['phone-bob']);
      // Kid has a PIN on the phone and isn't open there: not copied.
      expect(pcProfiles.idOf('Kid'), isNull);
      expect(pcProfiles.saved.links, {'main': 'main', 'a1': anna, bob: 'b1'});
      // Each library opened for the sync was closed again.
      expect(pcProfiles.closed, pcProfiles.opened);
      expect(pcProfiles.opened, 2);
    });

    test('a profile with a PIN on the phone waits until it is open there',
        () async {
      await setUpSync();
      await pcProfiles.add('k9', 'Kid', ['pc-kid']);

      expect(await sync.pair(address: phone.address, code: _code), isNull);
      expect(sync.lastNote, contains('Kid'));
      expect(sync.lastNote, contains('PIN on your phone'));
      expect(phone.libraries['k1']!.books, ['phone-kid']);
      expect(pcProfiles.libraries['k9']!.books, ['pc-kid']);

      // Opened on the phone: it syncs.
      phone.open = 'k1';
      expect(await sync.syncNow(), isNull);
      expect(phone.libraries['k1']!.books, ['pc-kid', 'phone-kid']);
      expect(pcProfiles.libraries['k9']!.books, ['pc-kid', 'phone-kid']);
    });

    test('a profile with a PIN on this PC syncs only while it is open here',
        () async {
      await setUpSync();
      pcProfiles.libraries['a1']!.pin = true;

      expect(await sync.pair(address: phone.address, code: _code), isNull);
      expect(sync.lastNote, contains('Anna'));
      expect(sync.lastNote, contains('PIN here'));
      expect(phone.idOf('Anna'), isNull);
    });

    test('later syncs keep the pairs and move changes', () async {
      await setUpSync();
      expect(await sync.pair(address: phone.address, code: _code), isNull);
      final bob = pcProfiles.idOf('Bob')!;
      final bobsBooks = pcProfiles.libraries[bob]!.repository;
      await bobsBooks.replaceAll([...bobsBooks.allBooks, _book('pc-bob')]);

      expect(await sync.syncNow(), isNull);

      expect(phone.libraries['b1']!.books, ['pc-bob', 'phone-bob']);
      expect(pcProfiles.names.length, 3);
      expect(phone.names.length, 4);
    });

    test('a phone without profile sync gets the open profile only', () async {
      await setUpSync(everyProfile: false);

      expect(await sync.pair(address: phone.address, code: _code), isNull);

      expect(pcMain.books, ['pc-me', 'phone-me']);
      expect(phone.names.length, 3);
      expect(pcProfiles.names.length, 2);
      expect(pcProfiles.opened, 0);
    });
  });

  group('several phones', () {
    late _Phone first;
    late _Phone second;
    late _PcProfiles pcProfiles;
    late _Library pcMain;
    late PcSync sync;
    final codes = <String, MemoryCodeStore>{};

    setUp(() async {
      codes.clear();
      first = _Phone();
      await first.add('main', 'Me', ['one']);
      await first.start();
      second = _Phone();
      await second.add('main', 'Me', ['two']);
      await second.start();
      pcProfiles = _PcProfiles();
      pcMain = await pcProfiles.add('main', 'Me', ['pc']);
      sync = PcSync(
        repository: pcMain.repository,
        settings: pcMain.settings,
        codeStore: MemoryCodeStore(),
        base: pcMain.base,
        client: SyncClient(pingTimeout: const Duration(seconds: 2)),
        profiles: pcProfiles,
        codeStoreFor: (id) => codes[id] ??= MemoryCodeStore(),
        baseFor: (id) async => pcMain.baseFor(id),
      );
    });

    tearDown(() async {
      await first.server.stop();
      await second.server.stop();
    });

    test('a second phone is added, and books reach every phone', () async {
      expect(await sync.pair(address: first.address, code: _code), isNull);
      expect(sync.phones.map((p) => p.name), ['Phone 1']);

      expect(await sync.pair(address: second.address, code: _code), isNull);
      expect(sync.phones.map((p) => p.name), ['Phone 1', 'Phone 2']);
      expect(sync.phones.map((p) => p.id), ['', 'p2']);

      // Syncing every phone brings each one's books to the others.
      expect(await sync.syncNow(), isNull);
      const all = ['one', 'pc', 'two'];
      expect(pcMain.books, all);
      expect(first.libraries['main']!.books, all);
      expect(second.libraries['main']!.books, all);
    });

    test('a removal on one phone reaches the other', () async {
      await sync.pair(address: first.address, code: _code);
      await sync.pair(address: second.address, code: _code);
      expect(await sync.syncNow(), isNull);

      await first.libraries['main']!.repository.deleteForever('two');
      expect(await sync.syncNow(), isNull);

      expect(second.libraries['main']!.books, ['one', 'pc']);
      expect(pcMain.books, ['one', 'pc']);
    });

    test('pairing the same phone again does not add another', () async {
      await sync.pair(address: first.address, code: _code);
      await sync.pair(address: first.address, code: _code);
      expect(sync.phones, hasLength(1));
    });

    test('a wrong code is not kept and leaves the others alone', () async {
      await sync.pair(address: first.address, code: _code);
      final problem =
          await sync.pair(address: second.address, code: 'AAAAAAAAAAAAAAAA');
      expect(problem, isNotNull);
      expect(sync.phones, hasLength(1));
    });

    test('a wrong code for a phone already paired leaves it paired', () async {
      await sync.pair(address: first.address, code: _code);
      final problem =
          await sync.pair(address: first.address, code: 'AAAAAAAAAAAAAAAA');
      expect(problem, isNotNull);
      expect(sync.phones, hasLength(1));
      expect(await sync.syncNow(), isNull);
    });

    test('forgetting one phone keeps the other', () async {
      await sync.pair(address: first.address, code: _code);
      await sync.pair(address: second.address, code: _code);

      await sync.forget('p2');
      expect(sync.phones.map((p) => p.name), ['Phone 1']);
      expect(sync.paired, isTrue);

      await sync.forget();
      expect(sync.paired, isFalse);
    });

    test('a phone that is away is named, and the others still sync', () async {
      await sync.pair(address: first.address, code: _code);
      await sync.pair(address: second.address, code: _code);
      await second.server.stop();

      final problem = await sync.syncNow();
      expect(problem, startsWith('Phone 2:'));
      expect(first.libraries['main']!.books, contains('two'));
    });

    test('an automatic sync leaves a phone that is away alone', () async {
      await sync.pair(address: first.address, code: _code);
      await sync.pair(address: second.address, code: _code);
      await second.server.stop();
      await first.libraries['main']!.repository.replaceAll([
        for (final id in ['one', 'new-one']) _book(id),
      ]);

      expect(await sync.autoSync(), isTrue);
      expect(pcMain.books, contains('new-one'));
      expect(pcMain.settings.lastSyncError, isNull);
    });

    test('each phone shows if it is here and when it last synced', () async {
      await sync.pair(address: first.address, code: _code);
      await sync.pair(address: second.address, code: _code);
      // Pairing syncs once, so both phones have a time.
      expect(pcMain.settings.phoneSynced.keys, unorderedEquals(['', 'p2']));

      await sync.checkPhones();
      expect(sync.phonesHere, {'': true, 'p2': true});

      await second.server.stop();
      await sync.checkPhones();
      expect(sync.phonesHere, {'': true, 'p2': false});

      // A sync with only the first phone leaves the other's time alone.
      final before = pcMain.settings.phoneSynced['p2'];
      expect(await sync.syncNow(only: {''}), isNull);
      expect(pcMain.settings.phoneSynced['p2'], before);

      // Forgetting a phone forgets its time.
      await sync.forget('p2');
      expect(pcMain.settings.phoneSynced.keys, ['']);
      await sync.forget();
      expect(pcMain.settings.phoneSynced, isEmpty);
    });
  });
}
