import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_settings.dart';

/// Hides the app behind a PIN screen when a PIN is set: when the app starts,
/// and when it comes back after being away longer than the chosen time.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.settings, required this.child});

  final AppSettings settings;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late bool _locked = widget.settings.pinEnabled;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_settingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_settingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _settingsChanged() {
    if (_locked && !widget.settings.pinEnabled) {
      setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          widget.settings.pinEnabled &&
          DateTime.now().difference(left).inSeconds >=
              widget.settings.lockAfterSeconds) {
        setState(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Visibility(
          visible: !_locked,
          maintainState: true,
          child: widget.child,
        ),
        if (_locked)
          Positioned.fill(
            child: _PinScreen(
              settings: widget.settings,
              onUnlocked: () => setState(() => _locked = false),
            ),
          ),
      ],
    );
  }
}

/// The PIN screen. It uses its own number pad instead of a text field,
/// because it sits above the app's navigator where text fields cannot show
/// their selection handles.
class _PinScreen extends StatefulWidget {
  const _PinScreen({required this.settings, required this.onUnlocked});

  final AppSettings settings;
  final VoidCallback onUnlocked;

  @override
  State<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<_PinScreen> {
  static const _maxTries = 5;
  static const _waitSeconds = 30;
  static const _maxLength = 8;

  Timer? _timer;
  String _entry = '';
  int _failures = 0;
  int _waiting = 0;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _type(String digit) {
    if (_waiting > 0 || _entry.length >= _maxLength) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
  }

  void _erase() {
    if (_waiting > 0 || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _check() {
    if (_waiting > 0 || _entry.isEmpty) return;
    if (widget.settings.checkPin(_entry)) {
      widget.onUnlocked();
      return;
    }
    _failures++;
    if (_failures >= _maxTries) {
      _failures = 0;
      setState(() {
        _entry = '';
        _waiting = _waitSeconds;
        _error = null;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _waiting--);
        if (_waiting <= 0) timer.cancel();
      });
    } else {
      setState(() {
        _entry = '';
        _error = 'Wrong PIN.';
      });
    }
  }

  Widget _digit(String digit) => SizedBox(
        width: 72,
        height: 64,
        child: TextButton(
          onPressed: _waiting > 0 ? null : () => _type(digit),
          child: Text(digit, style: Theme.of(context).textTheme.headlineSmall),
        ),
      );

  Widget _row(List<Widget> keys) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: keys,
      );

  @override
  Widget build(BuildContext context) {
    final message = _waiting > 0
        ? 'Too many tries. Wait $_waiting seconds.'
        : _error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Chapterly is locked',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: Text(
                    '\u2022 ' * _entry.length,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                SizedBox(
                  height: 24,
                  child: Text(
                    message ?? '',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                const SizedBox(height: 8),
                _row([_digit('1'), _digit('2'), _digit('3')]),
                _row([_digit('4'), _digit('5'), _digit('6')]),
                _row([_digit('7'), _digit('8'), _digit('9')]),
                _row([
                  SizedBox(
                    width: 72,
                    height: 64,
                    child: IconButton(
                      icon: const Icon(Icons.backspace_outlined),
                      onPressed: _waiting > 0 ? null : _erase,
                    ),
                  ),
                  _digit('0'),
                  SizedBox(
                    width: 72,
                    height: 64,
                    child: IconButton.filled(
                      icon: const Icon(Icons.check),
                      onPressed: _waiting > 0 ? null : _check,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
