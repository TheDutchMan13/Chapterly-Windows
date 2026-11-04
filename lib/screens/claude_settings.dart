import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/claude_client.dart';

// Windows app only.

/// Your Claude API key and model, for tagging the books Open Library cannot
/// tag. Off until you add a key.
class ClaudeSettings extends StatefulWidget {
  const ClaudeSettings({super.key, required this.settings, this.keyStore});

  final AppSettings settings;

  /// For tests; the open profile's key store otherwise.
  final ClaudeKeyStore? keyStore;

  @override
  State<ClaudeSettings> createState() => _ClaudeSettingsState();
}

class _ClaudeSettingsState extends State<ClaudeSettings> {
  late final ClaudeKeyStore _store = widget.keyStore ?? ClaudeKeyStore.current;
  String? _key;
  bool _loaded = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await _store.read();
    if (!mounted) return;
    setState(() {
      _key = key;
      _loaded = true;
    });
  }

  Future<String?> _ask({
    required String title,
    required String label,
    String initial = '',
    String? helper,
    bool secret = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: secret,
          decoration: InputDecoration(labelText: label, helperText: helper),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _setKey() async {
    final value = await _ask(
      title: 'Claude API key',
      label: 'API key',
      helper: 'From the Claude Console (platform.claude.com). '
          'Kept in Windows\' protected storage.',
      secret: true,
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    await _store.write(value);
    await _load();
  }

  Future<void> _removeKey() async {
    await _store.delete();
    await _load();
  }

  Future<void> _setModel() async {
    final value = await _ask(
      title: 'Claude model',
      label: 'Model',
      initial: widget.settings.claudeModel ?? defaultClaudeModel,
      helper: 'Leave empty for $defaultClaudeModel.',
    );
    if (value == null || !mounted) return;
    widget.settings.setClaudeModel(
      value.trim() == defaultClaudeModel ? null : value,
    );
  }

  Future<void> _test() async {
    final key = _key;
    if (key == null) return;
    setState(() => _testing = true);
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      await ClaudeClient(
        apiKey: key,
        model: widget.settings.claudeModel ?? defaultClaudeModel,
      ).ask(system: 'Reply with the word OK.', prompt: 'Test', maxTokens: 5);
      message = 'Claude answered. The key works.';
    } on ClaudeFailure catch (failure) {
      message = failure.message;
    }
    if (!mounted) return;
    setState(() => _testing = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = _key != null;
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Used only by Tag my library (Tags screen)'),
            subtitle: Text(
              'For the books Open Library cannot tag, Chapterly can ask '
              'Claude. It sends their title, author, Open Library subjects '
              'and your tag names, nothing else. Claude bills your API '
              'account for each question.',
            ),
          ),
          ListTile(
            leading: Icon(hasKey ? Icons.key : Icons.key_off_outlined),
            title: Text(
              !_loaded
                  ? 'API key'
                  : hasKey
                      ? 'API key saved'
                      : 'No API key',
            ),
            subtitle: Text(
              hasKey
                  ? 'Ending in ${_key!.length > 4 ? _key!.substring(_key!.length - 4) : _key}'
                  : 'Add one to use Claude.',
            ),
            trailing: Wrap(
              spacing: 8,
              children: [
                if (hasKey)
                  TextButton(
                    onPressed: _testing ? null : _test,
                    child: Text(_testing ? 'Testing...' : 'Test'),
                  ),
                if (hasKey)
                  TextButton(
                    onPressed: _removeKey,
                    child: const Text('Remove'),
                  ),
                FilledButton.tonal(
                  onPressed: _setKey,
                  child: Text(hasKey ? 'Change' : 'Add key'),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: const Text('Model'),
            subtitle: Text(widget.settings.claudeModel ?? defaultClaudeModel),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _setModel,
          ),
        ],
      ),
    );
  }
}
