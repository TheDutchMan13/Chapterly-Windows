import 'package:flutter/material.dart';

import '../data/profiles.dart';

/// A profile's coloured circle with its first letter.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, this.radius = 20});

  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(profile.color),
      foregroundColor: Colors.white,
      child: Text(
        profile.initial,
        style: TextStyle(fontSize: radius * 0.9, fontWeight: FontWeight.w600),
      ),
    );
  }
}

enum _ProfileAction { rename, colour, delete }

/// The profiles on this device: open another one, add one, rename, change
/// the colour or delete.
class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key, required this.store});

  final ProfileStore store;

  Future<void> _open(BuildContext context, Profile profile) async {
    if (ProfileSwitching.switchRestarts) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Open ${profile.name}?'),
          content: const Text('Chapterly closes and opens again with this '
              'profile.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    await ProfileSwitching.switchTo?.call(profile.id);
  }

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    required String action,
    String initial = '',
    String? exceptId,
  }) {
    final controller = TextEditingController(text: initial);
    String? problem;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) {
          void submit() {
            final found =
                store.nameProblem(controller.text, exceptId: exceptId);
            if (found != null) {
              setState(() => problem = found);
              return;
            }
            Navigator.of(dialogContext).pop(controller.text.trim());
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Name', errorText: problem),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: Text(action)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final name = await _askName(context, title: 'New profile', action: 'Add');
    if (name == null) return;
    final profile = await store.add(name);
    if (!context.mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Open ${profile.name} now?'),
        content: const Text('A new profile starts with an empty library. '
            'Its PIN, PC sync and other settings are set in its own '
            'Settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (open == true) await ProfileSwitching.switchTo?.call(profile.id);
  }

  Future<void> _rename(BuildContext context, Profile profile) async {
    final name = await _askName(
      context,
      title: 'Rename profile',
      action: 'Rename',
      initial: profile.name,
      exceptId: profile.id,
    );
    if (name != null) await store.rename(profile.id, name);
  }

  Future<void> _colour(BuildContext context, Profile profile) async {
    final colour = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Colour'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, value) in profileColors.indexed)
              IconButton.filled(
                tooltip: 'Colour ${index + 1}',
                style: IconButton.styleFrom(
                  backgroundColor: Color(value),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 48),
                ),
                icon: Icon(
                  value == profile.color ? Icons.check : Icons.circle,
                  color: value == profile.color ? Colors.white : Color(value),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(value),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (colour != null) await store.setColor(profile.id, colour);
  }

  Future<String?> _askPin(BuildContext context, Profile profile) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("${profile.name}'s PIN"),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, Profile profile) async {
    if (store.hasPin(profile.id)) {
      final pin = await _askPin(context, profile);
      if (pin == null || !context.mounted) return;
      if (!store.checkPin(profile.id, pin)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Wrong PIN.')));
        return;
      }
    }
    if (!context.mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${profile.name}?'),
        content: const Text('Its books, notes, statistics, settings and its '
            'lists of book files and audiobooks and its book server '
            'connection are removed from this device. Its automatic '
            'backups are kept. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await store.remove(profile.id);
    await ProfileSwitching.removeFiles?.call(profile.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Deleted ${profile.name}.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add a profile'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final active = store.active;
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Each profile has its own books, shelves, '
                    'statistics, goals, settings, phone sync, book server '
                    'connection and PIN. Tap a profile to open it.'),
              ),
              for (final profile in store.profiles)
                _tile(context, profile, isOpen: profile.id == active.id),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, Profile profile, {required bool isOpen}) {
    final notes = [
      if (isOpen) 'Open now',
      if (store.hasPin(profile.id)) 'PIN',
    ];
    return ListTile(
      leading: ProfileAvatar(profile: profile),
      title: Text(profile.name),
      subtitle: notes.isEmpty ? null : Text(notes.join(' · ')),
      selected: isOpen,
      onTap: isOpen ? null : () => _open(context, profile),
      trailing: PopupMenuButton<_ProfileAction>(
        tooltip: 'More for ${profile.name}',
        onSelected: (action) => switch (action) {
          _ProfileAction.rename => _rename(context, profile),
          _ProfileAction.colour => _colour(context, profile),
          _ProfileAction.delete => _delete(context, profile),
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: _ProfileAction.rename,
            child: Text('Rename'),
          ),
          const PopupMenuItem(
            value: _ProfileAction.colour,
            child: Text('Colour'),
          ),
          if (!isOpen)
            const PopupMenuItem(
              value: _ProfileAction.delete,
              child: Text('Delete'),
            ),
        ],
      ),
    );
  }
}
