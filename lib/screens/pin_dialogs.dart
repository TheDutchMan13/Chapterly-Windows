import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_settings.dart';

/// Asks for a new PIN twice. Returns it, or null if cancelled.
Future<String?> askNewPin(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _NewPinDialog(),
  );
}

/// Asks for the current PIN. Returns true only if it was right.
Future<bool> confirmCurrentPin(BuildContext context, AppSettings settings) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _CurrentPinDialog(settings: settings),
  );
  return ok ?? false;
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog();

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _pin.text;
    if (pin.length < 4) {
      setState(() => _error = 'Use 4 to 8 digits.');
    } else if (pin != _again.text) {
      setState(() => _error = 'The two PINs do not match.');
    } else {
      Navigator.of(context).pop(pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose a PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'PIN'),
          ),
          TextField(
            controller: _again,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'PIN again',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _CurrentPinDialog extends StatefulWidget {
  const _CurrentPinDialog({required this.settings});

  final AppSettings settings;

  @override
  State<_CurrentPinDialog> createState() => _CurrentPinDialogState();
}

class _CurrentPinDialogState extends State<_CurrentPinDialog> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _check() {
    if (widget.settings.checkPin(_pin.text)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'Wrong PIN.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter your PIN'),
      content: TextField(
        controller: _pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 8,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: 'PIN', errorText: _error),
        onSubmitted: (_) => _check(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _check, child: const Text('OK')),
      ],
    );
  }
}
