import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecrets implements SecretStore {
  final saved = <String, String>{};

  @override
  Future<String?> read(String name) async => saved[name];

  @override
  Future<void> write(String name, String value) async => saved[name] = value;

  @override
  Future<void> delete(String name) async => saved.remove(name);
}

void main() {
  test('keys move out of the settings file and stay out', () async {
    SharedPreferences.setMockInitialValues({
      'googleBooksKey': 'AIza-old',
      'hardcoverToken': 'hc-old',
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = await AppSettings.load(ScopedPrefs(prefs, ''));
    final secrets = _MemorySecrets();
    await settings.loadSecrets(secrets);

    expect(settings.googleBooksKey, 'AIza-old');
    expect(settings.hardcoverToken, 'hc-old');
    expect(secrets.saved,
        {'googleBooksKey': 'AIza-old', 'hardcoverToken': 'hc-old'});
    expect(prefs.getString('googleBooksKey'), isNull);
    expect(prefs.getString('hardcoverToken'), isNull);

    settings.setHardcoverToken('hc-new');
    settings.setGoogleBooksKey(null);
    await Future<void>.delayed(Duration.zero);
    expect(secrets.saved, {'hardcoverToken': 'hc-new'});
    expect(prefs.getString('hardcoverToken'), isNull);

    final again = await AppSettings.load(ScopedPrefs(prefs, ''));
    await again.loadSecrets(secrets);
    expect(again.hardcoverToken, 'hc-new');
    expect(again.googleBooksKey, isNull);
  });
}
