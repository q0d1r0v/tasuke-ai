import 'package:flutter_test/flutter_test.dart';

import 'native_source.dart';

/// Guards `ios/Runner/PrivacyInfo.xcprivacy`.
///
/// ⚠️ A missing or wrong privacy manifest is an **ITMS-91053** rejection at
/// upload — automatic, minutes after the upload finishes, before a human
/// reviewer ever sees the build, with no way to patch it except a new build
/// number. It is also the file most likely to be quietly dropped by a merge,
/// because nothing in a normal build references it.
void main() {
  late String manifest;

  setUpAll(() {
    manifest = stripXmlComments(
      readProjectFile('ios/Runner/PrivacyInfo.xcprivacy'),
    );
  });

  test('NSPrivacyTracking is false', () {
    expect(plistValue(manifest, 'NSPrivacyTracking'), '<false/>');
  });

  test('NSPrivacyTrackingDomains is empty', () {
    // huggingface.co is deliberately NOT listed: a tracking domain is blocked
    // when "Allow Apps to Request to Track" is off, which would break the model
    // download — i.e. first launch — for a large share of users.
    final String? value = plistValue(manifest, 'NSPrivacyTrackingDomains');
    expect(value, isNotNull);
    expect(value!.contains('<string>'), isFalse);
  });

  test('NSPrivacyCollectedDataTypes is present and empty', () {
    // ⚠️ Present AND empty, not omitted. To a reader they look the same; to
    // Apple's validator the empty array is the positive statement "we collect
    // nothing", which is what this app is claiming everywhere else.
    expect(plistHasKey(manifest, 'NSPrivacyCollectedDataTypes'), isTrue);
    final String? value = plistValue(manifest, 'NSPrivacyCollectedDataTypes');
    expect(value, isNotNull);
    expect(value!.contains('<dict>'), isFalse);
  });

  group('required-reason APIs', () {
    test('declares exactly three categories', () {
      final List<String> categories = RegExp(
        r'<string>(NSPrivacyAccessedAPICategory\w+)</string>',
      ).allMatches(manifest).map((RegExpMatch m) => m.group(1)!).toList();

      expect(categories, <String>[
        'NSPrivacyAccessedAPICategoryUserDefaults',
        'NSPrivacyAccessedAPICategoryFileTimestamp',
        'NSPrivacyAccessedAPICategoryDiskSpace',
      ]);
    });

    test('declares exactly the three reason codes, and no others', () {
      // Each code is the narrowest one that is true:
      //   CA92.1 — UserDefaults, this app only (no app group).
      //   3B52.1 — file timestamps inside our own container.
      //   E174.1 — free space GATES the model download; 85F4.1 would mean we
      //            display the number to the user, which we do not.
      final List<String> reasons = RegExp(r'<string>([0-9A-Z]{4}\.\d)</string>')
          .allMatches(manifest)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();

      expect(reasons, <String>['CA92.1', '3B52.1', 'E174.1']);
    });
  });

  test('is in the Runner target Copy Bundle Resources phase', () {
    // A manifest that exists in the repo but is not in the built .app does
    // nothing at all, and the repo looks correct while the upload is rejected.
    final String pbxproj = readProjectFile(
      'ios/Runner.xcodeproj/project.pbxproj',
    );
    expect(
      pbxproj,
      contains('PrivacyInfo.xcprivacy in Resources'),
      reason: 'add PrivacyInfo.xcprivacy to the Runner target resources',
    );
  });
}
