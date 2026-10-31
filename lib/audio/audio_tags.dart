import 'dart:convert';
import 'dart:typed_data';

import 'audio_probe.dart';

/// The names written inside an audio file.
class AudioTags {
  const AudioTags({
    this.title = '',
    this.album = '',
    this.artist = '',
    this.albumArtist = '',
    this.composer = '',
  });

  final String title;
  final String album;
  final String artist;
  final String albumArtist;
  final String composer;

  /// For an audiobook the album is the book; the title is often only the
  /// chapter (one file per chapter).
  String get bookTitle => album.isNotEmpty ? album : title;

  /// Audiobooks put the author in the artist, sometimes only in the album
  /// artist or the composer.
  String get author => artist.isNotEmpty
      ? artist
      : (albumArtist.isNotEmpty ? albumArtist : composer);

  bool get isEmpty => bookTitle.isEmpty && author.isEmpty;
}

/// Reads the title, album and artist of an M4B/M4A/MP4 file or an MP3
/// (ID3 tags). Never throws: anything it cannot read is left empty.
Future<AudioTags> readAudioTags(ByteSource source) async {
  try {
    final head = await source.read(0, 16);
    if (head.length < 10) return const AudioTags();
    if (_ascii(head, 4, 4) == 'ftyp') return await _mp4Tags(source);
    if (_ascii(head, 0, 3) == 'ID3') {
      final tags = await _id3v2(source, head);
      if (!tags.isEmpty) return tags;
    }
    return await _id3v1(source);
  } catch (_) {
    return const AudioTags();
  }
}

String _ascii(Uint8List b, int o, int n) =>
    o + n <= b.length ? String.fromCharCodes(b.sublist(o, o + n)) : '';

int _u32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

String _clean(String text) =>
    text.replaceAll('\u0000', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

// ---- MP4: moov > udta > meta > ilst > ©nam / ©alb / ©ART / aART / ©wrt

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
      size = (_u32(data, offset + 8) << 32) | _u32(data, offset + 12);
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

_Box? _child(Uint8List data, _Box? parent, String type, {int skip = 0}) {
  if (parent == null) return null;
  for (final box in _boxes(data, parent.start + skip, parent.end)) {
    if (box.type == type) return box;
  }
  return null;
}

Future<AudioTags> _mp4Tags(ByteSource source) async {
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
      boxSize = (_u32(head, 8) << 32) | _u32(head, 12);
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
  if (moov == null) return const AudioTags();
  final root = (type: 'moov', start: 0, end: moov.length);
  final meta = _child(moov, _child(moov, root, 'udta'), 'meta');
  // "meta" normally starts with 4 bytes of version and flags; some
  // QuickTime files leave them out.
  final ilst = _child(moov, meta, 'ilst', skip: 4) ?? _child(moov, meta, 'ilst');
  if (ilst == null) return const AudioTags();
  final values = <String, String>{};
  for (final item in _boxes(moov, ilst.start, ilst.end)) {
    final data = _child(moov, item, 'data');
    // 4 bytes of type, 4 of locale, then the text.
    if (data == null || data.end - data.start <= 8) continue;
    values[item.type] = _clean(utf8.decode(
      moov.sublist(data.start + 8, data.end),
      allowMalformed: true,
    ));
  }
  return AudioTags(
    title: values['©nam'] ?? '',
    album: values['©alb'] ?? '',
    artist: values['©ART'] ?? '',
    albumArtist: values['aART'] ?? '',
    composer: values['©wrt'] ?? '',
  );
}

// ---- MP3: ID3v2 at the start, or ID3v1 in the last 128 bytes

int _syncSafe(Uint8List b, int o) =>
    (b[o] << 21) | (b[o + 1] << 14) | (b[o + 2] << 7) | b[o + 3];

/// Undoes "unsynchronisation": FF 00 was written for every FF.
Uint8List _resync(Uint8List data) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < data.length; i++) {
    out.addByte(data[i]);
    if (data[i] == 0xFF && i + 1 < data.length && data[i + 1] == 0) i++;
  }
  return out.toBytes();
}

Future<AudioTags> _id3v2(ByteSource source, Uint8List head) async {
  final version = head[3];
  if (version < 2 || version > 4) return const AudioTags();
  final flags = head[5];
  // Covers come after the names in nearly every file, so 4 MB is plenty.
  final size = _syncSafe(head, 6).clamp(0, 4 * 1024 * 1024).toInt();
  var tag = await source.read(10, size);
  if (flags & 0x80 != 0 && version < 4) tag = _resync(tag);
  var at = 0;
  if (flags & 0x40 != 0 && version >= 3 && tag.length >= 4) {
    // Skip the extended header.
    at = version == 4 ? _syncSafe(tag, 0) : _u32(tag, 0) + 4;
  }
  final idLength = version == 2 ? 3 : 4;
  final headerLength = version == 2 ? 6 : 10;
  final values = <String, String>{};
  while (at + headerLength <= tag.length) {
    final id = _ascii(tag, at, idLength);
    if (id.codeUnits.any((c) => !((c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39)))) {
      break; // Padding or the end of the frames.
    }
    final int frameSize;
    if (version == 2) {
      frameSize = (tag[at + 3] << 16) | (tag[at + 4] << 8) | tag[at + 5];
    } else if (version == 4) {
      frameSize = _syncSafe(tag, at + 4);
    } else {
      frameSize = _u32(tag, at + 4);
    }
    final start = at + headerLength;
    if (frameSize <= 0 || start + frameSize > tag.length) break;
    if (id.startsWith('T')) {
      values[id] = _id3Text(tag.sublist(start, start + frameSize));
    }
    at = start + frameSize;
  }
  String pick(String v3, String v2) => values[v3] ?? values[v2] ?? '';
  return AudioTags(
    title: pick('TIT2', 'TT2'),
    album: pick('TALB', 'TAL'),
    artist: pick('TPE1', 'TP1'),
    albumArtist: pick('TPE2', 'TP2'),
    composer: pick('TCOM', 'TCM'),
  );
}

/// A text frame: one byte for the encoding, then the text. Only the first
/// of several values (ID3v2.4 separates them with a zero) is kept.
String _id3Text(Uint8List frame) {
  if (frame.isEmpty) return '';
  final encoding = frame[0];
  final body = frame.sublist(1);
  String text;
  switch (encoding) {
    case 1:
    case 2:
      var bigEndian = encoding == 2;
      var start = 0;
      if (body.length >= 2 && body[0] == 0xFF && body[1] == 0xFE) {
        bigEndian = false;
        start = 2;
      } else if (body.length >= 2 && body[0] == 0xFE && body[1] == 0xFF) {
        bigEndian = true;
        start = 2;
      }
      final units = <int>[];
      for (var i = start; i + 1 < body.length; i += 2) {
        final unit = bigEndian
            ? (body[i] << 8) | body[i + 1]
            : body[i] | (body[i + 1] << 8);
        if (unit == 0) break;
        units.add(unit);
      }
      text = String.fromCharCodes(units);
    case 3:
      final end = body.indexOf(0);
      text = utf8.decode(end < 0 ? body : body.sublist(0, end),
          allowMalformed: true);
    default:
      final end = body.indexOf(0);
      text = latin1.decode(end < 0 ? body : body.sublist(0, end));
  }
  return _clean(text);
}

Future<AudioTags> _id3v1(ByteSource source) async {
  final size = await source.length();
  if (size < 128) return const AudioTags();
  final tag = await source.read(size - 128, 128);
  if (tag.length < 128 || _ascii(tag, 0, 3) != 'TAG') return const AudioTags();
  String field(int offset) {
    final bytes = tag.sublist(offset, offset + 30);
    final end = bytes.indexOf(0);
    return _clean(latin1.decode(end < 0 ? bytes : bytes.sublist(0, end)));
  }

  return AudioTags(title: field(3), artist: field(33), album: field(63));
}
