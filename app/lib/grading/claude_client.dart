/// Minimal Claude Messages API client over raw HTTP (Dart has no official Anthropic SDK).
///
/// The API key comes from Settings (stored on the phone) or, failing that, from the build:
/// `flutter build apk --dart-define-from-file=secrets.json` with `{"ANTHROPIC_API_KEY": "..."}` in app/secrets.json,
/// which is git-ignored. The key is never written to the repo.
///
/// Budget rules (owner, 2026-11-16; docs/knowledge/API_USAGE.md): the right model per task, only the data needed,
/// automatic retry on rate limits, one request at a time, prompt caching for repeated material.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const builtInApiKey = String.fromEnvironment('ANTHROPIC_API_KEY');

/// Grading is reasoning: Sonnet 5.5 (owner rule: "reserve Sonnet for complex reasoning").
const graderModel = 'claude-sonnet-5-5';

/// Summaries, formatting and the connection test: Haiku 5.5 (owner rule: fast, cheap tasks).
const summaryModel = 'claude-haiku-5-5';

/// US$ per million tokens: input, output, cache read, cache write (5-minute TTL = 1.25 x input).
const modelPrices = <String, ({double input, double output, double cacheRead, double cacheWrite})>{
  graderModel: (input: 2.00, output: 10.00, cacheRead: 0.10, cacheWrite: 2.50),
  summaryModel: (input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite: 0.125),
};

/// Estimated cost of one call in US$ (unknown models priced as the grader).
double callCost(String model, {int input = 0, int output = 0, int cacheRead = 0, int cacheWrite = 0}) {
  final p = modelPrices[model] ?? modelPrices[model.startsWith('claude-haiku') ? summaryModel : graderModel]!;
  return (input * p.input + output * p.output + cacheRead * p.cacheRead + cacheWrite * p.cacheWrite) / 1e6;
}

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
      ClaudeErrorKind.rateLimit => 'Too many requests just now. Wait a minute, then tap "Grade now".',
      ClaudeErrorKind.overloaded => 'The examiner is busy right now. Tap "Grade now" in a minute.',
      ClaudeErrorKind.refusal => 'The examiner declined to grade this answer. Rephrase it and submit again.',
      ClaudeErrorKind.truncated => 'The examiner ran out of room. Tap "Grade now" to try again.',
      ClaudeErrorKind.badResponse || ClaudeErrorKind.other => 'The examiner had a problem (${e.message}). Tap "Grade now" to retry.',
    };

class ClaudeReply {
  const ClaudeReply({
    required this.json,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.retries = 0,
    this.elapsed = Duration.zero,
  });
  final Map<String, dynamic> json;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int retries;
  final Duration elapsed;

  double get cost => callCost(model, input: inputTokens, output: outputTokens, cacheRead: cacheReadTokens, cacheWrite: cacheWriteTokens);

  Map<String, dynamic> usageJson() => {
        'model': model, 'input_tokens': inputTokens, 'output_tokens': outputTokens,
        'cache_read_input_tokens': cacheReadTokens, 'cache_creation_input_tokens': cacheWriteTokens,
        'retries': retries, 'elapsed_ms': elapsed.inMilliseconds, 'cost_usd': cost,
      };
}

class ClaudeClient {
  ClaudeClient({
    required this.apiKey,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 90),
    this.maxRetries = 2,
    Future<void> Function(Duration)? sleep,
  })  : _http = httpClient ?? http.Client(),
        _sleep = sleep ?? Future<void>.delayed;

  /// Read on every request, so a key pasted in Settings takes effect at once.
  final String Function() apiKey;
  final http.Client _http;
  final Duration timeout;
  final int maxRetries;
  final Future<void> Function(Duration) _sleep;

  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  /// One request at a time across the whole app (Tier 1 limits are per minute; never burst).
  static Future<void> _tail = Future.value();

  bool get hasKey => apiKey().trim().isNotEmpty;

  /// Settings' "Test the connection": one tiny Haiku request, so a missing credit balance shows up too.
  Future<String> checkKey() async {
    try {
      await json(
        model: summaryModel,
        system: 'Reply with the JSON requested.',
        user: 'Say ok.',
        schema: const {
          'type': 'object',
          'additionalProperties': false,
          'required': ['ok'],
          'properties': {'ok': {'type': 'boolean'}},
        },
        effort: 'low',
        maxTokens: 300,
      );
      return 'The examiner is connected and ready.';
    } on ClaudeError catch (e) {
      return explainClaudeError(e);
    }
  }

  /// One request whose reply is JSON matching [schema] (structured outputs).
  /// [user] is a string or a list of content blocks (a block may carry `cache_control`).
  Future<ClaudeReply> json({
    required String model,
    required String system,
    required Object user,
    required Map<String, dynamic> schema,
    String effort = 'medium',
    int maxTokens = 8000,
  }) {
    final run = _tail.then((_) => _withRetries(model, system, user, schema, effort, maxTokens));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<ClaudeReply> _withRetries(String model, String system, Object user, Map<String, dynamic> schema, String effort, int maxTokens) async {
    final sw = Stopwatch()..start();
    for (var attempt = 0;; attempt++) {
      try {
        final r = await _once(model, system, user, schema, effort, maxTokens);
        return ClaudeReply(
          json: r.json, model: r.model, inputTokens: r.inputTokens, outputTokens: r.outputTokens,
          cacheReadTokens: r.cacheReadTokens, cacheWriteTokens: r.cacheWriteTokens, retries: attempt, elapsed: sw.elapsed,
        );
      } on _Retryable catch (e) {
        if (attempt >= maxRetries) throw e.error;
        // Owner rule: wait a few seconds and try again instead of showing an error.
        final wait = e.retryAfter ?? Duration(seconds: 2 << attempt);
        await _sleep(wait > const Duration(seconds: 10) ? const Duration(seconds: 10) : wait);
      }
    }
  }

  Future<ClaudeReply> _once(String model, String system, Object user, Map<String, dynamic> schema, String effort, int maxTokens) async {
    final key = apiKey().trim();
    if (key.isEmpty) throw const ClaudeError(ClaudeErrorKind.noKey, 'no key');
    // Haiku 5.5 has no server-side refusal fallback; Sonnet 5.5 uses the "default" routing.
    final withFallback = !model.startsWith('claude-haiku');
    final body = {
      'model': model,
      'max_tokens': maxTokens,
      if (withFallback) 'fallbacks': 'default',
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
                if (withFallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
              },
              body: jsonEncode(body))
          .timeout(timeout);
    } on SocketException catch (e) {
      throw _Retryable(ClaudeError(ClaudeErrorKind.offline, e.message));
    } on TimeoutException {
      throw const ClaudeError(ClaudeErrorKind.offline, 'timed out');
    } on http.ClientException catch (e) {
      throw _Retryable(ClaudeError(ClaudeErrorKind.offline, e.message));
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      final e = ClaudeError(ClaudeErrorKind.badResponse, 'HTTP ${res.statusCode}, not JSON');
      if (res.statusCode >= 500) throw _Retryable(e);
      throw e;
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
      final e = ClaudeError(kind, msg);
      if (res.statusCode == 429 || res.statusCode >= 500) {
        final ra = int.tryParse(res.headers['retry-after'] ?? '');
        throw _Retryable(e, ra == null ? null : Duration(seconds: ra));
      }
      throw e;
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
    int u(String k) => (usage[k] as num?)?.toInt() ?? 0;
    return ClaudeReply(
      json: out,
      model: data['model'] as String? ?? model,
      inputTokens: u('input_tokens'),
      outputTokens: u('output_tokens'),
      cacheReadTokens: u('cache_read_input_tokens'),
      cacheWriteTokens: u('cache_creation_input_tokens'),
    );
  }
}

class _Retryable implements Exception {
  _Retryable(this.error, [this.retryAfter]);
  final ClaudeError error;
  final Duration? retryAfter;
}
