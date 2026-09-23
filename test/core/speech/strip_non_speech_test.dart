import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/core/speech/whisper_speech_recognizer.dart';

/// whisper's annotations must never become task text.
void main() {
  test('a trailing blank-audio marker is removed', () {
    // From the device, on an otherwise perfect transcript of the JFK clip.
    expect(
      stripNonSpeech('ask what you can do for your country. [BLANK_AUDIO]'),
      'ask what you can do for your country.',
    );
  });

  test('speech outside the model language leaves nothing behind', () {
    // ⚠️ From the device. base.en heard Uzbek and wrote this, and the app
    // used to make it a task title. Empty is what makes the pipeline say
    // "We didn't catch that" without spending one of the day's captures.
    expect(stripNonSpeech('(speaking in foreign language)'), isEmpty);
  });

  test('every bracket and paren annotation goes, whatever it says', () {
    expect(
      stripNonSpeech('[MUSIC] call Dad (laughing) at 5 pm [NOISE]'),
      'call Dad at 5 pm',
    );
  });

  test('ordinary speech is left exactly as it was', () {
    const String note = 'Tomorrow at 3 PM send the build to James';
    expect(stripNonSpeech(note), note);
  });

  test('whitespace left by a removed span is collapsed', () {
    expect(stripNonSpeech('  call   [BLANK_AUDIO]  Dad  '), 'call Dad');
  });
}
