/// Finds glossary words inside case text so they can be tapped for their definition (finance cases only).
///
/// Matching rules: longest name first ("earnings per share" beats "earnings"); whole words only; acronyms and
/// short capitalised names ("GDP", "AUC", "Fed", "PM") must match their exact case so "fed" or "pm" in ordinary
/// prose is left alone; everything else ignores case. Each word is linked once per text block.
library;

import 'course.dart';

sealed class LinkPiece {
  const LinkPiece(this.text);
  final String text;
}

class PlainPiece extends LinkPiece {
  const PlainPiece(super.text);
}

class TermPiece extends LinkPiece {
  const TermPiece(super.text, this.term);
  final GlossaryTerm term;
}

class TermLinker {
  TermLinker(Course course) {
    final entries = <({String name, GlossaryTerm term})>[
      for (final t in course.terms)
        for (final n in t.names)
          if (!n.contains('(')) (name: n, term: t),
    ]..sort((a, b) => b.name.length.compareTo(a.name.length));
    final seen = <String>{};
    for (final e in entries) {
      final key = e.name.toLowerCase();
      if (!seen.add('${_caseSensitive(e.name)}|$key')) continue;
      final pattern = RegExp('(?<![A-Za-z0-9])${RegExp.escape(e.name)}(?![A-Za-z0-9])', caseSensitive: _caseSensitive(e.name));
      _rules.add((re: pattern, term: e.term));
    }
  }

  final List<({RegExp re, GlossaryTerm term})> _rules = [];

  /// Proper nouns and acronyms keep their case: any capital after the first letter ("the Fed", "Bank of England",
  /// "GDP", "BoE") or a short capitalised name ("Fed", "PM"). Plain words ("Equity", "yield curve") ignore case.
  static bool _caseSensitive(String name) {
    bool isUpper(int r) => r >= 65 && r <= 90;
    final runes = name.runes.toList();
    if (runes.skip(1).any(isUpper)) return true;
    return name.length <= 3 && runes.isNotEmpty && isUpper(runes.first);
  }

  /// Splits [text] into plain pieces and linked words. Words whose ids are in [linked] are not linked again;
  /// newly linked ids are added to it, so one set can span several pieces of the same block.
  List<LinkPiece> split(String text, {Set<String>? linked}) {
    // Every match of a longer name claims its span, even when the word was already linked, so a shorter word
    // never matches inside it ("asset" inside a second "asset manager"). Only the first claim per word links.
    final taken = <(int, int, GlossaryTerm, bool)>[];
    linked ??= <String>{};
    final claims = <(int, int, GlossaryTerm)>[];
    for (final r in _rules) {
      for (final m in r.re.allMatches(text)) {
        if (claims.any((t) => m.start < t.$2 && m.end > t.$1)) continue;
        claims.add((m.start, m.end, r.term));
      }
    }
    claims.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (s, e, term) in claims) {
      taken.add((s, e, term, linked.add(term.id)));
    }
    final out = <LinkPiece>[];
    var pos = 0;
    for (final (s, e, term, link) in taken) {
      if (!link) continue;
      if (s > pos) out.add(PlainPiece(text.substring(pos, s)));
      out.add(TermPiece(text.substring(s, e), term));
      pos = e;
    }
    if (pos < text.length) out.add(PlainPiece(text.substring(pos)));
    return out;
  }
}
