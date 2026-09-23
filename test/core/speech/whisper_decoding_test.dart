import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/speech/whisper_decoding.dart';

/// The prompt whisper is primed with. Every rule here is a regression the voice
/// eval (test/asr/asr_eval_test.dart) measured, not a style preference.
void main() {
  test('the prompt is exactly the names list', () {
    // Spelt out as a constant for the default argument; the list is what
    // people edit. Drifting apart would ship a list nobody reviewed.
    expect(whisperNamesPrompt, '${uzbekGivenNames.join(', ')}.');
  });

  test('the names are thirty distinct, capitalised, apostrophe-free words', () {
    expect(uzbekGivenNames, hasLength(30));
    expect(uzbekGivenNames.toSet(), hasLength(uzbekGivenNames.length));
    for (final String name in uzbekGivenNames) {
      expect(name, matches(RegExp(r'^[A-Z][a-z]+$')), reason: name);
    }
  });

  test('the prompt holds no clock time, no digit and no sentence', () {
    // ⚠️ A prompt with "9 a.m." in it made whisper write a.m./p.m. after bare
    // hours the speaker never qualified, and a to-do sentence did the same:
    // "at 10" became "at 10pm", which moves the task to the evening.
    expect(whisperNamesPrompt, isNot(matches(RegExp(r'\d'))));
    expect(
      whisperNamesPrompt.toLowerCase(),
      isNot(matches(RegExp(r'\b[ap]\.?\s?m\b'))),
    );
    // One list, one full stop: whisper copies a prompt's sentence breaks, and
    // a break where the note had a comma splits one task into two.
    expect('.'.allMatches(whisperNamesPrompt), hasLength(1));
    expect(whisperNamesPrompt, endsWith('.'));
  });

  test('the prompt stays short', () {
    // Every prompt token is decoded against the full encoder output on the
    // final pass; 30 names cost +13% of that pass on the eval host. A list
    // twice as long would cost about twice that, and whisper keeps at most
    // 224 prompt tokens anyway.
    expect(whisperNamesPrompt.length, lessThan(300));
  });

  test('the app primes the final pass only', () {
    expect(WhisperDecoding.app.initialPrompt, whisperNamesPrompt);
    expect(WhisperDecoding.app.promptOnPreviews, isFalse);
    expect(WhisperDecoding.unprimed.initialPrompt, isNull);
  });
}
