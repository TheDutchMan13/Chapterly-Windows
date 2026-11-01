import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/book.dart';
import 'cover_image.dart';

// Windows app only.

/// What Chapterly learned from a cover picture: a fingerprint of how it
/// looks (a difference hash), its size and how much it varies.
class CoverPrint {
  const CoverPrint({
    required this.hash,
    required this.width,
    required this.height,
    required this.spread,
  });

  /// 64 bits: each says whether a pixel is brighter than the one to its
  /// right, on the picture shrunk to 9 by 8 grey pixels. Pictures that look
  /// the same get nearly the same bits, whatever their size or quality.
  final int hash;
  final int width;
  final int height;

  /// How much the brightness varies (standard deviation, 0 to 255): close
  /// to 0 is a blank picture.
  final double spread;

  Map<String, Object?> toJson() =>
      {'hash': hash, 'width': width, 'height': height, 'spread': spread};

  static CoverPrint? fromJson(Object? value) {
    if (value is! Map) return null;
    final hash = value['hash'];
    final width = value['width'];
    final height = value['height'];
    final spread = value['spread'];
    if (hash is! int || width is! int || height is! int || spread is! num) {
      return null;
    }
    return CoverPrint(
      hash: hash,
      width: width,
      height: height,
      spread: spread.toDouble(),
    );
  }
}

/// The fingerprint of a picture, or null when it is not one.
CoverPrint? printCover(Uint8List bytes) {
  img.Image? picture;
  try {
    picture = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (picture == null) return null;
  final small = img.grayscale(img.copyResize(picture, width: 9, height: 8));
  var hash = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final left = small.getPixel(x, y).r;
      final right = small.getPixel(x + 1, y).r;
      hash = (hash << 1) | (left > right ? 1 : 0);
    }
  }
  final grey = img.grayscale(img.copyResize(picture, width: 32, height: 32));
  var sum = 0.0;
  var squares = 0.0;
  for (final pixel in grey) {
    final v = pixel.r.toDouble();
    sum += v;
    squares += v * v;
  }
  final mean = sum / 1024;
  final spread = math.sqrt(math.max(0, squares / 1024 - mean * mean));
  return CoverPrint(
    hash: hash,
    width: picture.width,
    height: picture.height,
    spread: spread,
  );
}

/// How many of the 64 bits differ: 0 the same picture, up to about 5 the
/// same picture at another size or quality.
int hashDistance(int a, int b) {
  var x = a ^ b;
  var count = 0;
  while (x != 0) {
    x &= x - 1;
    count++;
  }
  return count;
}

/// What looks wrong with a cover picture, or null.
String? coverProblem(CoverPrint print) {
  if (print.width < 60 || print.height < 60) {
    return 'Tiny picture (${print.width}×${print.height})';
  }
  if (print.spread < 6) return 'Blank or nearly one colour';
  if (print.width > print.height * 1.3) return 'Wider than it is tall';
  return null;
}

String _key(String url) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(url)) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return '${hash.toRadixString(16)}-${url.length}';
}

/// Fingerprints of covers already checked, kept in a small file so a second
/// check does not download them again.
class CoverPrints {
  CoverPrints({this.file});

  final File? file;
  final _prints = <String, CoverPrint>{};

  static Future<CoverPrints> load(File file) async {
    final store = CoverPrints(file: file);
    try {
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          for (final entry in data.entries) {
            final print = CoverPrint.fromJson(entry.value);
            if (print != null) store._prints[entry.key.toString()] = print;
          }
        }
      }
    } catch (_) {
      // Start again.
    }
    return store;
  }

  CoverPrint? operator [](String url) => _prints[_key(url)];

  void operator []=(String url, CoverPrint print) => _prints[_key(url)] = print;

  Future<void> save() async {
    final target = file;
    if (target == null) return;
    try {
      await target.parent.create(recursive: true);
      await target.writeAsString(jsonEncode({
        for (final entry in _prints.entries) entry.key: entry.value.toJson(),
      }));
    } catch (_) {
      // Not saved; the next check downloads again.
    }
  }
}

/// Gets the picture behind a cover address: a data: cover from the book, or
/// a download.
Future<Uint8List?> coverBytes(String url, http.Client client) async {
  if (isDataCover(url)) return bytesFromDataCover(url);
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return null;
  }
  try {
    final response = await client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    return response.bodyBytes;
  } catch (_) {
    return null;
  }
}

/// The result of a cover check.
class CoverReport {
  const CoverReport({
    required this.sameCover,
    required this.problems,
    required this.unreadable,
  });

  /// Groups of different books with the same cover picture.
  final List<List<Book>> sameCover;

  /// Books whose cover looks wrong, and why.
  final List<(Book, String)> problems;

  /// Books whose cover could not be downloaded or read.
  final List<Book> unreadable;
}

/// Groups books by cover fingerprint: covers at most [maxDistance] bits
/// apart are the same picture.
List<List<Book>> groupSameCovers(
  List<(Book, CoverPrint)> printed, {
  int maxDistance = 5,
}) {
  final parent = List<int>.generate(printed.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < printed.length; i++) {
    for (var j = i + 1; j < printed.length; j++) {
      // Blank pictures look alike but are reported on their own.
      if (printed[i].$2.spread < 6 || printed[j].$2.spread < 6) continue;
      if (hashDistance(printed[i].$2.hash, printed[j].$2.hash) <= maxDistance) {
        parent[find(j)] = find(i);
      }
    }
  }
  final groups = <int, List<Book>>{};
  for (var i = 0; i < printed.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(printed[i].$1);
  }
  return [
    for (final group in groups.values)
      if (group.length > 1) group,
  ];
}

/// Checks every cover in [books]: fingerprints each one (downloading those
/// not checked before), then finds books sharing a cover and covers that
/// look wrong. [onProgress] gets the number done and the total; stops early
/// when [cancelled] says so.
Future<CoverReport> checkCovers(
  List<Book> books, {
  required CoverPrints prints,
  http.Client? client,
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final httpClient = client ?? http.Client();
  final withCover = [
    for (final book in books)
      if (book.deletedAt == null && (book.coverUrl ?? '').trim().isNotEmpty) book,
  ];
  final printed = <(Book, CoverPrint)>[];
  final unreadable = <Book>[];
  try {
    for (var i = 0; i < withCover.length; i++) {
      if (cancelled?.call() ?? false) break;
      final book = withCover[i];
      final url = book.coverUrl!.trim();
      var print = prints[url];
      if (print == null) {
        final bytes = await coverBytes(url, httpClient);
        print = bytes == null ? null : printCover(bytes);
        if (print != null) prints[url] = print;
      }
      if (print == null) {
        unreadable.add(book);
      } else {
        printed.add((book, print));
      }
      onProgress?.call(i + 1, withCover.length);
    }
  } finally {
    if (client == null) httpClient.close();
    await prints.save();
  }
  return CoverReport(
    sameCover: groupSameCovers(printed),
    problems: [
      for (final (book, print) in printed)
        if (coverProblem(print) case final problem?) (book, problem),
    ],
    unreadable: unreadable,
  );
}
