import 'package:tasuke_ai/features/tasks/domain/task.dart';

import 'when_parser.dart';

/// Turns a spoken clause into the title the Confirm card shows.
///
/// "Tomorrow at 3 PM send the build to James" → "Send the build to James".
final class TitleCleaner {
  const TitleCleaner();

  /// Cuts the temporal span out of [clause] and tidies what is left.
  ///
  /// [spans] is what [ParsedWhen.spans] returned; when it is null the single
  /// [matchStart]..[matchEnd] range is cut instead.
  ///
  /// Idempotent by construction — `clean(clean(x)) == clean(x)` — because the
  /// Confirm screen re-cleans whatever the user typed back into the field.
  String clean(
    String clause, {
    required int matchStart,
    required int matchEnd,
    List<MatchSpan>? spans,
  }) {
    String text = _cut(
      clause,
      spans ?? <MatchSpan>[MatchSpan(matchStart, matchEnd)],
    );
    text = text.replaceAll(_whitespace, ' ').trim();
    text = text.replaceAll(_strandedPunctuation, ' ').trim();

    String previous = '';
    while (previous != text) {
      previous = text;
      text = text.replaceFirst(_leadingFiller, '').trimLeft();
      text = text.replaceFirst(_leadingConnective, '').trimLeft();
      text = text.replaceFirst(_trailingPreposition, '').trimRight();
      text = text.replaceFirst(_trailingPunctuation, '').trimRight();
    }

    return TaskTitle.normalise(_sentenceCase(text));
  }

  /// Removes [spans] from [clause], leaving a space behind so that the words
  /// either side of the cut do not fuse.
  String _cut(String clause, List<MatchSpan> spans) {
    final List<MatchSpan> ordered =
        spans
            .where((MatchSpan s) => !s.isEmpty && s.start < clause.length)
            .map(
              (MatchSpan s) => MatchSpan(
                s.start.clamp(0, clause.length),
                s.end.clamp(0, clause.length),
              ),
            )
            .toList()
          ..sort((MatchSpan a, MatchSpan b) => b.start.compareTo(a.start));
    String out = clause;
    for (final MatchSpan span in ordered) {
      if (span.isEmpty) continue;
      out = '${out.substring(0, span.start)} ${out.substring(span.end)}';
    }
    return out;
  }

  /// Upper-cases the first letter without touching the rest, so "send the
  /// build to James" keeps James.
  String _sentenceCase(String text) {
    if (text.isEmpty) return text;
    final String head = String.fromCharCode(text.runes.first);
    final String upper = head.toUpperCase();
    // ⚠️ Not every character upper-cases to one character — German ß becomes
    // SS — and growing the string here would silently lengthen every title.
    if (upper == head || upper.length != head.length) return text;
    return '$upper${text.substring(head.length)}';
  }

  static final RegExp _whitespace = RegExp(r'\s+');

  /// What a cut leaves behind: " , ", " - ", stray brackets.
  static final RegExp _strandedPunctuation = RegExp(r'\s+[,;:–—-]+(?=\s|$)');

  /// The things people say before the task instead of the task.
  static final RegExp _leadingFiller = RegExp(
    r'^(?:please|remind me to|remind me|i need to|i needed to|i have to'
    r'|i gotta|do not forget to|make sure to|make sure you|make sure i'
    r'|i should|i must|i want to|lets'
    r"|don['\u2019]t forget to|don['\u2019]t forget|let['\u2019]s"
    r')(?:\s+|$)',
    caseSensitive: false,
  );

  static final RegExp _leadingConnective = RegExp(
    r'^(?:and|then|also|plus|but|so)\b[\s,]*',
    caseSensitive: false,
  );

  /// A preposition left dangling by the cut — `send the build to <tomorrow>`.
  static final RegExp _trailingPreposition = RegExp(
    r'(?:^|\s)(?:at|on|in|by|for|to|with|from|until|till|of|about|around'
    r'|before|after|and|then|also|plus|the|a|an|this|next|my|your)$',
    caseSensitive: false,
  );

  static final RegExp _trailingPunctuation = RegExp(r'[\s,;:.!–—-]+$');
}
