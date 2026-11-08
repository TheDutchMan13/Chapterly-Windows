import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';

// Windows app only.

/// A short log of what is slow, kept in the data folder as
/// performance_log.txt and started fresh each time Chapterly opens: how long
/// each step of starting took, frames that took too long to draw, and
/// moments when the app was busy and could not respond. It holds no book
/// details. Used to find out why the app feels slow.
class PerfLog {
  PerfLog._();

  static final _clock = Stopwatch()..start();
  static final _lines = <String>[];
  static final _recent = <String>[];
  static File? _file;
  static Timer? _flushTimer;
  static const _maxLines = 300;
  static int _slowFrames = 0;
  static int _frames = 0;
  static int _stalls = 0;
  static int _worstFrame = 0;
  static int _worstStall = 0;
  static int _changes = 0;
  static int _changesWindowStart = 0;

  static String _stamp() {
    final ms = _clock.elapsedMilliseconds;
    final s = (ms / 1000).toStringAsFixed(2).padLeft(7);
    return '$s s';
  }

  static void _add(String line) {
    if (_lines.length < _maxLines) _lines.add('${_stamp()}  $line');
    _scheduleWrite();
  }

  /// Notes that a step of starting (or other work) is done.
  static void mark(String what) {
    _recent.add(what);
    if (_recent.length > 6) _recent.removeAt(0);
    _add(what);
  }

  /// Runs [work] and notes how long it took when that is long.
  static Future<T> timed<T>(String what, Future<T> Function() work) async {
    final start = _clock.elapsedMilliseconds;
    _recent.add('$what started');
    if (_recent.length > 6) _recent.removeAt(0);
    try {
      return await work();
    } finally {
      final took = _clock.elapsedMilliseconds - start;
      _recent.add('$what finished');
      if (_recent.length > 6) _recent.removeAt(0);
      _add('$what took $took ms');
    }
  }

  /// Notes that the library changed. A burst of changes is logged: each one
  /// redraws the screens.
  static void libraryChanged() {
    final now = _clock.elapsedMilliseconds;
    if (now - _changesWindowStart > 2000) {
      if (_changes >= 15) {
        _add('library changed $_changes times in 2 seconds; '
            'just before: ${_recent.join(' | ')}');
      }
      _changes = 0;
      _changesWindowStart = now;
    }
    _changes++;
  }

  /// Starts writing to [file] (what was noted before is kept).
  static void attach(File file) {
    _file = file;
    _scheduleWrite();
  }

  /// Watches for slow frames and for the app being busy. Call once the
  /// window exists.
  static void watch() {
    WidgetsBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      for (final t in timings) {
        _frames++;
        final total = t.totalSpan.inMilliseconds;
        if (total > _worstFrame) _worstFrame = total;
        if (total > 120) {
          _slowFrames++;
          _add('slow frame: $total ms (building ${t.buildDuration.inMilliseconds}'
              ' ms, drawing ${t.rasterDuration.inMilliseconds} ms)');
        }
      }
    });
    var last = _clock.elapsedMilliseconds;
    Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = _clock.elapsedMilliseconds;
      final late = now - last - 100;
      last = now;
      if (late > 250) {
        _stalls++;
        if (late > _worstStall) _worstStall = late;
        _add('busy for $late ms and could not respond; '
            'just before: ${_recent.join(' | ')}');
      }
    });
  }

  static void _scheduleWrite() {
    if (_file == null || (_flushTimer?.isActive ?? false)) return;
    _flushTimer = Timer(const Duration(seconds: 2), _write);
  }

  static void _write() {
    final file = _file;
    if (file == null) return;
    try {
      final summary = 'Chapterly performance log. Frames: $_frames, '
          'slow: $_slowFrames (worst $_worstFrame ms). '
          'Busy moments: $_stalls (worst $_worstStall ms).';
      file.writeAsStringSync('$summary\n${_lines.join('\n')}\n');
    } catch (_) {
      // The log is only a help: never a problem.
    }
  }
}
