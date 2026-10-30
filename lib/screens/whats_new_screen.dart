import 'package:flutter/material.dart';

import '../data/changelog.dart';

/// The changelog: what changed in each version of Chapterly.
class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in changelog) ...[
            Text('Version ${entry.version}', style: textTheme.titleLarge),
            Text(entry.date, style: textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final change in entry.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('\u2022 $change'),
              ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}
