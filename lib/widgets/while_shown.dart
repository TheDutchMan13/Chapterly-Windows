import 'package:flutter/widgets.dart';

/// Builds [build] only while the page is on screen. A page kept under others
/// (in an IndexedStack, say) shows what it last drew and does no work, then
/// draws itself again the moment it is shown. Without this every page was
/// worked out again on each change to the library, even the hidden ones.
class WhileShown extends StatefulWidget {
  const WhileShown({super.key, required this.build});

  final WidgetBuilder build;

  @override
  State<WhileShown> createState() => _WhileShownState();
}

class _WhileShownState extends State<WhileShown> {
  Widget? _last;

  @override
  Widget build(BuildContext context) {
    // An IndexedStack tells each page whether it is the one showing. Asking
    // also makes this rebuild when the page is shown again.
    final shown = Visibility.of(context);
    final last = _last;
    if (!shown && last != null) return last;
    return _last = widget.build(context);
  }
}
