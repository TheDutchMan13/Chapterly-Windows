import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pin_lock.dart';

/// The profile that was there before profiles existed. Its library and
/// settings stay where they always were, so nothing has to move.
const mainProfileId = 'main';

/// The settings of the other profiles are saved under this start, such as
/// `p.k3x9q2ab.accent`.
const _scopedStart = 'p.';

/// The list of profiles and the one that is open. Never part of a
/// profile's own settings.
const _profilesKey = 'profiles';
const _activeKey = 'activeProfile';

/// Colours for the profile circles. White letters can be read on each.
const profileColors = [
  0xFF795548,
  0xFF1565C0,
  0xFF2E7D32,
  0xFF6A1B9A,
  0xFFC62828,
  0xFF00695C,
  0xFFBF360C,
  0xFF283593,
];

/// Where a profile's settings start in shared_preferences.
String profilePrefix(String id) =>
    id == mainProfileId ? '' : '$_scopedStart$id.';

/// One person's Chapterly on this device: their own books, settings,
/// statistics, sync and PIN.
@immutable
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int color;
  final DateTime createdAt;

  bool get isMain => id == mainProfileId;

  /// The letter in the profile's circle.
  String get initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  Profile copyWith({String? name, int? color}) => Profile(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static Profile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final color = json['color'];
    final created = json['createdAt'];
    return Profile(
      id: id,
      name: name,
      color: color is int ? color : profileColors.first,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        created is int ? created : 0,
      ),
    );
  }
}

/// One profile's part of shared_preferences. It has the same methods the
/// settings use, and adds the profile's start to every key.
class ScopedPrefs {
  ScopedPrefs(this.prefs, this.prefix);

  final SharedPreferences prefs;
  final String prefix;

  String _key(String key) => '$prefix$key';

  bool _owns(String key) => prefix.isEmpty
      ? !key.startsWith(_scopedStart) &&
          key != _profilesKey &&
          key != _activeKey
      : key.startsWith(prefix);

  /// This profile's keys, without the profile's start.
  Set<String> getKeys() => {
        for (final key in prefs.getKeys())
          if (_owns(key)) key.substring(prefix.length),
      };

  String? getString(String key) => prefs.getString(_key(key));
  bool? getBool(String key) => prefs.getBool(_key(key));
  int? getInt(String key) => prefs.getInt(_key(key));
  double? getDouble(String key) => prefs.getDouble(_key(key));
  List<String>? getStringList(String key) => prefs.getStringList(_key(key));

  Future<bool> setString(String key, String value) =>
      prefs.setString(_key(key), value);
  Future<bool> setBool(String key, bool value) =>
      prefs.setBool(_key(key), value);
  Future<bool> setInt(String key, int value) => prefs.setInt(_key(key), value);
  Future<bool> setDouble(String key, double value) =>
      prefs.setDouble(_key(key), value);
  Future<bool> setStringList(String key, List<String> value) =>
      prefs.setStringList(_key(key), value);
  Future<bool> remove(String key) => prefs.remove(_key(key));

  /// Removes all of this profile's settings.
  Future<void> clear() async {
    for (final key in getKeys()) {
      await prefs.remove(_key(key));
    }
  }
}

/// The profiles on this device and which one is open.
class ProfileStore extends ChangeNotifier {
  ProfileStore(this._prefs, List<Profile> profiles, String activeId)
      : _profiles = profiles,
        _activeId = activeId;

  final SharedPreferences _prefs;
  List<Profile> _profiles;
  String _activeId;

  /// Reads the profiles. The first time, the library already on the device
  /// becomes the first profile, called "Me".
  static Future<ProfileStore> load({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = <Profile>[];
    try {
      final raw = prefs.getString(_profilesKey);
      final list = raw == null ? null : jsonDecode(raw);
      if (list is List) {
        for (final item in list) {
          final profile = Profile.fromJson(item);
          if (profile != null && !profiles.any((p) => p.id == profile.id)) {
            profiles.add(profile);
          }
        }
      }
    } on FormatException {
      // A damaged list: start again from the first profile.
    }
    if (profiles.isEmpty) {
      profiles.add(Profile(
        id: mainProfileId,
        name: 'Me',
        color: profileColors.first,
        createdAt: now ?? DateTime.now(),
      ));
    }
    final saved = prefs.getString(_activeKey);
    final active =
        profiles.any((p) => p.id == saved) ? saved! : profiles.first.id;
    return ProfileStore(prefs, profiles, active);
  }

  List<Profile> get profiles => List.unmodifiable(_profiles);

  Profile get active => _profiles.firstWhere((p) => p.id == _activeId);

  /// More than one profile, so switching is worth showing.
  bool get hasOthers => _profiles.length > 1;

  Profile? byId(String id) {
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  /// A profile's settings.
  ScopedPrefs scope(String id) => ScopedPrefs(_prefs, profilePrefix(id));

  /// Whether a profile asks for a PIN when it opens.
  bool hasPin(String id) => scope(id).getString('pinHash') != null;

  /// Checks a PIN against the one a profile saved.
  bool checkPin(String id, String pin) {
    final prefs = scope(id);
    final hash = prefs.getString('pinHash');
    final salt = prefs.getString('pinSalt');
    if (hash == null || !pinMatches(pin, hash, oldSalt: salt)) return false;
    if (isOldPinHash(hash)) {
      // Saved the new way from now on.
      prefs.setString('pinHash', hashNewPin(pin));
      prefs.remove('pinSalt');
    }
    return true;
  }

  /// What is wrong with a name for a profile, or null when it can be used.
  String? nameProblem(String name, {String? exceptId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Type a name.';
    if (trimmed.length > 30) return 'Use 30 letters or fewer.';
    final lower = trimmed.toLowerCase();
    final taken = _profiles.any(
      (p) => p.id != exceptId && p.name.trim().toLowerCase() == lower,
    );
    return taken ? 'There is already a profile with this name.' : null;
  }

  Future<Profile> add(String name, {Random? random, DateTime? now}) async {
    final problem = nameProblem(name);
    if (problem != null) throw ArgumentError(problem);
    final used = {for (final p in _profiles) p.color};
    final color = profileColors.firstWhere(
      (c) => !used.contains(c),
      orElse: () => profileColors[_profiles.length % profileColors.length],
    );
    final profile = Profile(
      id: _newId(random ?? Random.secure()),
      name: name.trim(),
      color: color,
      createdAt: now ?? DateTime.now(),
    );
    _profiles = [..._profiles, profile];
    await _save();
    notifyListeners();
    return profile;
  }

  Future<void> rename(String id, String name) async {
    final problem = nameProblem(name, exceptId: id);
    if (problem != null) throw ArgumentError(problem);
    _profiles = [
      for (final p in _profiles) p.id == id ? p.copyWith(name: name.trim()) : p,
    ];
    await _save();
    notifyListeners();
  }

  Future<void> setColor(String id, int color) async {
    _profiles = [
      for (final p in _profiles) p.id == id ? p.copyWith(color: color) : p,
    ];
    await _save();
    notifyListeners();
  }

  /// Makes [id] the profile that opens. The app then switches to it.
  Future<void> setActive(String id) async {
    if (byId(id) == null) throw ArgumentError('No profile $id');
    _activeId = id;
    await _save();
    await _prefs.setString(_activeKey, id);
    notifyListeners();
  }

  /// Forgets a profile and its settings. Its books and files are removed
  /// with removeProfileFiles. The open profile cannot be removed.
  Future<void> remove(String id) async {
    if (id == _activeId) {
      throw StateError('The open profile cannot be removed.');
    }
    if (byId(id) == null) return;
    await scope(id).clear();
    _profiles = [
      for (final p in _profiles)
        if (p.id != id) p,
    ];
    await _save();
    notifyListeners();
  }

  String _newId(Random random) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    while (true) {
      final id =
          List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
      if (id != mainProfileId && byId(id) == null) return id;
    }
  }

  Future<void> _save() => _prefs.setString(
        _profilesKey,
        jsonEncode([for (final p in _profiles) p.toJson()]),
      );
}

/// Lets screens switch profiles. Set up in main.dart. Null in tests, and the
/// profile parts of the screens then stay hidden.
class ProfileSwitching {
  ProfileSwitching._();

  static ProfileStore? store;

  /// Closes the open profile and opens [id].
  static Future<void> Function(String id)? switchTo;

  /// Removes a profile's books and files from this device.
  static Future<void> Function(String id)? removeFiles;

  /// True where Chapterly restarts to open another profile (Windows).
  static bool switchRestarts = false;
}
