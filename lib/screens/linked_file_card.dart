import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/linked_files.dart';
import '../models/book.dart';

Future<String?> _pickAnyFile() async => (await openFile())?.path;

Future<String?> _pickAnyFolder() => getDirectoryPath();

Future<bool> _openWithWindows(String path) =>
    launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);

Future<void> _showInExplorer(String path) async {
  final isFolder = linkedKindOf(path) == LinkedKind.folder;
  await Process.run('explorer.exe', [if (!isFolder) '/select,', path]);
}

/// A file or folder on this PC linked to the book without copying it: any
/// kind of file, left where it is, and opened with the program Windows uses
/// for it. Hidden when the links are not set up (tests).
class LinkedFileCard extends StatelessWidget {
  const LinkedFileCard({
    super.key,
    required this.book,
    this.links,
    this.pickFile = _pickAnyFile,
    this.pickFolder = _pickAnyFolder,
    this.open = _openWithWindows,
    this.showInExplorer = _showInExplorer,
  });

  final Book book;

  /// The links to use; the app's own when null.
  final LinkedFiles? links;

  final Future<String?> Function() pickFile;
  final Future<String?> Function() pickFolder;
  final Future<bool> Function(String path) open;
  final Future<void> Function(String path) showInExplorer;

  Future<void> _link(LinkedFiles links, Future<String?> Function() pick) async {
    final path = await pick();
    if (path != null && path.isNotEmpty) await links.link(book.id, path);
  }

  Future<void> _open(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await open(path);
    } on Object {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Windows could not open it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = this.links ?? LinkedFiles.shared;
    if (links == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: links,
      builder: (context, _) {
        final path = links.pathFor(book.id);
        final kind = path == null ? null : linkedKindOf(path);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_open_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('On your drive', style: textTheme.titleMedium),
                    ),
                    if (path != null)
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        onSelected: (choice) {
                          switch (choice) {
                            case 'file':
                              _link(links, pickFile);
                            case 'folder':
                              _link(links, pickFolder);
                            case 'remove':
                              links.unlink(book.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'file',
                            child: Text('Link another file...'),
                          ),
                          PopupMenuItem(
                            value: 'folder',
                            child: Text('Link a folder...'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove the link'),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (path == null) ...[
                  const Text(
                    'Link the book where it already is on this PC, such as an '
                    'EPUB, MOBI, PDF or a folder of audio files. Nothing is '
                    'copied; Windows opens it with its usual program.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _link(links, pickFile),
                        icon: const Icon(Icons.insert_drive_file_outlined),
                        label: const Text('Link a file'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _link(links, pickFolder),
                        icon: const Icon(Icons.folder_outlined),
                        label: const Text('Link a folder'),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    linkedName(path),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: colours.onSurfaceVariant),
                  ),
                  if (kind == LinkedKind.missing)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Not found. The file was moved, renamed or its drive '
                        'is not connected.',
                        style: textTheme.bodySmall
                            ?.copyWith(color: colours.error),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: kind == LinkedKind.missing
                            ? null
                            : () => _open(context, path),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open'),
                      ),
                      if (kind != LinkedKind.missing)
                        TextButton(
                          onPressed: () => showInExplorer(path),
                          child: const Text('Show in folder'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
