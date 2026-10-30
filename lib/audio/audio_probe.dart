import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Reads bytes from an audio file: a file on Windows, a content:// address
/// on Android (through the app's own code), or memory in tests.
abstract interface class ByteSource {
  Future<int> length();

  /// Up to [count] bytes from [offset]. Fewer at the end of the file.
  Future<Uint8List> read(int offset, int count);

  Future<void> close();
}

class MemoryByteSource implements ByteSource {
  MemoryByteSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset >= bytes.length || offset < 0) return Uint8List(0);
    final end = offset + count > bytes.length ? bytes.length : offset + count;
    return Uint8List.sublistView(bytes, offset, end);
  }

  @override
  Future<void> close() async {}
}

/// A file on disk.
class FileByteSource implements ByteSource {
  FileByteSource(this.path);

  final String path;
  RandomAccessFile? _file;

  Future<RandomAccessFile> _open() async =>
      _file ??= await File(path).open();

  @override
  Future<int> length() async => (await _open()).length();

  @override
  Future<Uint8List> read(int offset, int count) async {
    final file = await _open();
    await file.setPosition(offset);
    return file.read(count);
  }

  @override
  Future<void> close() async {
    await _file?.close();
    _file = null;
  }
}

/// A chapter found inside a file.
class FoundChapter {
  const FoundChapter(this.title, this.startMs);

  final String title;
  final int startMs;
}

/// What could be read from an audio file without playing it.
class AudioInfo {
  const AudioInfo({this.lengthMs, this.chapters = const []});

  final int? lengthMs;
  final List<FoundChapter> chapters;
}

int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

int _u32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _u64(Uint8List b, int o) => (_u32(b, o) << 32) | _u32(b, o + 4);

int _u16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

int _u32le(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

int _u64le(Uint8List b, int o) => _u32le(b, o) | (_u32le(b, o + 4) << 32);

String _ascii(Uint8List b, int o, int n) =>
    o + n <= b.length ? String.fromCharCodes(b.sublist(o, o + n)) : '';

/// Reads the length and chapters of an audio file. Never throws: anything it
/// cannot read is left out (the player then finds the length itself).
Future<AudioInfo> probeAudio(ByteSource source) async {
  try {
    final head = await source.read(0, 64);
    if (head.length < 12) return const AudioInfo();
    if (_ascii(head, 4, 4) == 'ftyp') return await _probeMp4(source);
    if (_ascii(head, 0, 4) == 'fLaC') return await _probeFlac(source);
    if (_ascii(head, 0, 4) == 'OggS') return await _probeOgg(source);
    if (_ascii(head, 0, 4) == 'RIFF' && _ascii(head, 8, 4) == 'WAVE') {
      return await _probeWav(source);
    }
    return await _probeMp3(source);
  } catch (_) {
    return const AudioInfo();
  }
}

// ---- MP4, M4A, M4B

/// One box inside [data]: its type and where its contents are.
typedef _Box = ({String type, int start, int end});

List<_Box> _boxes(Uint8List data, int start, int end) {
  final boxes = <_Box>[];
  var offset = start;
  while (offset + 8 <= end) {
    var size = _u32(data, offset);
    final type = _ascii(data, offset + 4, 4);
    var header = 8;
    if (size == 1) {
      if (offset + 16 > end) break;
      size = _u64(data, offset + 8);
      header = 16;
    } else if (size == 0) {
      size = end - offset;
    }
    if (size < header || offset + size > end) break;
    boxes.add((type: type, start: offset + header, end: offset + size));
    offset += size;
  }
  return boxes;
}

_Box? _child(Uint8List data, _Box parent, String type) {
  for (final box in _boxes(data, parent.start, parent.end)) {
    if (box.type == type) return box;
  }
  return null;
}

_Box? _path(Uint8List data, _Box parent, List<String> types) {
  _Box? box = parent;
  for (final type in types) {
    if (box == null) return null;
    box = _child(data, box, type);
  }
  return box;
}

/// Timescale and duration from an mvhd or mdhd box.
({int timescale, int duration}) _timing(Uint8List data, _Box box) {
  final version = data[box.start];
  if (version == 1) {
    return (
      timescale: _u32(data, box.start + 20),
      duration: _u64(data, box.start + 24),
    );
  }
  return (
    timescale: _u32(data, box.start + 12),
    duration: _u32(data, box.start + 16),
  );
}

Future<AudioInfo> _probeMp4(ByteSource source) async {
  final size = await source.length();
  Uint8List? moov;
  var offset = 0;
  while (offset + 8 <= size) {
    final head = await source.read(offset, 16);
    if (head.length < 8) break;
    var boxSize = _u32(head, 0);
    final type = _ascii(head, 4, 4);
    var header = 8;
    if (boxSize == 1) {
      if (head.length < 16) break;
      boxSize = _u64(head, 8);
      header = 16;
    } else if (boxSize == 0) {
      boxSize = size - offset;
    }
    if (boxSize < header) break;
    if (type == 'moov') {
      if (boxSize > 64 * 1024 * 1024) break;
      moov = await source.read(offset + header, boxSize - header);
      break;
    }
    offset += boxSize;
  }
  if (moov == null) return const AudioInfo();
  final root = (type: 'moov', start: 0, end: moov.length);

  int? lengthMs;
  final mvhd = _child(moov, root, 'mvhd');
  if (mvhd != null) {
    final timing = _timing(moov, mvhd);
    if (timing.timescale > 0) {
      lengthMs = timing.duration * 1000 ~/ timing.timescale;
    }
  }

  var chapters = await _quickTimeChapters(source, moov, root);
  if (chapters.isEmpty) chapters = _neroChapters(moov, root);
  return AudioInfo(lengthMs: lengthMs, chapters: chapters);
}

/// Chapters written as a "chpl" box (Nero style), times in 100 ns units.
List<FoundChapter> _neroChapters(Uint8List data, _Box root) {
  final chpl = _path(data, root, ['udta', 'chpl']);
  if (chpl == null) return const [];
  var at = chpl.start;
  final version = data[at];
  at += 4;
  if (version != 0) at += 4;
  if (at >= chpl.end) return const [];
  final count = data[at++];
  final chapters = <FoundChapter>[];
  for (var i = 0; i < count && at + 9 <= chpl.end; i++) {
    final start = _u64(data, at);
    final length = data[at + 8];
    at += 9;
    if (at + length > chpl.end) break;
    final title = utf8.decode(data.sublist(at, at + length), allowMalformed: true);
    at += length;
    chapters.add(FoundChapter(title.trim(), start ~/ 10000));
  }
  return chapters;
}

/// Chapters written as a text track that the audio track points to (the way
/// iTunes and most audiobook tools do it).
Future<List<FoundChapter>> _quickTimeChapters(
  ByteSource source,
  Uint8List moov,
  _Box root,
) async {
  final traks = [
    for (final box in _boxes(moov, root.start, root.end))
      if (box.type == 'trak') box,
  ];
  final chapterIds = <int>{};
  final byId = <int, _Box>{};
  for (final trak in traks) {
    final tkhd = _child(moov, trak, 'tkhd');
    if (tkhd == null) continue;
    final id = moov[tkhd.start] == 1
        ? _u32(moov, tkhd.start + 20)
        : _u32(moov, tkhd.start + 12);
    byId[id] = trak;
    final chap = _path(moov, trak, ['tref', 'chap']);
    if (chap != null) {
      for (var at = chap.start; at + 4 <= chap.end; at += 4) {
        chapterIds.add(_u32(moov, at));
      }
    }
  }
  for (final id in chapterIds) {
    final trak = byId[id];
    if (trak == null) continue;
    final chapters = await _readTextTrack(source, moov, trak);
    if (chapters.isNotEmpty) return chapters;
  }
  return const [];
}

Future<List<FoundChapter>> _readTextTrack(
  ByteSource source,
  Uint8List data,
  _Box trak,
) async {
  final mdhd = _path(data, trak, ['mdia', 'mdhd']);
  final stbl = _path(data, trak, ['mdia', 'minf', 'stbl']);
  if (mdhd == null || stbl == null) return const [];
  final timescale = _timing(data, mdhd).timescale;
  if (timescale <= 0) return const [];
  final stts = _child(data, stbl, 'stts');
  final stsz = _child(data, stbl, 'stsz');
  final stsc = _child(data, stbl, 'stsc');
  final stco = _child(data, stbl, 'stco');
  final co64 = _child(data, stbl, 'co64');
  if (stts == null || stsz == null || stsc == null) return const [];
  if (stco == null && co64 == null) return const [];

  // Start time of each sample.
  final starts = <int>[];
  var time = 0;
  final timeEntries = _u32(data, stts.start + 4);
  for (var i = 0; i < timeEntries; i++) {
    final at = stts.start + 8 + i * 8;
    if (at + 8 > stts.end) break;
    final count = _u32(data, at);
    final delta = _u32(data, at + 4);
    for (var j = 0; j < count && starts.length < 5000; j++) {
      starts.add(time);
      time += delta;
    }
  }

  // Size of each sample.
  final uniform = _u32(data, stsz.start + 4);
  final sampleCount = _u32(data, stsz.start + 8);
  final sizes = <int>[
    for (var i = 0; i < sampleCount && i < 5000; i++)
      uniform != 0 ? uniform : _u32(data, stsz.start + 12 + i * 4),
  ];

  // Where each chunk starts, and how many samples each chunk has.
  final chunkOffsets = <int>[];
  if (co64 != null) {
    final count = _u32(data, co64.start + 4);
    for (var i = 0; i < count; i++) {
      chunkOffsets.add(_u64(data, co64.start + 8 + i * 8));
    }
  } else {
    final count = _u32(data, stco!.start + 4);
    for (var i = 0; i < count; i++) {
      chunkOffsets.add(_u32(data, stco.start + 8 + i * 4));
    }
  }
  final runs = <({int firstChunk, int perChunk})>[];
  final runCount = _u32(data, stsc.start + 4);
  for (var i = 0; i < runCount; i++) {
    final at = stsc.start + 8 + i * 12;
    if (at + 12 > stsc.end) break;
    runs.add((firstChunk: _u32(data, at), perChunk: _u32(data, at + 4)));
  }
  if (runs.isEmpty) return const [];

  final offsets = <int>[];
  var sample = 0;
  for (var chunk = 1; chunk <= chunkOffsets.length; chunk++) {
    var perChunk = runs.first.perChunk;
    for (final run in runs) {
      if (run.firstChunk <= chunk) perChunk = run.perChunk;
    }
    var at = chunkOffsets[chunk - 1];
    for (var i = 0; i < perChunk && sample < sizes.length; i++) {
      offsets.add(at);
      at += sizes[sample];
      sample++;
    }
  }

  final chapters = <FoundChapter>[];
  final count = [starts.length, offsets.length, sizes.length]
      .reduce((a, b) => a < b ? a : b);
  for (var i = 0; i < count; i++) {
    final bytes = await source.read(offsets[i], sizes[i]);
    if (bytes.length < 2) continue;
    final length = _u16(bytes, 0);
    final end = 2 + length > bytes.length ? bytes.length : 2 + length;
    final text = bytes.sublist(2, end);
    String title;
    if (text.length >= 2 && text[0] == 0xFE && text[1] == 0xFF) {
      final units = [
        for (var j = 2; j + 1 < text.length; j += 2) (text[j] << 8) | text[j + 1],
      ];
      title = String.fromCharCodes(units);
    } else {
      title = utf8.decode(text, allowMalformed: true);
    }
    chapters.add(FoundChapter(title.trim(), starts[i] * 1000 ~/ timescale));
  }
  return chapters;
}

// ---- MP3

const _mpeg1Layer3 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
const _mpeg2Layer3 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
const _rates = [44100, 48000, 32000];

Future<AudioInfo> _probeMp3(ByteSource source) async {
  final size = await source.length();
  var start = 0;
  final id3 = await source.read(0, 10);
  if (_ascii(id3, 0, 3) == 'ID3' && id3.length == 10) {
    final tagSize = ((id3[6] & 0x7F) << 21) |
        ((id3[7] & 0x7F) << 14) |
        ((id3[8] & 0x7F) << 7) |
        (id3[9] & 0x7F);
    start = 10 + tagSize + ((id3[5] & 0x10) != 0 ? 10 : 0);
  }
  final window = await source.read(start, 65536);
  for (var i = 0; i + 4 <= window.length; i++) {
    if (window[i] != 0xFF || (window[i + 1] & 0xE0) != 0xE0) continue;
    final b1 = window[i + 1];
    final b2 = window[i + 2];
    final b3 = window[i + 3];
    final versionBits = (b1 >> 3) & 3; // 0: 2.5, 2: 2, 3: 1
    final layerBits = (b1 >> 1) & 3; // 1: layer 3
    final bitrateIndex = b2 >> 4;
    final rateIndex = (b2 >> 2) & 3;
    // An AAC file (ADTS) also starts with a sync word: not an MP3.
    if (i == 0 && layerBits == 0) return const AudioInfo();
    if (versionBits == 1 || layerBits != 1) continue;
    if (bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) continue;
    final mpeg1 = versionBits == 3;
    final rate = _rates[rateIndex] ~/ (mpeg1 ? 1 : (versionBits == 2 ? 2 : 4));
    final samplesPerFrame = mpeg1 ? 1152 : 576;
    final mono = (b3 >> 6) == 3;
    final frameStart = start + i;

    final xingAt = i + 4 + (mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17));
    final tag = _ascii(window, xingAt, 4);
    if ((tag == 'Xing' || tag == 'Info') && xingAt + 12 <= window.length) {
      final flags = _u32(window, xingAt + 4);
      if ((flags & 1) != 0) {
        final frames = _u32(window, xingAt + 8);
        return AudioInfo(lengthMs: frames * samplesPerFrame * 1000 ~/ rate);
      }
    }
    final vbriAt = i + 4 + 32;
    if (_ascii(window, vbriAt, 4) == 'VBRI' && vbriAt + 18 <= window.length) {
      final frames = _u32(window, vbriAt + 14);
      return AudioInfo(lengthMs: frames * samplesPerFrame * 1000 ~/ rate);
    }

    // Constant bit rate: work it out from the file size.
    final kbps = (mpeg1 ? _mpeg1Layer3 : _mpeg2Layer3)[bitrateIndex];
    var audioBytes = size - frameStart;
    final tail = await source.read(size - 128, 3);
    if (_ascii(tail, 0, 3) == 'TAG') audioBytes -= 128;
    return AudioInfo(lengthMs: audioBytes * 8 ~/ kbps);
  }
  return const AudioInfo();
}

// ---- FLAC

Future<AudioInfo> _probeFlac(ByteSource source) async {
  final b = await source.read(0, 42);
  if (b.length < 26 || (b[4] & 0x7F) != 0) return const AudioInfo();
  const d = 8; // STREAMINFO data
  final rate = (b[d + 10] << 12) | (b[d + 11] << 4) | (b[d + 12] >> 4);
  final samples = ((b[d + 13] & 0x0F) << 32) | _u32(b, d + 14);
  if (rate <= 0 || samples <= 0) return const AudioInfo();
  return AudioInfo(lengthMs: samples * 1000 ~/ rate);
}

// ---- Ogg Vorbis and Opus

Future<AudioInfo> _probeOgg(ByteSource source) async {
  final first = await source.read(0, 512);
  if (first.length < 28) return const AudioInfo();
  final packet = 27 + first[26];
  int rate;
  var preSkip = 0;
  if (_ascii(first, packet, 7) == '\u0001vorbis') {
    rate = _u32le(first, packet + 12);
  } else if (_ascii(first, packet, 8) == 'OpusHead') {
    rate = 48000;
    preSkip = _u16le(first, packet + 10);
  } else {
    return const AudioInfo();
  }
  final size = await source.length();
  final from = size > 65536 ? size - 65536 : 0;
  final tail = await source.read(from, size - from);
  for (var i = tail.length - 14; i >= 0; i--) {
    if (tail[i] == 0x4F &&
        tail[i + 1] == 0x67 &&
        tail[i + 2] == 0x67 &&
        tail[i + 3] == 0x53) {
      final granule = _u64le(tail, i + 6);
      if (granule <= 0 || rate <= 0) return const AudioInfo();
      return AudioInfo(lengthMs: (granule - preSkip) * 1000 ~/ rate);
    }
  }
  return const AudioInfo();
}

// ---- WAV

Future<AudioInfo> _probeWav(ByteSource source) async {
  final size = await source.length();
  var offset = 12;
  int? byteRate;
  while (offset + 8 <= size) {
    final header = await source.read(offset, 16);
    if (header.length < 8) break;
    final id = _ascii(header, 0, 4);
    final chunkSize = _u32le(header, 4);
    if (id == 'fmt ') {
      final fmt = await source.read(offset + 8, 16);
      if (fmt.length >= 12) byteRate = _u32le(fmt, 8);
    }
    if (id == 'data') {
      final rate = byteRate;
      if (rate == null || rate <= 0) return const AudioInfo();
      return AudioInfo(lengthMs: chunkSize * 1000 ~/ rate);
    }
    offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }
  return const AudioInfo();
}
