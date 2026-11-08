import 'dart:convert';

// Windows app only.

/// A phone this PC is paired with. The first one is kept where a single
/// pairing was always kept (id is empty); phones paired after it are in the
/// list below.
class SyncPhone {
  const SyncPhone({required this.id, required this.name, required this.address});

  /// Empty for the first phone.
  final String id;
  final String name;

  /// Such as 192.168.1.20:8765.
  final String address;

  SyncPhone copyWith({String? name, String? address}) => SyncPhone(
        id: id,
        name: name ?? this.name,
        address: address ?? this.address,
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'address': address};

  static SyncPhone? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final address = json['address'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || address is! String) return null;
    return SyncPhone(id: id, name: name, address: address);
  }
}

/// The phones after the first, as saved.
List<SyncPhone> decodeSyncPhones(String? text) {
  if (text == null || text.isEmpty) return const [];
  try {
    final data = jsonDecode(text);
    if (data is! List) return const [];
    return [
      for (final item in data) ?SyncPhone.fromJson(item),
    ];
  } catch (_) {
    return const [];
  }
}

String encodeSyncPhones(List<SyncPhone> phones) =>
    jsonEncode([for (final phone in phones) phone.toJson()]);

/// A name for the next phone: "Phone 2", "Phone 3", and so on.
String nextPhoneName(List<String> taken) {
  var number = taken.length + 1;
  while (taken.contains('Phone $number')) {
    number++;
  }
  return 'Phone $number';
}

/// An id for a phone that is not used yet: p2, p3, and so on.
String nextPhoneId(Iterable<String> taken) {
  var number = 2;
  while (taken.contains('p$number')) {
    number++;
  }
  return 'p$number';
}

/// The file a phone's last-synced copy of a profile is kept in. The first
/// phone keeps the name used before there could be several.
String syncBaseFileName(String phone) =>
    phone.isEmpty ? 'sync_base.json' : 'sync_base.$phone.json';

/// The key the links between profiles are kept under.
String syncLinksKey(String phone) => phone.isEmpty ? 'syncLinks' : 'syncLinks.$phone';
