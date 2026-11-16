/// "I don't know" detection (owner request 2026-11-16): such an answer is a request for hints, not something to
/// grade. It counts as an attempt and climbs the same ladder (pointer + first hint, then every hint, then the
/// model answer). Checked locally, so no API call is spent on it.
library;

final _phrases = RegExp(
  r"\b(i\s*(do\s*n[o']?t|dont|dunno)\s*(know|understand|get it)|idk|no\s*idea|not\s*sure|no\s*clue|"
  r"have\s*no\s*idea|don'?t\s*understand|help|hint|pass|skip|nothing)\b",
  caseSensitive: false,
);

bool isNoAttempt(String answer) {
  final a = answer.trim();
  if (a.isEmpty) return true;
  // Only punctuation, e.g. "?" or "...".
  if (!RegExp(r'[A-Za-z0-9]').hasMatch(a)) return true;
  final words = a.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  // A long answer that merely contains "not sure" is still an answer: grade it.
  if (words <= 8 && _phrases.hasMatch(a)) return true;
  return words < 3;
}
