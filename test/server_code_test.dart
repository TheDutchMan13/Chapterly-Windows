import 'package:chapterly/data/server_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseServerCode', () {
    test('reads a valid code', () {
      final code = parseServerCode('chapterly-server:1|100.72.125.106:8780|aB3_-.~x');
      expect(code?.address, '100.72.125.106:8780');
      expect(code?.token, 'aB3_-.~x');
    });

    test('reads a host name', () {
      expect(parseServerCode('chapterly-server:1|my-pc.local:1|t')?.address,
          'my-pc.local:1');
    });

    test('ignores whitespace around the code', () {
      final code = parseServerCode('  \nchapterly-server:1|10.0.0.2:8780|tok\r\n ');
      expect(code?.address, '10.0.0.2:8780');
      expect(code?.token, 'tok');
    });

    test('rejects a wrong prefix or version', () {
      expect(parseServerCode('chapterly-pair:1|10.0.0.2:8780|tok'), isNull);
      expect(parseServerCode('chapterly-server:2|10.0.0.2:8780|tok'), isNull);
      expect(parseServerCode('chapterly-server:|10.0.0.2:8780|tok'), isNull);
      expect(parseServerCode('10.0.0.2:8780|tok'), isNull);
      expect(parseServerCode(''), isNull);
    });

    test('rejects a missing part', () {
      expect(parseServerCode('chapterly-server:1|10.0.0.2:8780'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:8780|'), isNull);
      expect(parseServerCode('chapterly-server:1||tok'), isNull);
      expect(parseServerCode('chapterly-server:1|:8780|tok'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2|tok'), isNull);
    });

    test('rejects a bad port', () {
      expect(parseServerCode('chapterly-server:1|10.0.0.2:0|tok'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:65536|tok'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:99999999|tok'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:80a|tok'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:-1|tok'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:65535|tok')?.address,
          '10.0.0.2:65535');
    });

    test('rejects an empty or odd token', () {
      expect(parseServerCode('chapterly-server:1|10.0.0.2:8780| '), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:8780|a b'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:8780|a/b'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:8780|a+b='), isNull);
    });

    test('rejects extra pipes', () {
      expect(parseServerCode('chapterly-server:1|10.0.0.2:8780|tok|more'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2:8780|to|k'), isNull);
    });

    test('rejects spaces, schemes and slashes in the address', () {
      expect(parseServerCode('chapterly-server:1|10.0.0.2 :8780|tok'), isNull);
      expect(parseServerCode('chapterly-server:1| 10.0.0.2:8780|tok'), isNull);
      expect(parseServerCode('chapterly-server:1|http://10.0.0.2:8780|tok'), isNull);
      expect(parseServerCode('chapterly-server:1|10.0.0.2/x:8780|tok'), isNull);
    });
  });
}
