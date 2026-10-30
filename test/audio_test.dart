import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chapterly/audio/audio_engine.dart';
import 'package:chapterly/audio/audio_files.dart';
import 'package:chapterly/audio/audio_library.dart';
import 'package:chapterly/audio/audio_probe.dart';
import 'package:chapterly/audio/listen_controller.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/models/audio_progress.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

// ---- bytes for test files

List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _u32(int v) =>
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _u64(int v) => [..._u32(v >> 32), ..._u32(v & 0xFFFFFFFF)];
List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32le(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _u64le(int v) => [..._u32le(v & 0xFFFFFFFF), ..._u32le(v >> 32)];

List<int> _box(String type, List<int> content) =>
    [..._u32(content.length + 8), ...ascii.encode(type), ...content];

List<int> _mvhd(int timescale, int duration) => _box('mvhd', [
      0, 0, 0, 0, // version and flags
      ..._u32(0), ..._u32(0), // created, changed
      ..._u32(timescale), ..._u32(duration),
      ...List.filled(80, 0),
    ]);

List<int> _ftyp() => _box('ftyp', [...ascii.encode('M4B '), ..._u32(0)]);

ByteSource _source(List<int> bytes) =>
    MemoryByteSource(Uint8List.fromList(bytes));

Uint8List _m4bWithNeroChapters() {
  final chapters = <int>[
    1, 0, 0, 0, // version 1, flags
    0, 0, 0, 0, // reserved
    2, // two chapters
    ..._u64(0), 7, ...ascii.encode('Opening'),
    ..._u64(18000000000), 6, ...ascii.encode('Middle'), // 1800 s
  ];
  return Uint8List.fromList([
    ..._ftyp(),
    ..._box('moov', [
      ..._mvhd(1000, 3600000),
      ..._box('udta', _box('chpl', chapters)),
    ]),
  ]);
}

Uint8List _m4bWithChapterTrack() {
  final first = [..._u16(5), ...ascii.encode('Intro')];
  final second = [..._u16(8), ...ascii.encode('Part Two')];
  List<int> trak(int id, List<int> rest) => _box('trak', [
        ..._box('tkhd', [
          0, 0, 0, 0,
          ..._u32(0), ..._u32(0),
          ..._u32(id),
          ...List.filled(68, 0),
        ]),
        ...rest,
      ]);
  List<int> moov(int dataOffset) => _box('moov', [
        ..._mvhd(1000, 180000),
        ...trak(1, _box('tref', _box('chap', _u32(2)))),
        ...trak(
          2,
          _box('mdia', [
            ..._box('mdhd', [
              0, 0, 0, 0,
              ..._u32(0), ..._u32(0),
              ..._u32(1000), ..._u32(180000),
              0, 0, 0, 0,
            ]),
            ..._box(
              'minf',
              _box('stbl', [
                ..._box('stts', [
                  0, 0, 0, 0, ..._u32(2),
                  ..._u32(1), ..._u32(60000),
                  ..._u32(1), ..._u32(120000),
                ]),
                ..._box('stsz', [
                  0, 0, 0, 0, ..._u32(0), ..._u32(2),
                  ..._u32(first.length), ..._u32(second.length),
                ]),
                ..._box('stsc', [
                  0, 0, 0, 0, ..._u32(1),
                  ..._u32(1), ..._u32(2), ..._u32(1),
                ]),
                ..._box('stco', [0, 0, 0, 0, ..._u32(1), ..._u32(dataOffset)]),
              ]),
            ),
          ]),
        ),
      ]);
  final ftyp = _ftyp();
  final offset = ftyp.length + moov(0).length + 8;
  return Uint8List.fromList([
    ...ftyp,
    ...moov(offset),
    ..._box('mdat', [...first, ...second]),
  ]);
}

Uint8List _mp3Cbr() => Uint8List.fromList([
      ...ascii.encode('ID3'), 3, 0, 0, 0, 0, 0, 0, // empty tag
      0xFF, 0xFB, 0x90, 0x00, // MPEG 1 layer 3, 128 kbps, 44.1 kHz
      ...List.filled(160000 - 4, 0),
    ]);

Uint8List _mp3Xing() => Uint8List.fromList([
      0xFF, 0xFB, 0x90, 0x00,
      ...List.filled(32, 0),
      ...ascii.encode('Xing'), ..._u32(1), ..._u32(1000),
      ...List.filled(400, 0),
    ]);

Uint8List _flac() {
  const rate = 44100;
  const total = 44100 * 60;
  return Uint8List.fromList([
    ...ascii.encode('fLaC'),
    0x80, 0, 0, 34,
    0, 16, 0, 16, 0, 0, 0, 0, 0, 0,
    rate >> 12, (rate >> 4) & 0xFF, ((rate & 0xF) << 4) | (1 << 1),
    0xF0 | ((total >> 32) & 0xF), ..._u32(total & 0xFFFFFFFF),
    ...List.filled(16, 0),
  ]);
}

Uint8List _opus() {
  List<int> page(int type, int granule, List<int> packet) => [
        ...ascii.encode('OggS'), 0, type, ..._u64le(granule),
        ..._u32le(1), ..._u32le(0), ..._u32le(0),
        1, packet.length, ...packet,
      ];
  final head = [
    ...ascii.encode('OpusHead'), 1, 2, ..._u16le(312), ..._u32le(48000),
    0, 0, 0,
  ];
  return Uint8List.fromList([
    ...page(2, 0, head),
    ...List.filled(1000, 0),
    ...page(4, 48000 * 30 + 312, List.filled(10, 0)),
  ]);
}

Uint8List _wav() => Uint8List.fromList([
      ...ascii.encode('RIFF'), ..._u32le(36), ...ascii.encode('WAVE'),
      ...ascii.encode('fmt '), ..._u32le(16),
      ..._u16le(1), ..._u16le(2), ..._u32le(44100), ..._u32le(176400),
      ..._u16le(4), ..._u16le(16),
      ...ascii.encode('data'), ..._u32le(176400 * 2),
    ]);

// ---- fakes

class FakeEngine implements AudioEngine {
  List<Uri> tracks = [];
  final List<Duration> lengths;
  double speed = 1;
  bool disposed = false;
  // Events arrive a moment later, as they do from a real player.
  final _changes = StreamController<void>.broadcast();
  final _completed = StreamController<void>.broadcast();

  FakeEngine(this.lengths);

  @override
  bool playing = false;
  @override
  int index = 0;
  @override
  Duration position = Duration.zero;

  @override
  Duration? get duration => index < lengths.length ? lengths[index] : null;

  @override
  Future<void> load(
    List<Uri> tracks, {
    required int index,
    required Duration position,
  }) async {
    this.tracks = tracks;
    this.index = index;
    this.position = position;
  }

  @override
  Future<void> play() async {
    playing = true;
    _changes.add(null);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _changes.add(null);
  }

  @override
  Future<void> seek(int index, Duration position) async {
    this.index = index;
    this.position = position;
    _changes.add(null);
  }

  @override
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  void finish() => _completed.add(null);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<void> get completed => _completed.stream;
}

class FakeFiles implements AudioFiles {
  FakeFiles(this.contents);

  final Map<String, Uint8List> contents;
  final released = <String>[];

  @override
  Future<List<PickedFile>?> pickFile() async => null;

  @override
  Future<List<PickedFile>?> pickFolder() async => null;

  @override
  ByteSource open(String location) =>
      MemoryByteSource(contents[location] ?? Uint8List(0));

  @override
  Uri playable(String location) => Uri.parse('test:$location');

  @override
  Future<void> release(List<String> locations) async =>
      released.addAll(locations);
}

AudioLink _threeFiles() => const AudioLink(tracks: [
      AudioTrack(location: 'a', name: '01 One.mp3', lengthMs: 60000),
      AudioTrack(location: 'b', name: '02 Two.mp3', lengthMs: 120000),
      AudioTrack(location: 'c', name: '03 Three.mp3', lengthMs: 30000),
    ]);

void main() {
  group('progress', () {
    test('goes to and from JSON, and ignores rubbish', () {
      const progress = AudioProgress(
        positionMs: 90000,
        lengthMs: 210000,
        track: 1,
        trackMs: 30000,
        trackCount: 3,
      );
      expect(AudioProgress.fromJson(progress.toJson()), progress);
      expect(AudioProgress.fromJson(jsonDecode(jsonEncode(progress.toJson()))),
          progress);
      expect(AudioProgress.fromJson('nope'), isNull);
      expect(AudioProgress.fromJson({'positionMs': 'x'}), isNull);
      expect(progress.fraction, closeTo(0.4286, 0.001));
      expect(const AudioProgress(positionMs: 5).fraction, isNull);
    });

    test('is saved with the book and synced', () {
      final book = Book(
        id: '1',
        title: 'Dune',
        author: 'Frank Herbert',
        shelf: Shelf.inProgress,
        addedAt: DateTime(2026),
        audio: const AudioProgress(positionMs: 1234, lengthMs: 5000),
      );
      expect(Book.fromJson(book.toJson()).audio, book.audio);
      expect(Book.fromMap(book.toMap()).audio, book.audio);
      final none = book.copyWith(audio: () => null);
      expect(Book.fromJson(none.toJson()).audio, isNull);
      expect(Book.fromMap(none.toMap()).audio, isNull);
    });

    test('times read nicely', () {
      expect(formatListenTime(40000), '40 s');
      expect(formatListenTime(12 * 60000), '12 min');
      expect(formatListenTime(3 * 3600000), '3 h');
      expect(formatListenTime(3 * 3600000 + 5 * 60000), '3 h 5 min');
      expect(formatPlayerClock(const Duration(minutes: 2, seconds: 3)), '2:03');
      expect(
        formatPlayerClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  group('files and chapters', () {
    test('sorts file names the way people count', () {
      final names = ['10 End.mp3', '2 Middle.mp3', '1 Start.mp3', 'b.mp3', 'a.mp3']
        ..sort(naturalCompare);
      expect(names, ['1 Start.mp3', '2 Middle.mp3', '10 End.mp3', 'a.mp3', 'b.mp3']);
      expect(isAudioFileName('Book.M4B'), isTrue);
      expect(isAudioFileName('cover.jpg'), isFalse);
      expect(trackTitle(r'CD 1\03 The Desert.mp3'), '03 The Desert');
      expect(trackTitle('Part 2.m4a'), 'Part 2');
    });

    test('works out the place in a book of several files', () {
      final link = _threeFiles();
      expect(link.lengthMs, 210000);
      expect(link.startOfTrack(2), 180000);
      final progress = link.progressAt(1, 30000);
      expect(progress.positionMs, 90000);
      expect(progress.trackCount, 3);
      expect(link.resumeAt(progress), (track: 1, trackMs: 30000));
      expect(link.resumeAt(null), (track: 0, trackMs: 0));
    });

    test('resumes by time when the other device has other files', () {
      final link = _threeFiles();
      const fromPhone = AudioProgress(positionMs: 200000, trackCount: 1);
      expect(link.resumeAt(fromPhone), (track: 2, trackMs: 20000));
      const pastTheEnd = AudioProgress(positionMs: 999999, trackCount: 1);
      expect(link.resumeAt(pastTheEnd), (track: 2, trackMs: 30000));
      const single = AudioLink(
        tracks: [AudioTrack(location: 'x', name: 'Book.m4b', lengthMs: 210000)],
      );
      expect(
        single.resumeAt(link.progressAt(2, 5000)),
        (track: 0, trackMs: 185000),
      );
    });

    test('a folder has one chapter per file', () {
      final link = _threeFiles();
      expect([for (final c in link.allChapters) c.title],
          ['01 One', '02 Two', '03 Three']);
      expect(link.chapterAt(1, 5000), 1);
      expect(link.withTrackLength(2, 31000).tracks[2].lengthMs, 31000);
    });

    test('chapters inside one file', () {
      const link = AudioLink(
        tracks: [AudioTrack(location: 'x', name: 'Book.m4b')],
        chapters: [
          AudioChapter(title: 'One', track: 0, startMs: 0),
          AudioChapter(title: 'Two', track: 0, startMs: 60000),
        ],
      );
      expect(link.lengthMs, isNull);
      expect(link.chapterAt(0, 59999), 0);
      expect(link.chapterAt(0, 60000), 1);
      final again = AudioLink.fromJson(jsonDecode(jsonEncode(link.toJson())));
      expect(again!.chapters.last.title, 'Two');
      expect(AudioLink.fromJson({'tracks': []}), isNull);
    });

    test('the list of audio is saved in a file', () async {
      final dir = await Directory.systemTemp.createTemp('chapterly_audio');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/audio_library.json');
      final library = await AudioLibrary.load(file);
      await library.setLink('book', _threeFiles());
      await library.setSpeed(1.5);
      await library.setTrackLength('book', 0, 61000);

      final again = await AudioLibrary.load(file);
      expect(again.speed, 1.5);
      expect(again.linkFor('book')!.tracks.first.lengthMs, 61000);
      await again.remove('book');
      expect((await AudioLibrary.load(file)).hasAudio('book'), isFalse);

      await file.writeAsString('not json');
      expect((await AudioLibrary.load(file)).hasAudio('book'), isFalse);
    });
  });

  group('reading lengths and chapters', () {
    test('M4B with Nero chapters', () async {
      final info = await probeAudio(_source(_m4bWithNeroChapters()));
      expect(info.lengthMs, 3600000);
      expect([for (final c in info.chapters) c.title], ['Opening', 'Middle']);
      expect([for (final c in info.chapters) c.startMs], [0, 1800000]);
    });

    test('M4B with a chapter track', () async {
      final info = await probeAudio(_source(_m4bWithChapterTrack()));
      expect(info.lengthMs, 180000);
      expect([for (final c in info.chapters) c.title], ['Intro', 'Part Two']);
      expect([for (final c in info.chapters) c.startMs], [0, 60000]);
    });

    test('MP3 at a constant bit rate, and with a Xing header', () async {
      expect((await probeAudio(_source(_mp3Cbr()))).lengthMs, 10000);
      expect((await probeAudio(_source(_mp3Xing()))).lengthMs, 26122);
    });

    test('FLAC, Opus and WAV', () async {
      expect((await probeAudio(_source(_flac()))).lengthMs, 60000);
      expect((await probeAudio(_source(_opus()))).lengthMs, 30000);
      expect((await probeAudio(_source(_wav()))).lengthMs, 2000);
    });

    test('anything else gives nothing, without failing', () async {
      final info = await probeAudio(_source(List.filled(100, 7)));
      expect(info.lengthMs, isNull);
      expect(info.chapters, isEmpty);
      expect((await probeAudio(_source([1, 2]))).lengthMs, isNull);
    });

    test('picked files become a book\'s audio in order', () async {
      final files = FakeFiles({
        'x/10.mp3': _mp3Cbr(),
        'x/2.mp3': _mp3Xing(),
        'x/cover.jpg': Uint8List(10),
      });
      final link = await buildAudioLink(files, const [
        PickedFile(location: 'x/10.mp3', name: '10.mp3'),
        PickedFile(location: 'x/cover.jpg', name: 'cover.jpg'),
        PickedFile(location: 'x/2.mp3', name: '2.mp3'),
      ]);
      expect([for (final t in link!.tracks) t.name], ['2.mp3', '10.mp3']);
      expect(link.lengthMs, 26122 + 10000);
      expect(link.allChapters.length, 2);

      final single = await buildAudioLink(
        FakeFiles({'b.m4b': _m4bWithNeroChapters()}),
        const [PickedFile(location: 'b.m4b', name: 'Book.m4b')],
      );
      expect(single!.chapters.length, 2);
      expect(
        await buildAudioLink(files, const [
          PickedFile(location: 'x/cover.jpg', name: 'cover.jpg'),
        ]),
        isNull,
      );
    });
  });

  group('player', () {
    late BookRepository repository;
    late AudioLibrary library;
    late FakeFiles files;
    late FakeEngine engine;
    late DateTime now;
    late ListenController controller;
    late String id;

    setUp(() async {
      repository = BookRepository(InMemoryBookStore());
      await repository.load();
      await repository.add(title: 'Dune', author: 'F', shelf: Shelf.inProgress);
      id = repository.books.single.id;
      library = AudioLibrary();
      await library.setLink(id, _threeFiles());
      files = FakeFiles({});
      engine = FakeEngine(const [
        Duration(seconds: 60),
        Duration(seconds: 120),
        Duration(seconds: 30),
      ]);
      now = DateTime(2026, 10, 30, 20);
      controller = ListenController(
        repository: repository,
        library: library,
        files: files,
        engine: () => engine,
        now: () => now,
        saveEvery: const Duration(hours: 1),
      );
    });

    tearDown(() => controller.dispose());

    test('opens where you left off, even on another device', () async {
      await repository.setAudioProgress(
        id,
        const AudioProgress(positionMs: 70000, trackCount: 1),
      );
      expect(await controller.open(id, autoplay: false), isNull);
      expect(engine.tracks.length, 3);
      expect(engine.index, 1);
      expect(engine.position, const Duration(seconds: 10));
      expect(controller.chapterIndex, 1);
    });

    test('saves the place and the time listened when paused', () async {
      await controller.open(id);
      await pumpEventQueue();
      expect(controller.playing, isTrue);
      now = now.add(const Duration(minutes: 12, seconds: 40));
      engine.position = const Duration(seconds: 45);
      await controller.pause();
      await pumpEventQueue();
      final book = repository.byId(id)!;
      expect(book.audio!.positionMs, 45000);
      expect(book.readingLog.single.minutes, 12);

      // The rest carries over, and the same day stays one entry.
      await controller.play();
      await pumpEventQueue();
      now = now.add(const Duration(minutes: 1));
      await controller.close();
      await pumpEventQueue();
      expect(repository.byId(id)!.readingLog.single.minutes, 14);
      expect(engine.disposed, isTrue);
      expect(controller.active, isFalse);
    });

    test('skips across files', () async {
      await controller.open(id, autoplay: false);
      engine
        ..index = 0
        ..position = const Duration(seconds: 50);
      await controller.skip(const Duration(seconds: 30));
      expect((engine.index, engine.position), (1, const Duration(seconds: 20)));
      await controller.skip(const Duration(seconds: -30));
      expect((engine.index, engine.position), (0, const Duration(seconds: 50)));
      engine.position = const Duration(seconds: 10);
      await controller.skip(const Duration(seconds: -30));
      expect((engine.index, engine.position), (0, Duration.zero));
    });

    test('moves between chapters', () async {
      await controller.open(id, autoplay: false);
      await controller.nextChapter();
      expect(engine.index, 1);
      engine.position = const Duration(seconds: 2);
      await controller.previousChapter();
      expect(engine.index, 0, reason: 'just started, so the previous one');
      await controller.goToChapter(2);
      engine.position = const Duration(seconds: 20);
      await controller.previousChapter();
      expect((engine.index, engine.position), (2, Duration.zero));
    });

    test('speed is used and remembered', () async {
      await controller.open(id, autoplay: false);
      await controller.setSpeed(1.75);
      expect(engine.speed, 1.75);
      expect(library.speed, 1.75);
    });

    test('the sleep timer pauses', () async {
      await controller.open(id);
      await pumpEventQueue();
      controller.setSleepTimer(const Duration(milliseconds: 20));
      expect(controller.sleepLeft, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.playing, isFalse);
      expect(controller.sleepLeft, isNull);
    });

    test('stopping at the end of the chapter', () async {
      await controller.open(id);
      await pumpEventQueue();
      controller.sleepAtEndOfChapter();
      expect(controller.sleepAtChapterEnd, isTrue);
      await engine.seek(1, Duration.zero);
      await pumpEventQueue();
      expect(controller.playing, isFalse);
      expect(controller.sleepAtChapterEnd, isFalse);
    });

    test('the end of the book saves it as heard and asks about Finished',
        () async {
      Book? finished;
      controller.onFinished = (book) => finished = book;
      await controller.open(id);
      await pumpEventQueue();
      await engine.seek(2, const Duration(seconds: 30));
      engine.finish();
      await pumpEventQueue();
      expect(finished?.id, id);
      expect(repository.byId(id)!.audio!.positionMs, 210000);
      await controller.play();
      expect((engine.index, engine.position), (0, Duration.zero));
    });

    test('learns the exact length of a file from the player', () async {
      await library.setLink(id, const AudioLink(tracks: [
        AudioTrack(location: 'a', name: 'a.mp3'),
        AudioTrack(location: 'b', name: 'b.mp3'),
      ]));
      await controller.open(id);
      await pumpEventQueue();
      expect(library.linkFor(id)!.tracks.first.lengthMs, 60000);
    });

    test('a book without audio, or a file that is gone', () async {
      await library.remove(id);
      expect(await controller.open(id), isNotNull);

      await library.setLink(id, _threeFiles());
      final broken = ListenController(
        repository: repository,
        library: library,
        files: files,
        engine: () => _BrokenEngine(),
      );
      addTearDown(broken.dispose);
      expect(await broken.open(id), contains('moved'));
      expect(broken.active, isFalse);
    });

    test('removing the audio keeps the place and releases the files',
        () async {
      await controller.open(id);
      await pumpEventQueue();
      engine.position = const Duration(seconds: 5);
      await controller.removeAudio(id);
      expect(library.hasAudio(id), isFalse);
      expect(files.released, ['a', 'b', 'c']);
      expect(repository.byId(id)!.audio!.positionMs, 5000);
    });
  });

  test('listening minutes join the day\'s entry in the reading log', () async {
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    await repository.add(title: 'Emma', author: 'J', shelf: Shelf.inProgress);
    final id = repository.books.single.id;
    final day = DateTime(2026, 10, 30, 9);
    await repository.addLogEntry(id, day, 20);
    await repository.addListeningMinutes(id, day, 10);
    await repository.addListeningMinutes(id, day.add(const Duration(hours: 5)), 5);
    await repository.addListeningMinutes(id, DateTime(2026, 10, 31), 7);
    await repository.addListeningMinutes(id, day, 0);
    final log = repository.byId(id)!.readingLog;
    expect([for (final e in log) (e.pages, e.minutes)], [(0, 15), (20, 0), (0, 7)]);
  });
}

class _BrokenEngine extends FakeEngine {
  _BrokenEngine() : super(const []);

  @override
  Future<void> load(
    List<Uri> tracks, {
    required int index,
    required Duration position,
  }) async {
    throw const FileSystemException('gone');
  }
}
