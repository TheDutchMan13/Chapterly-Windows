import 'package:chapterly/data/app_info.dart';
import 'package:chapterly/data/changelog.dart';
import 'package:flutter_test/flutter_test.dart';

// Kept so `flutter create` does not add its sample counter test here.
void main() {
  test('What\'s New starts with this version', () {
    expect(changelog.first.version, appVersion);
  });
}
