// The same file is in both apps (lib/data/sync_profiles.dart).

import 'dart:convert';

/// Told in the phone's ping when one pairing syncs every profile.
const syncProfilesVersion = 1;

/// The most profiles a device lists or adds in one go.
const maxSyncProfiles = 50;

/// One profile, as a device tells the other about it.
class SyncProfileInfo {
  const SyncProfileInfo({
    required this.id,
    required this.name,
    required this.color,
    this.locked = false,
  });

  final String id;
  final String name;
  final int color;

  /// Has a PIN and isn't the open profile on that device, so it can't sync
  /// until it is opened there.
  final bool locked;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'locked': locked,
      };

  static SyncProfileInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final color = json['color'];
    if (id is! String || !isSyncProfileId(id)) return null;
    if (name is! String || name.trim().isEmpty || name.length > 60) {
      return null;
    }
    return SyncProfileInfo(
      id: id,
      name: name.trim(),
      color: color is int ? color : 0,
      locked: json['locked'] == true,
    );
  }
}

final _profileId = RegExp(r'^[a-z0-9]{1,32}$');

/// Whether [id] looks like a profile's id ("main", or 8 letters and digits).
bool isSyncProfileId(String id) => _profileId.hasMatch(id);

/// Where one profile's sync requests go, such as `/v2/p/main/sync`. Without a
/// profile, the phone's open profile (`/v2/sync`), as before profiles synced.
String profileSyncPath(String? profileId, String rest) =>
    profileId == null ? '/v2$rest' : '/v2/p/$profileId$rest';

/// Splits `/v2/p/<id>/<rest>` into the id and `/v2/<rest>`, or null.
({String id, String path})? splitProfilePath(String path) {
  const start = '/v2/p/';
  if (!path.startsWith(start)) return null;
  final rest = path.substring(start.length);
  final slash = rest.indexOf('/');
  if (slash <= 0) return null;
  final id = rest.substring(0, slash);
  if (!isSyncProfileId(id)) return null;
  return (id: id, path: '/v2${rest.substring(slash)}');
}

/// The phone's answer to `/v2/profiles`.
String encodeProfileList(List<SyncProfileInfo> profiles) => jsonEncode({
      'profiles': [for (final profile in profiles) profile.toJson()],
    });

/// Reads [encodeProfileList]. Throws a [FormatException] when it isn't one.
List<SyncProfileInfo> decodeProfileList(String text) {
  Object? data;
  try {
    data = jsonDecode(text);
  } on FormatException {
    data = null;
  }
  final list = data is Map ? data['profiles'] : null;
  if (list is! List) {
    throw const FormatException('Your phone sent no list of profiles.');
  }
  final seen = <String>{};
  return [
    for (final item in list.take(maxSyncProfiles))
      if (SyncProfileInfo.fromJson(item) case final profile?)
        if (seen.add(profile.id)) profile,
  ];
}

/// A new profile to add on the other device.
typedef NewSyncProfile = ({String name, int color});

/// The PC's request to `/v2/profiles`: the profiles to add on the phone.
String encodeProfileRequest(List<NewSyncProfile> create) => jsonEncode({
      'create': [
        for (final profile in create)
          {'name': profile.name, 'color': profile.color},
      ],
    });

/// Reads [encodeProfileRequest]. Anything that isn't a profile is left out.
List<NewSyncProfile> decodeProfileRequest(String text) {
  Object? data;
  try {
    data = jsonDecode(text);
  } on FormatException {
    data = null;
  }
  final list = data is Map ? data['create'] : null;
  if (list is! List) return const [];
  return [
    for (final item in list.take(maxSyncProfiles))
      if (item is Map &&
          item['name'] is String &&
          (item['name'] as String).trim().isNotEmpty &&
          (item['name'] as String).length <= 60)
        (
          name: (item['name'] as String).trim(),
          color: item['color'] is int ? item['color'] as int : 0,
        ),
  ];
}

String _nameKey(String name) => name.trim().toLowerCase();

/// Which PC profile syncs with which phone profile, kept on the PC.
class ProfileLinks {
  const ProfileLinks({
    this.links = const {},
    this.leftOnPc = const {},
    this.leftOnPhone = const {},
  });

  /// PC profile id to phone profile id.
  final Map<String, String> links;

  /// PC profiles whose phone profile was removed: not added to the phone
  /// again.
  final Set<String> leftOnPc;

  /// Phone profiles whose PC profile was removed: not added to this PC
  /// again.
  final Set<String> leftOnPhone;

  bool get isEmpty => links.isEmpty && leftOnPc.isEmpty && leftOnPhone.isEmpty;

  String toJson() => jsonEncode({
        'links': links,
        'leftOnPc': leftOnPc.toList(),
        'leftOnPhone': leftOnPhone.toList(),
      });

  static ProfileLinks fromJson(String? text) {
    if (text == null) return const ProfileLinks();
    try {
      final data = jsonDecode(text);
      if (data is! Map) return const ProfileLinks();
      final links = data['links'];
      Set<String> ids(Object? list) => {
            if (list is List)
              for (final item in list)
                if (item is String) item,
          };
      return ProfileLinks(
        links: {
          if (links is Map)
            for (final entry in links.entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
        },
        leftOnPc: ids(data['leftOnPc']),
        leftOnPhone: ids(data['leftOnPhone']),
      );
    } on FormatException {
      return const ProfileLinks();
    }
  }
}

/// What a sync does with the profiles on both sides.
class ProfileLinkPlan {
  const ProfileLinkPlan({
    required this.links,
    required this.createOnPhone,
    required this.createOnPc,
  });

  /// Which profiles sync together, kept for next time.
  final ProfileLinks links;

  /// PC profiles the phone does not have yet.
  final List<SyncProfileInfo> createOnPhone;

  /// Phone profiles this PC does not have yet.
  final List<SyncProfileInfo> createOnPc;
}

/// Pairs up the profiles of the PC ([pc]) and the phone ([phone]): the pairs
/// from last time ([saved]) first, then profiles with the same name, then
/// the first profile on each side. A profile left over is added on the
/// other device, unless it has a PIN (it is never copied) or its partner
/// was removed there.
ProfileLinkPlan planProfileLinks({
  required List<SyncProfileInfo> pc,
  required List<SyncProfileInfo> phone,
  ProfileLinks saved = const ProfileLinks(),
}) {
  final pcIds = {for (final profile in pc) profile.id};
  final phoneIds = {for (final profile in phone) profile.id};
  final links = <String, String>{};
  final leftOnPc = <String>{
    for (final id in saved.leftOnPc)
      if (pcIds.contains(id)) id,
  };
  final leftOnPhone = <String>{
    for (final id in saved.leftOnPhone)
      if (phoneIds.contains(id)) id,
  };
  // Pairs from last time. One whose partner is gone stays unpaired, and is
  // not added again on the side it was removed from.
  for (final entry in saved.links.entries) {
    final pcThere = pcIds.contains(entry.key);
    final phoneThere = phoneIds.contains(entry.value);
    if (pcThere && phoneThere) {
      if (!links.containsValue(entry.value)) links[entry.key] = entry.value;
    } else if (pcThere) {
      leftOnPc.add(entry.key);
    } else if (phoneThere) {
      leftOnPhone.add(entry.value);
    }
  }
  bool pcFree(String id) => !links.containsKey(id) && !leftOnPc.contains(id);
  bool phoneFree(String id) =>
      !links.containsValue(id) && !leftOnPhone.contains(id);
  // The same name on both sides.
  for (final p in pc) {
    if (!pcFree(p.id)) continue;
    for (final q in phone) {
      if (phoneFree(q.id) && _nameKey(q.name) == _nameKey(p.name)) {
        links[p.id] = q.id;
        break;
      }
    }
  }
  // The first profile on each side: your own library.
  const main = 'main';
  if (pcIds.contains(main) &&
      phoneIds.contains(main) &&
      pcFree(main) &&
      phoneFree(main)) {
    links[main] = main;
  }
  final phoneNames = {for (final q in phone) _nameKey(q.name)};
  final pcNames = {for (final p in pc) _nameKey(p.name)};
  return ProfileLinkPlan(
    links: ProfileLinks(
      links: links,
      leftOnPc: leftOnPc,
      leftOnPhone: leftOnPhone,
    ),
    createOnPhone: [
      for (final p in pc)
        if (pcFree(p.id) && !p.locked && !phoneNames.contains(_nameKey(p.name)))
          p,
    ],
    createOnPc: [
      for (final q in phone)
        if (phoneFree(q.id) &&
            !q.locked &&
            !pcNames.contains(_nameKey(q.name)))
          q,
    ],
  );
}
