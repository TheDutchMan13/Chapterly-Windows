import 'package:chapterly/server/server_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ServerClient _clientAnswering(int status, String body) => ServerClient(
      address: Uri.parse('http://100.1.2.3:8780'),
      token: 'token',
      client: MockClient((_) async => http.Response(body, status)),
    );

Future<ServerFailure> _failure(int status, String body) async {
  try {
    await _clientAnswering(status, body).tracks('abc');
  } on ServerFailure catch (failure) {
    return failure;
  }
  throw StateError('Expected a ServerFailure');
}

void main() {
  test('a missing file says the file or folder may have moved', () async {
    final failure = await _failure(404, '{"detail":"The file is gone."}');
    expect(failure.notFound, isTrue);
    expect(failure.message, contains('cannot find this book'));
  });

  test('a folder that is not served says to check config.toml', () async {
    final failure = await _failure(
      404,
      '{"detail":"That book\'s folder is no longer served."}',
    );
    expect(failure.notFound, isTrue);
    expect(failure.message, contains('books_dirs'));
  });

  test('any other not-found still says the book is gone', () async {
    final failure = await _failure(404, '{"detail":"No such book."}');
    expect(failure.notFound, isTrue);
    expect(failure.message, 'That book is no longer on the server.');
    final plain = await _failure(404, 'Not Found');
    expect(plain.message, 'That book is no longer on the server.');
  });
}
