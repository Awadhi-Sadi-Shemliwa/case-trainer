/// Resolves `{expected.key}` and `{captured.name}` placeholders in authored text.
///
/// Spec §2: numbers shown in the app come only from the pipeline. Authored text never contains them;
/// it contains placeholders that are replaced here with `results.display` or the real captured output.
/// An unknown key throws, so a broken bundle fails loudly instead of showing a blank.
library;

import '../data/models.dart';

final placeholderRe = RegExp(r'\{(expected|captured)\.([a-z][a-z0-9_]*)\}');

sealed class Segment {
  const Segment();
}

class TextSegment extends Segment {
  const TextSegment(this.text);
  final String text;
}

/// A pipeline number (shown highlighted; tooltip = description).
class ValueSegment extends Segment {
  const ValueSegment(this.key, this.display, this.description);
  final String key;
  final String display;
  final String description;
}

/// Real printed output of pipeline code (shown as a code block).
class CapturedSegment extends Segment {
  const CapturedSegment(this.name, this.output);
  final String name;
  final String output;
}

class PlaceholderError implements Exception {
  PlaceholderError(this.message);
  final String message;
  @override
  String toString() => 'PlaceholderError: $message';
}

class Resolver {
  const Resolver(this.results, this.captured);
  final Map<String, ResultEntry> results;
  final Map<String, String> captured;

  List<Segment> segments(String text) {
    final out = <Segment>[];
    var pos = 0;
    for (final m in placeholderRe.allMatches(text)) {
      if (m.start > pos) out.add(TextSegment(text.substring(pos, m.start)));
      final kind = m.group(1)!;
      final key = m.group(2)!;
      if (kind == 'expected') {
        final r = results[key] ?? (throw PlaceholderError('unknown result key "$key"'));
        out.add(ValueSegment(key, r.display, r.description));
      } else {
        final c = captured[key] ?? (throw PlaceholderError('unknown captured output "$key"'));
        out.add(CapturedSegment(key, c));
      }
      pos = m.end;
    }
    if (pos < text.length) out.add(TextSegment(text.substring(pos)));
    return out;
  }

  /// Plain-text resolution (captured outputs inlined), e.g. for comparisons and exports.
  String plain(String text) => segments(text).map((s) => switch (s) {
        TextSegment(:final text) => text,
        ValueSegment(:final display) => display,
        CapturedSegment(:final output) => output,
      }).join();
}
