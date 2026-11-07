import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'text_cleaning.dart';

/// Summarises extracted text with Gemini, called straight from the phone
/// with the user's own key. Same model and prompt as the Pi reader
/// (server.py `generate_summary`).
class GeminiSummaryService {
  GeminiSummaryService({
    this._client,
    this.timeout = const Duration(seconds: 60),
  });

  final http.Client? _client;
  final Duration timeout;

  static const String model = 'gemini-2.5-flash';
  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent';

  /// The Pi's prompt, word for word.
  static String promptFor(String text) =>
      '''

You are helping a blind or visually impaired reader.

Summarize the following document in clear and simple language.

Rules:
- Preserve the important meaning.
- Include the important facts and ideas.
- Do not invent information.
- Do not add information that is not present.
- Keep it reasonably short.
- Make it natural and easy to understand when spoken aloud.
- Return only the summary.

DOCUMENT:

$text
''';

  /// Returns the cleaned summary. Throws [GeminiException] with a message
  /// the user can act on. The key travels only in the `x-goog-api-key`
  /// header — never in the URL — and is never logged.
  Future<String> summarize(String text, {required String apiKey}) async {
    if (text.trim().isEmpty) return '';
    final client = _client ?? http.Client();
    try {
      final http.Response res;
      try {
        res = await client
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': apiKey,
              },
              body: jsonEncode({
                'contents': [
                  {
                    'role': 'user',
                    'parts': [
                      {'text': promptFor(text)},
                    ],
                  },
                ],
              }),
            )
            .timeout(timeout);
      } on TimeoutException {
        throw const GeminiException(
          'Gemini took too long to answer.',
          shortReason: 'Gemini took too long',
        );
      } on SocketException {
        throw const GeminiException(
          'No internet connection for the AI summary.',
          shortReason: 'no internet connection',
        );
      } on http.ClientException {
        throw const GeminiException(
          'No internet connection for the AI summary.',
          shortReason: 'no internet connection',
        );
      }

      if (res.statusCode != 200) throw _errorFor(res);

      final Object? body;
      try {
        body = jsonDecode(res.body);
      } on FormatException {
        throw const GeminiException(
          'Gemini sent an unreadable answer.',
          shortReason: 'Gemini error',
        );
      }
      final summary = cleanOcrText(_textOf(body));
      if (summary.isEmpty) {
        throw const GeminiException(
          'Gemini returned an empty summary.',
          shortReason: 'Gemini returned nothing',
        );
      }
      return summary;
    } finally {
      if (_client == null) client.close();
    }
  }

  static String _textOf(Object? body) {
    if (body is! Map) return '';
    final candidates = body['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final content = (candidates.first as Map?)?['content'];
    final parts = (content is Map) ? content['parts'] : null;
    if (parts is! List) return '';
    return parts
        .whereType<Map>()
        .where((p) => p['thought'] != true)
        .map((p) => p['text'])
        .whereType<String>()
        .join();
  }

  static GeminiException _errorFor(http.Response res) {
    String? status;
    try {
      final err = (jsonDecode(res.body) as Map?)?['error'];
      if (err is Map) status = err['status'] as String?;
    } catch (_) {}
    final keyProblem =
        res.statusCode == 401 ||
        res.statusCode == 403 ||
        status == 'PERMISSION_DENIED' ||
        status == 'UNAUTHENTICATED' ||
        (res.statusCode == 400 && res.body.contains('API_KEY_INVALID'));
    if (keyProblem) {
      return const GeminiException(
        'Gemini rejected the API key. Check it in Settings.',
        keyRejected: true,
        shortReason: 'Gemini key not accepted',
      );
    }
    if (res.statusCode == 429) {
      return const GeminiException(
        'Gemini usage limit reached for this key. Try again later.',
        shortReason: 'Gemini limit reached',
      );
    }
    return GeminiException(
      'Gemini error (HTTP ${res.statusCode}).',
      shortReason: 'Gemini error',
    );
  }
}

class GeminiException implements Exception {
  const GeminiException(
    this.message, {
    this.keyRejected = false,
    this.shortReason = 'Gemini error',
  });
  final String message;
  final bool keyRejected;

  /// A few words for "Summary not available (...)".
  final String shortReason;
  @override
  String toString() => message;
}
