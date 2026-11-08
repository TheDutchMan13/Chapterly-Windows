import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_settings.dart';
import 'book_repository.dart';
import 'pc_sync.dart';
import 'profile_files.dart';
import 'profiles.dart';
import 'sqlite_book_store.dart';
import 'sync_phones.dart';
import 'sync_profiles.dart';
import 'sync_three_way.dart';

/// The profiles on this PC, for a sync of every profile with one pairing.
/// Another profile's library is opened only for its part of the sync.
class StoreSyncProfiles implements SyncProfileAccess {
  StoreSyncProfiles(this.store);

  final ProfileStore store;

  final _stores = <SyncTarget, SqliteBookStore>{};

  @override
  String get openId => store.active.id;

  @override
  List<SyncProfileInfo> list() => [
        for (final profile in store.profiles)
          SyncProfileInfo(
            id: profile.id,
            name: profile.name,
            color: profile.color,
            locked: profile.id != openId && store.hasPin(profile.id),
          ),
      ];

  @override
  Future<String?> create(String name, int color) async {
    if (store.profiles.length >= maxSyncProfiles) return null;
    if (store.nameProblem(name) != null) return null;
    final profile = await store.add(name);
    if (profileColors.contains(color)) await store.setColor(profile.id, color);
    return profile.id;
  }

  @override
  Future<SyncTarget> open(String id, {String phone = ''}) async {
    final dir = await profileDataDir(id);
    final books = await SqliteBookStore.open(p.join(dir.path, 'chapterly.db'));
    final repository = BookRepository(books);
    await repository.load();
    final target = SyncTarget(
      repository: repository,
      settings: await AppSettings.load(store.scope(id)),
      base: await SyncBase.load(
        File(p.join(dir.path, syncBaseFileName(phone))),
      ),
    );
    _stores[target] = books;
    return target;
  }

  @override
  Future<void> close(SyncTarget target) async {
    await _stores.remove(target)?.close();
  }

  /// Which profile here syncs with which on a phone, kept for the whole PC
  /// (see [deviceKeyStart]).
  @override
  ProfileLinks linksFor(String phone) =>
      ProfileLinks.fromJson(store.device.getString(syncLinksKey(phone)));

  @override
  Future<void> saveLinks(ProfileLinks links, {String phone = ''}) async {
    final key = syncLinksKey(phone);
    if (links.isEmpty) {
      await store.device.remove(key);
    } else {
      await store.device.setString(key, links.toJson());
    }
  }
}
