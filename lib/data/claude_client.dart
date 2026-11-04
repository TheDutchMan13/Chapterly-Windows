import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'profiles.dart';

/// The Claude model Chapterly uses unless you pick another: quick and
/// inexpensive, which is plenty for picking tags.
const defaultClaudeModel = 'claude-haiku-5-5';

const _endpoint = 'https://api.anthropic.com/v1/messages';

/// The Claude API version these requests are written for. Since this
/// version the API refuses temperature, top_p and top_k, so none are sent.
const claudeApiVersion = '2026-10-21';

/// Why a request to Claude did not work, in words for the screen.
class ClaudeFailure implements Exception {
  const ClaudeFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Claude answered, but the answer had no text Chapterly could read. Only
/// that book is affected: the rest can still be asked.
class ClaudeUnreadable implements Exception {
  const ClaudeUnreadable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sends one message at a time to Claude with your own API key.
class ClaudeClient {
  ClaudeClient({
    required this.apiKey,
    this.model = defaultClaudeModel,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  /// Claude's text answer to [prompt].
  Future<String> ask({
    required String system,
    required String prompt,
    int maxTokens = 300,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'authorization': 'Bearer $apiKey',
              'anthropic-version': claudeApiVersion,
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': maxTokens,
              'system': system,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const ClaudeFailure('Claude did not answer in time.');
    } on Exception {
      throw const ClaudeFailure('Could not reach Claude. Is this PC online?');
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw ClaudeFailure(_problem(response.statusCode, text));
    }
    Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      data = null;
    }
    final content = data is Map ? data['content'] : null;
    if (content is List) {
      final parts = [
        for (final block in content)
          if (block is Map && block['type'] == 'text' && block['text'] is String)
            block['text'] as String,
      ];
      if (parts.isNotEmpty) return parts.join();
    }
    final stop = data is Map ? data['stop_reason'] : null;
    throw ClaudeUnreadable(
      'Claude sent an answer Chapterly could not read'
      '${stop == null ? '' : ' (stop reason: $stop)'}.',
    );
  }

  String _problem(int status, String body) {
    String? detail;
    try {
      final data = jsonDecode(body);
      final error = data is Map ? data['error'] : null;
      if (error is Map && error['message'] is String) {
        detail = error['message'] as String;
      }
    } on FormatException {
      // No details.
    }
    final more = detail == null ? '' : ': $detail';
    return switch (status) {
      401 => 'Claude did not accept the API key. Check it in Settings.',
      403 => 'This API key may not use Claude$more.',
      404 => 'Claude does not know the model "$model"$more.',
      429 => 'Too many requests to Claude for now, or the account is out '
          'of credit. Try again later.',
      503 || 529 => 'Claude is busy. Try again in a minute.',
      _ => 'Claude answered with an error ($status)$more.',
    };
  }
}

/// Keeps your Claude API key in Windows' protected storage, like the
/// pairing code. Each profile has its own.
class ClaudeKeyStore {
  const ClaudeKeyStore({this.storageKey = _key});

  static const _key = 'chapterly_claude_key';

  /// The key store of the open profile. Set at start-up.
  static ClaudeKeyStore current = const ClaudeKeyStore();

  static String keyFor(String profileId) =>
      profileId == mainProfileId ? _key : '${_key}_$profileId';

  final String storageKey;

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  Future<String?> read() async {
    try {
      final value = await _storage.read(key: storageKey);
      return value == null || value.trim().isEmpty ? null : value.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key) =>
      _storage.write(key: storageKey, value: key.trim());

  Future<void> delete() => _storage.delete(key: storageKey);
}
