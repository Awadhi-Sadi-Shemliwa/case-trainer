/// Minimal Claude Messages API client over raw HTTP (Dart has no official Anthropic SDK).
///
/// The API key comes from Settings (stored on the phone) or, failing that, from the build:
/// `flutter build apk --dart-define-from-file=secrets.json` with `{"ANTHROPIC_API_KEY": "..."}` in app/secrets.json,
/// which is git-ignored. The key is never written to the repo.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const builtInApiKey = String.fromEnvironment('ANTHROPIC_API_KEY');

/// Model and effort chosen 2026-11-16 (DECISIONS.md): the current default Opus at medium effort.
const examinerModel = 'claude-opus-5-5';

class ClaudeError implements Exception {
  const ClaudeError(this.kind, this.message);
  final ClaudeErrorKind kind;
  final String message;
  @override
  String toString() => 'ClaudeError(${kind.name}): $message';
}

enum ClaudeErrorKind { noKey, offline, auth, credit, rateLimit, overloaded, refusal, truncated, badResponse, other }

/// What a learner sees when the examiner is unavailable.
String explainClaudeError(ClaudeError e) => switch (e.kind) {
      ClaudeErrorKind.noKey => 'No Claude API key. Add one in Settings to have your answers graded.',
      ClaudeErrorKind.offline => 'No internet connection. Your answer is saved; tap "Grade now" when you are back online.',
      ClaudeErrorKind.auth => 'The Claude API key was refused. Paste a valid key in Settings.',
      ClaudeErrorKind.credit =>
        'The Claude API account has no credit left. Add credit at console.anthropic.com (Plans & Billing), then tap "Grade now".',
      ClaudeErrorKind.rateLimit => 'Too many requests just now. Wait a moment, then tap "Grade now".',
      ClaudeErrorKind.overloaded => 'The examiner is busy right now. Tap "Grade now" in a minute.',
      ClaudeErrorKind.refusal => 'The examiner declined to grade this answer. Rephrase it and submit again.',
      ClaudeErrorKind.truncated => 'The examiner ran out of room. Tap "Grade now" to try again.',
      ClaudeErrorKind.badResponse || ClaudeErrorKind.other => 'The examiner had a problem (${e.message}). Tap "Grade now" to retry.',
    };

class ClaudeReply {
  const ClaudeReply({required this.json, required this.model, required this.inputTokens, required this.outputTokens});
  final Map<String, dynamic> json;
  final String model;
  final int inputTokens;
  final int outputTokens;
}

class ClaudeClient {
  ClaudeClient({required this.apiKey, http.Client? httpClient, this.timeout = const Duration(seconds: 90)})
      : _http = httpClient ?? http.Client();

  /// Read on every request, so a key pasted in Settings takes effect at once.
  final String Function() apiKey;
  final http.Client _http;
  final Duration timeout;

  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  bool get hasKey => apiKey().trim().isNotEmpty;

  /// Settings' "Test the connection": one tiny graded-style request, so a missing credit balance shows up too.
  Future<String> checkKey() async {
    try {
      await json(
        system: 'Reply with the JSON requested.',
        user: 'Say ok.',
        schema: const {
          'type': 'object',
          'additionalProperties': false,
          'required': ['ok'],
          'properties': {'ok': {'type': 'boolean'}},
        },
        effort: 'low',
        maxTokens: 1000,
      );
      return 'The examiner is connected and ready.';
    } on ClaudeError catch (e) {
      return explainClaudeError(e);
    }
  }

  /// One request whose reply is JSON matching [schema] (structured outputs).
  Future<ClaudeReply> json({
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    String effort = 'medium',
    int maxTokens = 16000,
  }) async {
    final key = apiKey().trim();
    if (key.isEmpty) throw const ClaudeError(ClaudeErrorKind.noKey, 'no key');
    final body = {
      'model': examinerModel,
      'max_tokens': maxTokens,
      // On a safety decline the API retries on a suitable model inside the same call.
      'fallbacks': 'default',
      'system': system,
      'output_config': {
        'effort': effort,
        'format': {'type': 'json_schema', 'schema': schema},
      },
      'messages': [
        {'role': 'user', 'content': user},
      ],
    };
    final http.Response res;
    try {
      res = await _http
          .post(_endpoint,
              headers: {
                'content-type': 'application/json',
                'x-api-key': key,
                'anthropic-version': '2026-10-21',
                'anthropic-beta': 'server-side-fallback-2026-07-01',
              },
              body: jsonEncode(body))
          .timeout(timeout);
    } on SocketException catch (e) {
      throw ClaudeError(ClaudeErrorKind.offline, e.message);
    } on TimeoutException {
      throw const ClaudeError(ClaudeErrorKind.offline, 'timed out');
    } on http.ClientException catch (e) {
      throw ClaudeError(ClaudeErrorKind.offline, e.message);
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw ClaudeError(ClaudeErrorKind.badResponse, 'HTTP ${res.statusCode}, not JSON');
    }
    if (res.statusCode != 200) {
      final msg = ((data['error'] as Map?)?['message'] as String?) ?? 'HTTP ${res.statusCode}';
      final kind = switch (res.statusCode) {
        401 || 403 => ClaudeErrorKind.auth,
        429 => ClaudeErrorKind.rateLimit,
        529 || 503 => ClaudeErrorKind.overloaded,
        400 when msg.toLowerCase().contains('credit balance') => ClaudeErrorKind.credit,
        _ => ClaudeErrorKind.other,
      };
      throw ClaudeError(kind, msg);
    }
    final stop = data['stop_reason'];
    if (stop == 'refusal') throw const ClaudeError(ClaudeErrorKind.refusal, 'refusal');
    if (stop == 'max_tokens') throw const ClaudeError(ClaudeErrorKind.truncated, 'max_tokens');
    final text = [
      for (final b in (data['content'] as List? ?? const []))
        if ((b as Map)['type'] == 'text') b['text'] as String
    ].join();
    final Map<String, dynamic> out;
    try {
      out = jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      throw const ClaudeError(ClaudeErrorKind.badResponse, 'reply was not JSON');
    }
    final usage = (data['usage'] as Map?) ?? const {};
    return ClaudeReply(
      json: out,
      model: data['model'] as String? ?? examinerModel,
      inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }
}
