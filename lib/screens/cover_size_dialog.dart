import 'package:flutter/material.dart';

import '../data/app_settings.dart';

/// A slider for how big the covers are in the grid view. The grid changes
/// while you drag.
Future<void> showCoverSizeDialog(BuildContext context, AppSettings settings) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cover size'),
      content: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_size_select_small),
                Expanded(
                  child: Slider(
                    value: settings.coverScale,
                    min: AppSettings.minCoverScale,
                    max: AppSettings.maxCoverScale,
                    divisions: 9,
                    label: '${(settings.coverScale * 100).round()}%',
                    onChanged: settings.setCoverScale,
                  ),
                ),
                const Icon(Icons.photo_size_select_large),
              ],
            ),
            Text(
              'For the grid view.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => settings.setCoverScale(1),
          child: const Text('Normal size'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
