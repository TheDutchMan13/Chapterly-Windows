import 'package:flutter/material.dart';

import '../models/shelf.dart';

/// The icon for a shelf, the same everywhere in the app.
IconData shelfIcon(Shelf shelf) => switch (shelf) {
      Shelf.finished => Icons.check_circle_outline,
      Shelf.inProgress => Icons.auto_stories_outlined,
      Shelf.forLater => Icons.bookmark_border,
      Shelf.unfinished => Icons.do_not_disturb_on_outlined,
    };
