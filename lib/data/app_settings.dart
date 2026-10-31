import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_format.dart';
import '../models/shelf.dart';
import 'pin_lock.dart';

enum SortField {
  dateAdded,
  title,
  author,
  rating,
  pages,
  dateFinished,
  publicationYear,
  dateModified,
  format,
  favorite,
  priority,
  nextUp,
}

extension SortFieldLabel on SortField {
  String get label => switch (this) {
        SortField.dateAdded => 'Date added',
        SortField.title => 'Title',
        SortField.author => 'Author',
        SortField.rating => 'Rating',
        SortField.pages => 'Pages',
        SortField.dateFinished => 'Date finished',
        SortField.publicationYear => 'Publication year',
        SortField.dateModified => 'Date modified',
        SortField.format => 'Format',
        SortField.favorite => 'Favorites first',
        SortField.priority => 'Priority',
        SortField.nextUp => 'Next up',
      };
}

enum DisplayMode { list, grid, table }

DateTime? _fromMillis(int? value) =>
    value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);

/// How the library is sorted and shown, the app's theme, accent colour and
/// font, reading goals, and the backup reminder. Saved on the phone with
/// shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings({this.prefs});

  /// Brown, the colour Chapterly starts with.
  static const int defaultAccent = 0xFF795548;

  final SharedPreferences? prefs;
  SortField _sortField = SortField.dateAdded;
  bool _ascending = false;
  DisplayMode _display = DisplayMode.list;
  int _accent = defaultAccent;
  String? _fontFamily;
  int? _monthlyGoal;
  ThemeMode _themeMode = ThemeMode.system;
  bool _pureBlack = false;
  bool _paperLight = false;
  bool _backupReminder = true;
  int _backupDays = 30;
  bool _syncEnabled = false;
  String? _syncCode;
  DateTime? _lastSyncAt;
  int _lastSyncChanged = 0;
  String? _lastSyncError;
  String? _syncAddress;
  bool _syncOnOpen = true;
  bool _reviewSync = true;
  int _syncEveryMinutes = 15;
  bool _checkUpdates = true;
  DateTime? _lastUpdateCheck;
  List<String> _collections = [];
  String? _pinHash;
  String? _pinSalt;
  int _lockAfterSeconds = 30;
  DateTime? _lastBackup;
  DateTime? _backupSnoozed;
  DateTime? _reminderSince;
  final Map<int, int> _goals = {};
  final Map<int, int> _pageGoals = {};
  final Map<int, Map<String, int>> _tagGoals = {};
  bool _autoBackup = false;
  int _autoBackupDays = 7;
  DateTime? _lastAutoBackupAt;
  String? _lastAutoBackupPath;
  String? _lastAutoBackupError;
  Shelf? _defaultShelf;
  BookFormat? _defaultFormat;
  List<String> _defaultTags = [];
  bool _ratingAsNumber = false;
  bool _showFormatOnCards = true;
  bool _showTagsOnCards = true;
  double _coverScale = 1.0;
  List<Shelf> _shelfOrder = List.of(Shelf.values);

  SortField get sortField => _sortField;
  bool get ascending => _ascending;
  DisplayMode get display => _display;

  /// The accent colour as a 0xAARRGGBB number.
  int get accent => _accent;

  /// The name of a font on the phone, or null for the app's normal font.
  String? get fontFamily => _fontFamily;

  /// Books to finish every month, or null for no monthly goal.
  int? get monthlyGoal => _monthlyGoal;

  /// Follow the phone, or always light, or always dark.
  ThemeMode get themeMode => _themeMode;

  /// Use true black instead of dark grey in dark mode.
  bool get pureBlack => _pureBlack;

  /// A warm, cream page colour instead of white in light mode.
  bool get paperLight => _paperLight;

  bool get backupReminder => _backupReminder;

  /// How many days may pass before the app asks for a new backup.
  int get backupDays => _backupDays;

  DateTime? get lastBackup => _lastBackup;

  /// Whether the PC can sync with this phone (only while the app is open).
  bool get syncEnabled => _syncEnabled;

  /// The pairing code the PC must send. Null until sync is first switched on.
  String? get syncCode => _syncCode;

  /// When the PC last synced successfully, and how many books it changed here.
  DateTime? get lastSyncAt => _lastSyncAt;
  int get lastSyncChanged => _lastSyncChanged;

  /// Why the last sync attempt failed, or null if it worked.
  String? get lastSyncError => _lastSyncError;

  /// The phone's address for sync, such as 192.168.1.20:8765, or null when
  /// this PC is not paired.
  String? get syncAddress => _syncAddress;

  /// Sync with the phone each time Chapterly opens, quietly, if the phone is
  /// there.
  bool get syncOnOpen => _syncOnOpen;

  /// Show what a sync will change before it happens. Automatic syncs then
  /// hold back changes that would remove books, for you to review.
  bool get reviewSync => _reviewSync;

  /// Sync in the background every this many minutes while Chapterly is open.
  /// 0 turns it off.
  int get syncEveryMinutes => _syncEveryMinutes;

  /// Ask GitHub once a day whether a newer Chapterly for Windows is out.
  bool get checkUpdates => _checkUpdates;

  /// When the last update check ran.
  DateTime? get lastUpdateCheck => _lastUpdateCheck;

  /// The names of your own shelves, including ones with no books yet.
  List<String> get collections => List.unmodifiable(_collections);

  /// Save a backup file by itself every [autoBackupDays] days.
  bool get autoBackup => _autoBackup;
  int get autoBackupDays => _autoBackupDays;
  DateTime? get lastAutoBackupAt => _lastAutoBackupAt;
  String? get lastAutoBackupPath => _lastAutoBackupPath;

  /// Why the last automatic backup failed, or null if it worked.
  String? get lastAutoBackupError => _lastAutoBackupError;

  /// The shelf new books go on, or null to ask every time.
  Shelf? get defaultShelf => _defaultShelf;

  /// The format given to new books, or null for "not set".
  BookFormat? get defaultFormat => _defaultFormat;

  /// Tags given to every new book.
  List<String> get defaultTags => List.unmodifiable(_defaultTags);

  /// Show ratings as a number (4/5) instead of stars.
  bool get ratingAsNumber => _ratingAsNumber;

  bool get showFormatOnCards => _showFormatOnCards;
  bool get showTagsOnCards => _showTagsOnCards;

  /// How big the covers are in the grid view, from [minCoverScale] to
  /// [maxCoverScale]; 1 is the normal size.
  double get coverScale => _coverScale;
  static const minCoverScale = 0.7;
  static const maxCoverScale = 1.6;

  /// The four main shelves in the order their tabs are shown.
  List<Shelf> get shelfOrder => List.unmodifiable(_shelfOrder);

  /// Whether a PIN is needed to open the app.
  bool get pinEnabled => _pinHash != null;

  /// How long the app can be in the background before it asks for the PIN.
  int get lockAfterSeconds => _lockAfterSeconds;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(prefs: prefs);
    settings._sortField =
        SortField.values.asNameMap()[prefs.getString('sortField')] ??
            SortField.dateAdded;
    settings._ascending = prefs.getBool('ascending') ?? false;
    settings._display =
        DisplayMode.values.asNameMap()[prefs.getString('display')] ??
            DisplayMode.list;
    settings._accent = prefs.getInt('accent') ?? defaultAccent;
    settings._fontFamily = prefs.getString('font');
    settings._monthlyGoal = prefs.getInt('monthly_goal');
    settings._themeMode =
        ThemeMode.values.asNameMap()[prefs.getString('themeMode')] ??
            ThemeMode.system;
    settings._pureBlack = prefs.getBool('pureBlack') ?? false;
    settings._paperLight = prefs.getBool('paperLight') ?? false;
    settings._backupReminder = prefs.getBool('backupReminder') ?? true;
    settings._backupDays = prefs.getInt('backupDays') ?? 30;
    settings._syncEnabled = prefs.getBool('syncEnabled') ?? false;
    settings._syncCode = prefs.getString('syncCode');
    settings._lastSyncAt = _fromMillis(prefs.getInt('lastSync'));
    settings._lastSyncChanged = prefs.getInt('lastSyncChanged') ?? 0;
    settings._lastSyncError = prefs.getString('lastSyncError');
    settings._syncAddress = prefs.getString('syncAddress');
    settings._syncOnOpen = prefs.getBool('syncOnOpen') ?? true;
    settings._reviewSync = prefs.getBool('reviewSync') ?? true;
    settings._syncEveryMinutes = prefs.getInt('syncEveryMinutes') ?? 15;
    settings._checkUpdates = prefs.getBool('checkUpdates') ?? true;
    settings._lastUpdateCheck = _fromMillis(prefs.getInt('lastUpdateCheck'));
    settings._collections = prefs.getStringList('collections') ?? [];
    settings._pinHash = prefs.getString('pinHash');
    settings._pinSalt = prefs.getString('pinSalt');
    settings._lockAfterSeconds = prefs.getInt('lockAfterSeconds') ?? 30;
    settings._defaultShelf =
        Shelf.values.asNameMap()[prefs.getString('defaultShelf')];
    settings._defaultFormat =
        BookFormat.values.asNameMap()[prefs.getString('defaultFormat')];
    settings._defaultTags = prefs.getStringList('defaultTags') ?? [];
    settings._ratingAsNumber = prefs.getBool('ratingAsNumber') ?? false;
    settings._showFormatOnCards = prefs.getBool('showFormatOnCards') ?? true;
    settings._showTagsOnCards = prefs.getBool('showTagsOnCards') ?? true;
    settings._coverScale =
        _clampScale(prefs.getDouble('coverScale') ?? 1.0);
    settings._shelfOrder = _cleanShelfOrder([
      for (final name in prefs.getStringList('shelfOrder') ?? <String>[])
        ?Shelf.values.asNameMap()[name],
    ]);
    settings._tagGoals.addAll(_decodeTagGoals(prefs.getString('tagGoals')));
    settings._autoBackup = prefs.getBool('autoBackup') ?? false;
    settings._autoBackupDays = prefs.getInt('autoBackupDays') ?? 7;
    settings._lastAutoBackupAt = _fromMillis(prefs.getInt('lastAutoBackup'));
    settings._lastAutoBackupPath = prefs.getString('lastAutoBackupPath');
    settings._lastAutoBackupError = prefs.getString('lastAutoBackupError');
    settings._lastBackup = _fromMillis(prefs.getInt('lastBackup'));
    settings._backupSnoozed = _fromMillis(prefs.getInt('backupSnoozed'));
    settings._reminderSince = _fromMillis(prefs.getInt('backupSince'));
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('goal_')) continue;
      final year = int.tryParse(key.substring(5));
      final goal = prefs.getInt(key);
      if (year != null && goal != null) settings._goals[year] = goal;
    }
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('pagesgoal_')) continue;
      final year = int.tryParse(key.substring(10));
      final goal = prefs.getInt(key);
      if (year != null && goal != null) settings._pageGoals[year] = goal;
    }
    return settings;
  }

  void setAutoBackup(bool value) {
    _autoBackup = value;
    prefs?.setBool('autoBackup', value);
    notifyListeners();
  }

  void setAutoBackupDays(int days) {
    _autoBackupDays = days;
    prefs?.setInt('autoBackupDays', days);
    notifyListeners();
  }

  /// True when automatic backups are on and none was made in the last
  /// [autoBackupDays] days.
  bool autoBackupDue([DateTime? now]) {
    if (!_autoBackup) return false;
    final last = _lastAutoBackupAt;
    if (last == null) return true;
    final current = now ?? DateTime.now();
    return !current.isBefore(last.add(Duration(days: _autoBackupDays)));
  }

  void recordAutoBackup({required DateTime at, required String path}) {
    _lastAutoBackupAt = at;
    _lastAutoBackupPath = path;
    _lastAutoBackupError = null;
    prefs?.setInt('lastAutoBackup', at.millisecondsSinceEpoch);
    prefs?.setString('lastAutoBackupPath', path);
    prefs?.remove('lastAutoBackupError');
    notifyListeners();
  }

  void recordAutoBackupError(String message) {
    _lastAutoBackupError = message;
    prefs?.setString('lastAutoBackupError', message);
    notifyListeners();
  }

  static Map<int, Map<String, int>> _decodeTagGoals(String? text) {
    if (text == null) return {};
    try {
      final data = jsonDecode(text);
      if (data is! Map) return {};
      final result = <int, Map<String, int>>{};
      for (final entry in data.entries) {
        final year = int.tryParse(entry.key.toString());
        final goals = entry.value;
        if (year == null || goals is! Map) continue;
        result[year] = {
          for (final goal in goals.entries)
            if (goal.value is int && (goal.value as int) > 0)
              goal.key.toString(): goal.value as int,
        };
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  /// Goals for books with a tag in [year], for example {"sci-fi": 10}.
  Map<String, int> tagGoalsFor(int year) =>
      Map.unmodifiable(_tagGoals[year] ?? const <String, int>{});

  /// A null or zero goal removes the goal for that tag and year.
  void setTagGoal(int year, String tag, int? goal) {
    final clean = tag.trim();
    if (clean.isEmpty) return;
    final goals = {...?_tagGoals[year]};
    if (goal == null || goal <= 0) {
      goals.remove(clean);
    } else {
      goals[clean] = goal;
    }
    if (goals.isEmpty) {
      _tagGoals.remove(year);
    } else {
      _tagGoals[year] = goals;
    }
    prefs?.setString(
      'tagGoals',
      jsonEncode({
        for (final entry in _tagGoals.entries) '${entry.key}': entry.value,
      }),
    );
    notifyListeners();
  }

  /// Removes repeats and adds any shelf that is missing, keeping the order.
  static List<Shelf> _cleanShelfOrder(List<Shelf> order) {
    final result = <Shelf>[];
    for (final shelf in [...order, ...Shelf.values]) {
      if (!result.contains(shelf)) result.add(shelf);
    }
    return result;
  }

  /// Pass null to ask which shelf every time.
  void setDefaultShelf(Shelf? shelf) {
    _defaultShelf = shelf;
    if (shelf == null) {
      prefs?.remove('defaultShelf');
    } else {
      prefs?.setString('defaultShelf', shelf.name);
    }
    notifyListeners();
  }

  void setDefaultFormat(BookFormat? format) {
    _defaultFormat = format;
    if (format == null) {
      prefs?.remove('defaultFormat');
    } else {
      prefs?.setString('defaultFormat', format.name);
    }
    notifyListeners();
  }

  void setDefaultTags(List<String> tags) {
    _defaultTags = List.of(tags);
    prefs?.setStringList('defaultTags', _defaultTags);
    notifyListeners();
  }

  void setRatingAsNumber(bool value) {
    _ratingAsNumber = value;
    prefs?.setBool('ratingAsNumber', value);
    notifyListeners();
  }

  void setShowFormatOnCards(bool value) {
    _showFormatOnCards = value;
    prefs?.setBool('showFormatOnCards', value);
    notifyListeners();
  }

  void setShowTagsOnCards(bool value) {
    _showTagsOnCards = value;
    prefs?.setBool('showTagsOnCards', value);
    notifyListeners();
  }

  static double _clampScale(double value) => value < minCoverScale
      ? minCoverScale
      : value > maxCoverScale
          ? maxCoverScale
          : value;

  void setCoverScale(double value) {
    final scale = _clampScale(value);
    if (scale == _coverScale) return;
    _coverScale = scale;
    prefs?.setDouble('coverScale', scale);
    notifyListeners();
  }

  /// Sets the order of the four main shelf tabs. Anything missing from
  /// [order] is added at the end.
  void setShelfOrder(List<Shelf> order) {
    _shelfOrder = _cleanShelfOrder(order);
    prefs?.setStringList('shelfOrder', [for (final s in _shelfOrder) s.name]);
    notifyListeners();
  }

  /// Choosing the field that is already selected flips the direction.
  void setSort(SortField field) {
    if (field == _sortField) {
      _ascending = !_ascending;
    } else {
      _sortField = field;
      _ascending = field == SortField.title ||
          field == SortField.author ||
          field == SortField.format ||
          field == SortField.nextUp;
    }
    _save();
    notifyListeners();
  }

  void setDisplay(DisplayMode mode) {
    _display = mode;
    _save();
    notifyListeners();
  }

  void toggleDisplay() {
    _display =
        _display == DisplayMode.list ? DisplayMode.grid : DisplayMode.list;
    _save();
    notifyListeners();
  }

  void setAccent(int colorValue) {
    _accent = colorValue;
    _save();
    notifyListeners();
  }

  /// Pass null to go back to the app's normal font.
  void setFontFamily(String? family) {
    _fontFamily = family;
    _save();
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    prefs?.setString('themeMode', mode.name);
    notifyListeners();
  }

  void setPureBlack(bool value) {
    _pureBlack = value;
    prefs?.setBool('pureBlack', value);
    notifyListeners();
  }

  void setPaperLight(bool value) {
    _paperLight = value;
    prefs?.setBool('paperLight', value);
    notifyListeners();
  }

  void setBackupReminder(bool value) {
    _backupReminder = value;
    prefs?.setBool('backupReminder', value);
    notifyListeners();
  }

  void setBackupDays(int days) {
    _backupDays = days;
    prefs?.setInt('backupDays', days);
    notifyListeners();
  }

  void setSyncEnabled(bool value) {
    _syncEnabled = value;
    prefs?.setBool('syncEnabled', value);
    notifyListeners();
  }

  void setSyncCode(String code) {
    _syncCode = code;
    prefs?.setString('syncCode', code);
    notifyListeners();
  }

  void setSyncOnOpen(bool value) {
    _syncOnOpen = value;
    prefs?.setBool('syncOnOpen', value);
    notifyListeners();
  }

  void setReviewSync(bool value) {
    _reviewSync = value;
    prefs?.setBool('reviewSync', value);
    notifyListeners();
  }

  void setSyncEveryMinutes(int minutes) {
    _syncEveryMinutes = minutes < 0 ? 0 : minutes;
    prefs?.setInt('syncEveryMinutes', _syncEveryMinutes);
    notifyListeners();
  }

  void setCheckUpdates(bool value) {
    _checkUpdates = value;
    prefs?.setBool('checkUpdates', value);
    notifyListeners();
  }

  void setLastUpdateCheck(DateTime at) {
    _lastUpdateCheck = at;
    prefs?.setInt('lastUpdateCheck', at.millisecondsSinceEpoch);
  }

  /// Pass null to forget the phone.
  void setSyncAddress(String? address) {
    _syncAddress = address;
    if (address == null) {
      prefs?.remove('syncAddress');
    } else {
      prefs?.setString('syncAddress', address);
    }
    notifyListeners();
  }

  /// Called after a sync worked.
  void recordSync({required DateTime at, required int changed}) {
    _lastSyncAt = at;
    _lastSyncChanged = changed;
    _lastSyncError = null;
    prefs?.setInt('lastSync', at.millisecondsSinceEpoch);
    prefs?.setInt('lastSyncChanged', changed);
    prefs?.remove('lastSyncError');
    notifyListeners();
  }

  /// Called after a sync attempt failed.
  void recordSyncError(String message) {
    _lastSyncError = message;
    prefs?.setString('lastSyncError', message);
    notifyListeners();
  }

  /// Adds a shelf name (ignored if it already exists, ignoring capitals).
  void addCollection(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    if (_collections.any((c) => c.toLowerCase() == clean.toLowerCase())) return;
    _collections = [..._collections, clean];
    prefs?.setStringList('collections', _collections);
    notifyListeners();
  }

  void renameCollection(String from, String to) {
    final clean = to.trim();
    if (clean.isEmpty) return;
    final next = <String>[];
    for (final name in _collections) {
      final value = name == from ? clean : name;
      if (!next.any((c) => c.toLowerCase() == value.toLowerCase())) {
        next.add(value);
      }
    }
    _collections = next;
    prefs?.setStringList('collections', _collections);
    notifyListeners();
  }

  void removeCollection(String name) {
    _collections = [for (final c in _collections) if (c != name) c];
    prefs?.setStringList('collections', _collections);
    notifyListeners();
  }

  /// Saves a PIN (stored as a salted hash, never as the PIN itself).
  void setPin(String pin) {
    final salt = newPinSalt();
    _pinSalt = salt;
    _pinHash = hashPin(pin, salt);
    prefs?.setString('pinSalt', salt);
    prefs?.setString('pinHash', _pinHash!);
    notifyListeners();
  }

  bool checkPin(String pin) {
    final hash = _pinHash;
    final salt = _pinSalt;
    return hash != null && salt != null && hashPin(pin, salt) == hash;
  }

  void clearPin() {
    _pinHash = null;
    _pinSalt = null;
    prefs?.remove('pinHash');
    prefs?.remove('pinSalt');
    notifyListeners();
  }

  void setLockAfterSeconds(int seconds) {
    _lockAfterSeconds = seconds;
    prefs?.setInt('lockAfterSeconds', seconds);
    notifyListeners();
  }

  /// Call after a backup was exported.
  void markBackedUp([DateTime? now]) {
    _lastBackup = now ?? DateTime.now();
    _backupSnoozed = null;
    prefs?.setInt('lastBackup', _lastBackup!.millisecondsSinceEpoch);
    prefs?.remove('backupSnoozed');
    notifyListeners();
  }

  /// "Later": ask again in a week.
  void snoozeBackupReminder([DateTime? now]) {
    _backupSnoozed = now ?? DateTime.now();
    prefs?.setInt('backupSnoozed', _backupSnoozed!.millisecondsSinceEpoch);
    notifyListeners();
  }

  /// True when it is time to ask for a backup: the reminder is on, there are
  /// books, and the chosen number of days have passed since the last backup
  /// (or since the app first checked, if there never was one). After "Later"
  /// it waits another week.
  bool backupDue({required int bookCount, DateTime? now}) {
    if (!_backupReminder || bookCount == 0) return false;
    final current = now ?? DateTime.now();
    if (_reminderSince == null) {
      _reminderSince = current;
      prefs?.setInt('backupSince', current.millisecondsSinceEpoch);
    }
    final base = _lastBackup ?? _reminderSince!;
    var dueAt = base.add(Duration(days: _backupDays));
    final snoozed = _backupSnoozed;
    if (snoozed != null) {
      final again = snoozed.add(const Duration(days: 7));
      if (again.isAfter(dueAt)) dueAt = again;
    }
    return !current.isBefore(dueAt);
  }

  /// A null or zero goal removes the monthly goal.
  void setMonthlyGoal(int? goal) {
    if (goal == null || goal <= 0) {
      _monthlyGoal = null;
      prefs?.remove('monthly_goal');
    } else {
      _monthlyGoal = goal;
      prefs?.setInt('monthly_goal', goal);
    }
    notifyListeners();
  }

  int? goalFor(int year) => _goals[year];

  /// The number of pages to finish in [year], or null for no pages goal.
  int? pagesGoalFor(int year) => _pageGoals[year];

  /// A null or zero goal removes the pages goal for that year.
  void setPagesGoal(int year, int? goal) {
    if (goal == null || goal <= 0) {
      _pageGoals.remove(year);
      prefs?.remove('pagesgoal_$year');
    } else {
      _pageGoals[year] = goal;
      prefs?.setInt('pagesgoal_$year', goal);
    }
    notifyListeners();
  }

  /// A null or zero goal removes the goal for that year.
  void setGoal(int year, int? goal) {
    if (goal == null || goal <= 0) {
      _goals.remove(year);
      prefs?.remove('goal_$year');
    } else {
      _goals[year] = goal;
      prefs?.setInt('goal_$year', goal);
    }
    notifyListeners();
  }

  void _save() {
    prefs?.setString('sortField', _sortField.name);
    prefs?.setBool('ascending', _ascending);
    prefs?.setString('display', _display.name);
    prefs?.setInt('accent', _accent);
    final font = _fontFamily;
    if (font == null) {
      prefs?.remove('font');
    } else {
      prefs?.setString('font', font);
    }
  }
}
