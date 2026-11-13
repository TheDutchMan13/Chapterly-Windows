import 'package:flutter/widgets.dart';

import '../data/app_settings.dart';

/// Builds the app's root (its theme) again only when something that changes
/// how the app looks was changed. Any other setting, such as the sort order
/// or the width of the list, used to rebuild the whole app, theme and all.
class ThemeChanges extends StatefulWidget {
  const ThemeChanges({super.key, required this.settings, required this.builder});

  final AppSettings settings;
  final WidgetBuilder builder;

  @override
  State<ThemeChanges> createState() => _ThemeChangesState();
}

class _ThemeChangesState extends State<ThemeChanges> {
  late Object _key = _lookOf(widget.settings);

  /// Everything the theme and the dark/light choice are made from.
  static Object _lookOf(AppSettings s) => (
        s.look,
        s.pureBlack,
        s.fontFamily,
        s.accent,
        s.paperLight,
        s.themeMode,
      );

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_changed);
  }

  @override
  void didUpdateWidget(ThemeChanges old) {
    super.didUpdateWidget(old);
    if (old.settings != widget.settings) {
      old.settings.removeListener(_changed);
      widget.settings.addListener(_changed);
      _key = _lookOf(widget.settings);
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final now = _lookOf(widget.settings);
    if (now != _key) setState(() => _key = now);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
