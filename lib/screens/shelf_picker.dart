import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../models/shelf.dart';

/// Asks which shelf a book should go on. Returns null if cancelled.
Future<Shelf?> showShelfPicker(BuildContext context) {
  return showDialog<Shelf>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Add to shelf'),
      children: [
        for (final option in Shelf.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(option),
            child: Text(option.label),
          ),
      ],
    ),
  );
}

/// The shelf for a new book: the default chosen in Settings, or asks if there
/// is none. Returns null if cancelled.
Future<Shelf?> chooseShelfForNewBook(
  BuildContext context,
  AppSettings settings,
) async {
  final preset = settings.defaultShelf;
  if (preset != null) return preset;
  return showShelfPicker(context);
}
