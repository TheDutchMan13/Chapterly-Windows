import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../audio/listening.dart';
import '../data/update_check.dart';
import '../data/update_install.dart';

// Windows app only.

/// "Chapterly 1.10.0 is available": install it from inside Chapterly
/// (download, then the installer replaces this version and opens the new
/// one), or see the release on GitHub.
Future<void> showUpdateDialog(BuildContext context, AvailableUpdate update) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(update: update),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});

  final AvailableUpdate update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  bool _cancelled = false;
  double? _progress;
  String? _problem;

  Future<void> _install() async {
    setState(() {
      _downloading = true;
      _cancelled = false;
      _problem = null;
      _progress = null;
    });
    try {
      final file = await downloadInstaller(
        widget.update,
        onProgress: (fraction) {
          if (mounted) setState(() => _progress = fraction);
        },
        cancelled: () => _cancelled,
      );
      if (file == null || !mounted) return;
      // Save where you are in an audiobook before closing.
      final player = Listening.controller;
      if (player != null && player.playing) {
        await player.pause();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await startInstaller(file);
      exit(0);
    } on UpdateDownloadFailure catch (failure) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _problem = failure.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _problem = "The installer couldn't be started.";
        });
      }
    }
  }

  void _openRelease() {
    unawaited(launchUrl(
      Uri.parse(widget.update.url),
      mode: LaunchMode.externalApplication,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final canInstall = update.installerUrl != null;
    return AlertDialog(
      title: Text('Chapterly ${update.version} is available'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_downloading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 12),
              Text(
                _progress == null
                    ? 'Downloading...'
                    : 'Downloading... ${(_progress! * 100).round()}%',
              ),
              const SizedBox(height: 4),
              const Text(
                'Chapterly closes when the download is done, the installer '
                'updates it, and it opens again.',
              ),
            ] else ...[
              Text(
                canInstall
                    ? 'Install now: Chapterly downloads the update, closes, '
                        'installs it and opens again. Your library stays as '
                        'it is.'
                    : 'This release has no installer to download here. See '
                        'the release on GitHub.',
              ),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _problem!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: _downloading
          ? [
              TextButton(
                onPressed: () {
                  _cancelled = true;
                  setState(() => _downloading = false);
                },
                child: const Text('Cancel'),
              ),
            ]
          : [
              TextButton(
                onPressed: _openRelease,
                child: const Text("What's new"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later'),
              ),
              if (canInstall)
                FilledButton(
                  onPressed: _install,
                  child: const Text('Install now'),
                ),
            ],
    );
  }
}
