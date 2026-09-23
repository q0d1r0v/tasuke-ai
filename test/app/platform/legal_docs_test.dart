import 'package:flutter_test/flutter_test.dart';

import 'native_source.dart';

/// Keeps the bundled legal Markdown (`assets/legal/`) and the web HTML
/// (`store/`) the same document.
///
/// ⚠️ A reviewer reads the HTML on the web and a user reads the Markdown in the
/// binary. When only one is edited, the policy Apple and Google were shown stops
/// matching the one the app ships.
void main() {
  for (final (String markdown, String page) in <(String, String)>[
    ('assets/legal/privacy_en.md', 'store/privacy-policy.html'),
    ('assets/legal/terms_en.md', 'store/terms.html'),
  ]) {
    test('$markdown and $page say the same thing', () {
      expect(
        _htmlText(readProjectFile(page)),
        _markdownText(readProjectFile(markdown)),
        reason: 'edit both files, not one',
      );
    });
  }

  test('the privacy policy promises no model download', () {
    // Extraction is rule-based and the speech model is bundled, so nothing is
    // fetched on first launch. A policy that still says so is false.
    for (final String path in <String>[
      'assets/legal/privacy_en.md',
      'store/privacy-policy.html',
    ]) {
      final String text = readProjectFile(path);
      expect(text, isNot(contains('huggingface.co')), reason: path);
      expect(text, isNot(contains('219 MB')), reason: path);
    }
  });
}

/// The words of a legal Markdown file, without its markup.
String _markdownText(String source) => _words(
  source
      .replaceAll(RegExp(r'^#+ |^- ', multiLine: true), '')
      .replaceAll(RegExp(r'[*`]'), ''),
);

/// The words inside `<main>`, without tags or entities.
String _htmlText(String source) {
  final String main = RegExp(r'<main>([\s\S]*)</main>')
      .firstMatch(source)!
      .group(1)!;
  return _words(
    main
        // Block tags separate words; inline ones (strong, em, code) do not.
        .replaceAll(RegExp(r'</?(p|h\d|ul|ol|li)\b[^>]*>'), ' ')
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&'),
  );
}

String _words(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
