import 'package:flutter/material.dart';

import '../audio/audio_files.dart';
import '../audio/audio_library.dart';
import '../audio/listening.dart';
import '../data/book_repository.dart';
import '../models/audio_progress.dart';
import '../models/book.dart';
import '../models/book_format.dart';
import 'now_playing.dart';

/// "4 h 5 min of 11 h 40 min · 35%" and the like.
String describeAudioProgress(AudioProgress? progress, AudioLink? link) {
  if (progress == null || progress.positionMs <= 0) {
    final length = link?.lengthMs;
    return length == null
        ? 'Not started'
        : 'Not started · ${formatListenTime(length)}';
  }
  final length = link?.lengthMs ?? progress.lengthMs;
  if (length == null || length <= 0) {
    return '${formatListenTime(progress.positionMs)} listened';
  }
  final percent = (progress.positionMs * 100 / length).clamp(0, 100).round();
  return '${formatListenTime(progress.positionMs)} of '
      '${formatListenTime(length)} · $percent%';
}

/// The audiobook part of a book's page: add the audio from this device,
/// then play it and see how far you are.
class ListenCard extends StatefulWidget {
  const ListenCard({super.key, required this.book, required this.repository});

  final Book book;
  final BookRepository repository;

  @override
  State<ListenCard> createState() => _ListenCardState();
}

class _ListenCardState extends State<ListenCard> {
  bool _adding = false;

  Future<void> _add({required bool folder}) async {
    final controller = Listening.controller;
    final files = Listening.files;
    if (controller == null || files == null) return;
    final messenger = ScaffoldMessenger.of(context);
    List<PickedFile>? picked;
    try {
      picked = folder ? await files.pickFolder() : await files.pickFile();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the file picker.')),
      );
      return;
    }
    if (picked == null || !mounted) return;
    setState(() => _adding = true);
    try {
      final link = await buildAudioLink(files, picked);
      if (link == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              folder
                  ? 'There are no audio files in that folder.'
                  : 'That is not an audio file Chapterly can play.',
            ),
          ),
        );
        return;
      }
      final book = widget.book;
      final old = controller.library.linkFor(book.id);
      if (old != null) {
        if (controller.bookId == book.id) await controller.close();
        final kept = {for (final t in link.tracks) t.location};
        await files.release([
          for (final t in old.tracks)
            if (!kept.contains(t.location)) t.location,
        ]);
      }
      await controller.library.setLink(book.id, link);
      if (book.format == null) {
        await widget.repository.setFormat(book.id, BookFormat.audiobook);
      }
      final count = link.tracks.length;
      final chapters = link.allChapters.length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Added the audiobook'
                    '${chapters > 0 ? ' with $chapters chapters' : ''}'
                : 'Added $count audio files',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove() async {
    final controller = Listening.controller;
    if (controller == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove the audio?'),
        content: const Text(
          'Chapterly forgets the audio files for this book on this device. '
          'The files themselves are not deleted, and where you are in the '
          'book is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure == true) await controller.removeAudio(widget.book.id);
  }

  Future<void> _restart() async {
    final controller = Listening.controller;
    if (controller == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start from the beginning?'),
        content: const Text(
          'The audiobook goes back to the start and begins playing. Where '
          'you are now is not kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final problem = await controller.restart(widget.book.id);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _listen() async {
    final controller = Listening.controller;
    if (controller == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (controller.bookId == widget.book.id) {
      await controller.toggle();
      return;
    }
    final problem = await controller.open(widget.book.id);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Widget _addButtons() {
    if (_adding) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Reading the audio files...'),
          ],
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => _add(folder: false),
          icon: const Icon(Icons.audio_file_outlined),
          label: const Text('Add an audio file'),
        ),
        OutlinedButton.icon(
          onPressed: () => _add(folder: true),
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Add a folder'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Listening.controller;
    if (controller == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.library]),
      builder: (context, _) {
        final book = widget.book;
        final link = controller.library.linkFor(book.id);
        final current = controller.bookId == book.id;
        final progress = current ? controller.progress : book.audio;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.headphones_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Audiobook', style: textTheme.titleMedium),
                    ),
                    if (link != null)
                      PopupMenuButton<VoidCallback>(
                        tooltip: 'More',
                        onSelected: (action) => action(),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: () => _add(folder: false),
                            child: const Text('Use another file...'),
                          ),
                          PopupMenuItem(
                            value: () => _add(folder: true),
                            child: const Text('Use another folder...'),
                          ),
                          PopupMenuItem(
                            value: _remove,
                            child: const Text('Remove the audio'),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (link == null) ...[
                  Text(
                    book.audio != null && book.audio!.positionMs > 0
                        ? '${describeAudioProgress(book.audio, null)} on '
                            'another device. Add the audio on this device to '
                            'carry on here.'
                        : 'Listen to this book here: add the audiobook from '
                            'this device, as one file (such as .m4b or .mp3) '
                            'or a folder of files.',
                  ),
                  const SizedBox(height: 8),
                  _addButtons(),
                ] else ...[
                  Text(describeAudioProgress(progress, link)),
                  if (progress?.fraction case final fraction?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: LinearProgressIndicator(value: fraction),
                    ),
                  if (link.allChapters.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${link.allChapters.length} chapters',
                        style: textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (_adding)
                    _addButtons()
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _listen,
                          icon: Icon(
                            current && controller.playing
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            current && controller.playing
                                ? 'Pause'
                                : (progress?.positionMs ?? 0) > 0
                                    ? 'Resume'
                                    : 'Listen',
                          ),
                        ),
                        if (current || (progress?.positionMs ?? 0) > 0)
                          OutlinedButton.icon(
                            onPressed: _restart,
                            icon: const Icon(Icons.replay),
                            label: const Text('Restart'),
                          ),
                        if (current)
                          OutlinedButton.icon(
                            onPressed: () => openPlayer(context),
                            icon: const Icon(Icons.open_in_full),
                            label: const Text('Player'),
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
