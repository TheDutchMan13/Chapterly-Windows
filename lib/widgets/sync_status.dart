import 'dart:async';

import 'package:flutter/material.dart';

import '../data/pc_sync.dart';
import '../data/sync_plan.dart';
import '../screens/sync_preview.dart';

/// "5 min ago" and the like: short enough for the side menu.
String shortSyncedText(DateTime? at, DateTime now) {
  if (at == null) return 'Not synced';
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return 'Just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours} h ago';
  return '${gap.inDays} d ago';
}

/// The one place that shows how syncing with the phone is going, at the
/// bottom of the side menu. Click it to sync now, or to set up syncing.
class SyncStatusButton extends StatefulWidget {
  const SyncStatusButton({
    super.key,
    required this.pcSync,
    required this.onSetUp,
  });

  final PcSync pcSync;

  /// Opens the sync settings, when the phone is not set up yet.
  final VoidCallback onSetUp;

  @override
  State<SyncStatusButton> createState() => _SyncStatusButtonState();
}

class _SyncStatusButtonState extends State<SyncStatusButton> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps "5 min ago" up to date.
    _tick = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.pcSync;
    return ListenableBuilder(
      listenable: Listenable.merge([sync, sync.settings]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final now = DateTime.now();
        final error = sync.settings.lastSyncError;
        final pending = sync.pendingReview != null;
        final Widget icon;
        final String label;
        final String tooltip;
        Color? colour;
        if (sync.busy) {
          icon = const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
          label = 'Syncing';
          tooltip = 'Syncing with your phone...';
        } else if (!sync.paired) {
          icon = const Icon(Icons.sync_disabled);
          label = 'Set up sync';
          tooltip = 'Set up sync with your phone';
        } else if (pending) {
          colour = scheme.tertiary;
          icon = Icon(Icons.sync_problem, color: colour);
          label = 'Review sync';
          tooltip = 'A sync is waiting for you to look at what it changes';
        } else if (error != null) {
          colour = scheme.error;
          icon = Icon(Icons.sync_problem, color: colour);
          label = 'Not synced';
          tooltip = '$error\nClick to try again (Ctrl+S)';
        } else {
          icon = const Icon(Icons.sync);
          label = shortSyncedText(sync.settings.lastSyncAt, now);
          tooltip = '${syncedAgoText(sync.settings.lastSyncAt, now)}. '
              'Click to sync now (Ctrl+S)';
        }
        return Tooltip(
          message: tooltip,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: sync.busy
                ? null
                : !sync.paired
                    ? widget.onSetUp
                    : () => runManualSync(context, sync),
            child: SizedBox(
              width: 76,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 24, child: Center(child: icon)),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colour ?? scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
