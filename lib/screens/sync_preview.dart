import 'package:flutter/material.dart';

import '../data/pc_sync.dart';
import '../data/sync_plan.dart';

/// Syncs because the user asked (the sync button, Ctrl+S, Settings). With
/// "Show changes before syncing" on, it first shows what will change and
/// only syncs if the user agrees. Shows the result as a message.
Future<void> runManualSync(BuildContext context, PcSync sync) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!sync.settings.reviewSync) {
    final problem = await sync.syncNow();
    messenger.showSnackBar(
      SnackBar(content: Text(problem ?? 'Synced with your phone')),
    );
    return;
  }
  final result = await sync.preview();
  final plan = result.plan;
  if (plan == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(result.problem ?? 'The sync could not start.')),
    );
    return;
  }
  if (plan.isEmpty) {
    sync.recordInSync();
    messenger.showSnackBar(
      const SnackBar(content: Text('Already in sync with your phone')),
    );
    return;
  }
  if (!context.mounted) return;
  final go = await showSyncPreview(context, plan);
  if (go != true) {
    if (sync.pendingReview != null) sync.dismissPending();
    return;
  }
  final problem = await sync.syncNow();
  messenger.showSnackBar(
    SnackBar(content: Text(problem ?? 'Synced with your phone')),
  );
}

/// Shows what a sync will change on this PC and on the phone. Returns true
/// when the user chooses Sync.
Future<bool?> showSyncPreview(BuildContext context, SyncPlan plan) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => _SyncPreviewDialog(plan: plan),
  );
}

class _SyncPreviewDialog extends StatelessWidget {
  const _SyncPreviewDialog({required this.plan});

  final SyncPlan plan;

  @override
  Widget build(BuildContext context) {
    final removals = plan.removals;
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: const Text('Before you sync'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (removals > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'This sync removes $removals '
                    '${removals == 1 ? 'book' : 'books'}. Check that this is '
                    'what you want.',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              TabBar(
                tabs: [
                  Tab(text: 'On this PC (${plan.onPc.length})'),
                  Tab(text: 'On your phone (${plan.onPhone.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ChangeList(
                      changes: plan.onPc,
                      empty: 'Nothing changes on this PC.',
                    ),
                    _ChangeList(
                      changes: plan.onPhone,
                      empty: 'Nothing changes on your phone.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sync'),
          ),
        ],
      ),
    );
  }
}

class _ChangeList extends StatelessWidget {
  const _ChangeList({required this.changes, required this.empty});

  final List<BookChange> changes;
  final String empty;

  IconData _icon(ChangeKind kind) => switch (kind) {
        ChangeKind.added => Icons.add_circle_outline,
        ChangeKind.changed => Icons.edit_outlined,
        ChangeKind.trashed => Icons.delete_outline,
        ChangeKind.restored => Icons.restore_from_trash_outlined,
        ChangeKind.deleted => Icons.delete_forever_outlined,
      };

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) return Center(child: Text(empty));
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: changes.length,
      itemBuilder: (context, index) {
        final change = changes[index];
        final lines = [
          if (change.author.isNotEmpty) change.author,
          change.details.isEmpty
              ? change.kind.label
              : change.details.join(' · '),
        ];
        return ListTile(
          dense: true,
          leading: Icon(
            _icon(change.kind),
            color: change.kind.removes ? scheme.error : null,
          ),
          title: Text(change.title),
          subtitle: Text(lines.join('\n')),
          isThreeLine: lines.length > 1,
        );
      },
    );
  }
}
