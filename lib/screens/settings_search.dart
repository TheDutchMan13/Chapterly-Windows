import 'package:flutter/material.dart';

// The same file is in the Android app; keep the two copies alike.

/// What was typed in the Settings search box, and the sections that answer
/// to it. A section shows when it has every word typed, in its heading or
/// anywhere in its text (setting names and their descriptions).
class SettingsSearch extends ChangeNotifier {
  final Set<_SettingsSearchableState> _sections = {};
  String _query = '';

  String get query => _query;

  List<String> get words => [
        for (final word in _query.toLowerCase().split(RegExp(r'\s+')))
          if (word.isNotEmpty) word,
      ];

  bool get searching => words.isNotEmpty;

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    for (final section in _sections) {
      section.refreshText();
    }
    notifyListeners();
  }

  /// True when nothing is typed, or some section has what was typed.
  bool get anyMatch {
    final typed = words;
    return typed.isEmpty || _sections.any((s) => s.matches(typed));
  }

  /// A section's text changed while searching.
  void textsChanged() => notifyListeners();
}

/// Gives the sections below it the search to answer to.
class SettingsSearchScope extends InheritedNotifier<SettingsSearch> {
  const SettingsSearchScope({
    super.key,
    required SettingsSearch search,
    required super.child,
  }) : super(notifier: search);

  /// The search above, or null when there is none (the section then always
  /// shows).
  static SettingsSearch? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SettingsSearchScope>()
      ?.notifier;
}

/// A part of the settings that the search can hide. [builder] gets whether a
/// search is under way, so a collapsed group can open itself.
class SettingsSearchable extends StatefulWidget {
  const SettingsSearchable({
    super.key,
    required this.title,
    required this.builder,
  });

  final String title;
  final Widget Function(BuildContext context, bool searching) builder;

  @override
  State<SettingsSearchable> createState() => _SettingsSearchableState();
}

class _SettingsSearchableState extends State<SettingsSearchable> {
  SettingsSearch? _search;
  String _text = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final search = SettingsSearchScope.maybeOf(context);
    if (!identical(search, _search)) {
      _search?._sections.remove(this);
      _search = search;
      search?._sections.add(this);
    }
  }

  @override
  void dispose() {
    _search?._sections.remove(this);
    super.dispose();
  }

  /// Reads the words shown in this section, including those in groups that
  /// are folded away and in the options of drop-down lists.
  void refreshText() {
    if (!mounted) return;
    final found = StringBuffer();
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text) {
        found.write(' ${widget.data ?? widget.textSpan?.toPlainText() ?? ''}');
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    _text = found.toString().toLowerCase();
  }

  bool matches(List<String> words) {
    final haystack = '${widget.title.toLowerCase()} $_text';
    return words.every(haystack.contains);
  }

  @override
  Widget build(BuildContext context) {
    final search = _search;
    final searching = search?.searching ?? false;
    final shown = !searching || matches(search!.words);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final before = _text;
      refreshText();
      if (before != _text && (_search?.searching ?? false)) {
        _search?.textsChanged();
      }
    });
    return Offstage(offstage: !shown, child: widget.builder(context, searching));
  }
}

/// The search box at the top of Settings.
class SettingsSearchField extends StatefulWidget {
  const SettingsSearchField({super.key, required this.search});

  final SettingsSearch search;

  @override
  State<SettingsSearchField> createState() => _SettingsSearchFieldState();
}

class _SettingsSearchFieldState extends State<SettingsSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.search.setQuery('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onChanged: (value) {
          widget.search.setQuery(value);
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'Search settings',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: _clear,
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

/// "Nothing found" under the search box, shown only when no section answers.
class SettingsNoMatch extends StatelessWidget {
  const SettingsNoMatch({super.key});

  @override
  Widget build(BuildContext context) {
    final search = SettingsSearchScope.maybeOf(context);
    if (search == null || search.anyMatch) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'No settings match "${search.query.trim()}".',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
