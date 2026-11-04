import 'dart:math';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/pin_lock.dart';
import 'package:chapterly/data/profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the library from before profiles becomes the first profile', () async {
    SharedPreferences.setMockInitialValues({'accent': 0xFF123456});
    final store = await ProfileStore.load();
    expect(store.profiles, hasLength(1));
    expect(store.active.id, mainProfileId);
    expect(store.active.name, 'Me');
    final settings = await AppSettings.load(store.scope(mainProfileId));
    expect(settings.accent, 0xFF123456);
  });

  test('each profile has its own settings', () async {
    SharedPreferences.setMockInitialValues({'accent': 0xFF123456});
    final store = await ProfileStore.load();
    final anna = await store.add('Anna', random: Random(1));
    final annaSettings = await AppSettings.load(store.scope(anna.id));
    expect(annaSettings.accent, AppSettings.defaultAccent);
    annaSettings.setAccent(0xFF654321);
    final mine = await AppSettings.load(store.scope(mainProfileId));
    expect(mine.accent, 0xFF123456);
    final again = await AppSettings.load(store.scope(anna.id));
    expect(again.accent, 0xFF654321);
    expect(store.scope(mainProfileId).getKeys(), {'accent'});
    expect(store.scope(anna.id).getKeys(), containsAll(['accent', 'display']));
  });

  test('the open profile is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProfileStore.load();
    final anna = await store.add('Anna', random: Random(2));
    await store.setActive(anna.id);
    final reloaded = await ProfileStore.load();
    expect(reloaded.active.id, anna.id);
    expect(reloaded.profiles.map((p) => p.name), ['Me', 'Anna']);
  });

  test('names must be filled in and different', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await ProfileStore.load();
    await store.add('Anna', random: Random(3));
    expect(store.nameProblem(''), isNotNull);
    expect(store.nameProblem(' anna '), isNotNull);
    expect(store.nameProblem('Sam'), isNull);
    expect(store.nameProblem('Me', exceptId: mainProfileId), isNull);
  });

  test('removing a profile removes only its settings', () async {
    SharedPreferences.setMockInitialValues({'accent': 1});
    final store = await ProfileStore.load();
    final anna = await store.add('Anna', random: Random(4));
    await store.scope(anna.id).setInt('accent', 2);
    await expectLater(store.remove(mainProfileId), throwsStateError);
    await store.remove(anna.id);
    expect(store.profiles, hasLength(1));
    expect(store.scope(anna.id).getKeys(), isEmpty);
    expect(store.scope(mainProfileId).getInt('accent'), 1);
  });

  test('a PIN belongs to one profile', () async {
    const salt = 'salt';
    SharedPreferences.setMockInitialValues({
      'pinSalt': salt,
      'pinHash': hashPin('1234', salt),
    });
    final store = await ProfileStore.load();
    final anna = await store.add('Anna', random: Random(5));
    expect(store.hasPin(mainProfileId), isTrue);
    expect(store.checkPin(mainProfileId, '1234'), isTrue);
    expect(store.checkPin(mainProfileId, '0000'), isFalse);
    expect(store.hasPin(anna.id), isFalse);
  });
}
