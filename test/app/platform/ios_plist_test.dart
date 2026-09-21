import 'package:flutter_test/flutter_test.dart';

import 'native_source.dart';

/// Guards `ios/Runner/Info.plist`, `ios/Podfile` and the deployment target in
/// `ios/Runner.xcodeproj/project.pbxproj`.
///
/// There is no Xcode on this machine, so nothing here has ever been compiled.
/// These assertions are the substitute, and they cover the two iOS failures
/// that cost the most: a missing usage description (a hard crash on device,
/// not a denial) and a deployment target that disagrees between CocoaPods and
/// Xcode (a link error that names a symbol, not a setting).
void main() {
  late String plist;
  late String podfile;
  late String pbxproj;

  setUpAll(() {
    // Comments are stripped because Info.plist documents, by name, every key it
    // deliberately does not declare. Matching those explanations would fail the
    // file for being well documented.
    plist = stripXmlComments(readProjectFile('ios/Runner/Info.plist'));
    podfile = readProjectFile('ios/Podfile');
    pbxproj = readProjectFile('ios/Runner.xcodeproj/project.pbxproj');
  });

  group('required keys', () {
    test('NSMicrophoneUsageDescription is present and meaningful', () {
      // ⚠️ Missing, this is not a permission denial — it is an uncatchable
      // NSInvalidArgumentException the first time the mic is touched, on a real
      // device, which here is the first thing a reviewer does.
      final String? value = plistValue(plist, 'NSMicrophoneUsageDescription');
      expect(value, isNotNull);
      expect(value!.trim(), isNotEmpty);
      expect(
        value.length,
        greaterThan(30),
        reason:
            'the string is shown verbatim in the system prompt and has to '
            'answer "why", not just say "microphone"',
      );
    });

    test('ITSAppUsesNonExemptEncryption is false', () {
      // Answers the export-compliance questionnaire at build time. Omitted,
      // every single upload stops and waits for a human.
      expect(plistValue(plist, 'ITSAppUsesNonExemptEncryption'), '<false/>');
    });

    test('CFBundleDisplayName is Tasuke AI', () {
      expect(plistValue(plist, 'CFBundleDisplayName'), 'Tasuke AI');
    });

    test('CFBundleURLTypes registers the tasuke:// scheme', () {
      expect(plistHasKey(plist, 'CFBundleURLTypes'), isTrue);
      expect(plist, contains('<string>tasuke</string>'));
    });

    test('FlutterDeepLinkingEnabled is true', () {
      expect(plistValue(plist, 'FlutterDeepLinkingEnabled'), '<true/>');
    });

    test('CADisableMinimumFrameDurationOnPhone is true', () {
      expect(
        plistValue(plist, 'CADisableMinimumFrameDurationOnPhone'),
        '<true/>',
      );
    });

    test('is portrait-only on both idioms', () {
      for (final String key in <String>[
        'UISupportedInterfaceOrientations',
        'UISupportedInterfaceOrientations~ipad',
      ]) {
        final String? value = plistValue(plist, key);
        expect(value, isNotNull, reason: '$key is missing');
        // Omitting the ~ipad key does not inherit the iPhone list — it falls
        // back to all four orientations.
        expect(
          RegExp('<string>').allMatches(value!).length,
          1,
          reason: '$key must list Portrait and nothing else',
        );
        expect(value, contains('UIInterfaceOrientationPortrait'));
      }
    });
  });

  group('keys that must NOT be present', () {
    test('no NSSpeechRecognitionUsageDescription', () {
      // Apple's Speech framework is not used; whisper.cpp is. Declaring the key
      // advertises a capability the binary does not contain.
      expect(
        plistHasKey(plist, 'NSSpeechRecognitionUsageDescription'),
        isFalse,
      );
    });

    test('no photos, location, calendar or contacts usage strings', () {
      // The permission_handler post_install hook in ios/Podfile compiles those
      // handlers out of the pod, which is what makes their absence here safe
      // rather than a latent crash.
      for (final String key in <String>[
        'NSPhotoLibraryUsageDescription',
        'NSPhotoLibraryAddUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'NSLocationAlwaysAndWhenInUseUsageDescription',
        'NSCalendarsUsageDescription',
        'NSRemindersUsageDescription',
        'NSContactsUsageDescription',
        'NSMotionUsageDescription',
        'NSBluetoothAlwaysUsageDescription',
      ]) {
        expect(
          plistHasKey(plist, key),
          isFalse,
          reason: '$key must not appear',
        );
      }
    });

    test('no NSUserTrackingUsageDescription', () {
      // There is no IDFA, no ad SDK and no attribution. The key would make App
      // Store Connect ask us to declare tracking we do not do.
      expect(plistHasKey(plist, 'NSUserTrackingUsageDescription'), isFalse);
    });

    test('no UIBackgroundModes', () {
      // ⚠️ The most tempting key here and the one that gets an app rejected.
      // Recording is modal and foreground; reminders are local notifications
      // the OS delivers with the app terminated. An unused background mode is
      // guideline 2.5.4.
      expect(plistHasKey(plist, 'UIBackgroundModes'), isFalse);
    });
  });

  group('deployment target 16.4', () {
    test('the Podfile pins it', () {
      // 16.4 is llamadart's floor.
      expect(podfile, contains("platform :ios, '16.4'"));
    });

    test('the Podfile sweeps every pod target in post_install', () {
      // `platform :ios` sets the floor for resolution only; a transitive pod
      // still shipping an 11.0 podspec fails the whole archive under Xcode 16.
      expect(
        podfile,
        contains(
          "config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.4'",
        ),
      );
    });

    test('the pbxproj pins it in all three configurations', () {
      // CocoaPods reads the Podfile and Xcode reads the pbxproj. The build only
      // works while they agree, and a disagreement surfaces as a linker error
      // about a symbol built for a newer iOS.
      expect(
        RegExp('IPHONEOS_DEPLOYMENT_TARGET = 16.4;').allMatches(pbxproj).length,
        3,
        reason: 'Debug, Release and Profile must all say 16.4',
      );
      expect(
        pbxproj,
        isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0;')),
        reason: 'a leftover 15.0 configuration will fail to resolve llamadart',
      );
    });
  });

  group('permission_handler trimming', () {
    test('declares exactly the microphone and notification macros', () {
      // ⚠️ A privacy requirement, not an optimisation: the macros strip the
      // photo/location/contacts API references out of the binary, which is what
      // lets the forbidden keys above stay absent and the privacy manifest stay
      // honest.
      expect(podfile, contains("target.name == 'permission_handler_apple'"));
      expect(podfile, contains('PERMISSION_MICROPHONE=1'));
      expect(podfile, contains('PERMISSION_NOTIFICATIONS=1'));
      for (final String macro in <String>[
        'PERMISSION_PHOTOS',
        'PERMISSION_LOCATION',
        'PERMISSION_CONTACTS',
        'PERMISSION_EVENTS',
      ]) {
        expect(podfile, isNot(contains(macro)), reason: '$macro must stay off');
      }
    });
  });

  group('bundle identity', () {
    test('the bundle id is uz.digitalgroup.tasuke', () {
      expect(
        pbxproj,
        contains('PRODUCT_BUNDLE_IDENTIFIER = uz.digitalgroup.tasuke;'),
      );
      expect(pbxproj, isNot(contains('uz.digitalgroup.tasukeAi')));
    });
  });

  group('AppDelegate', () {
    test('sets the notification delegate before registering plugins', () {
      // ⚠️ Registering plugins first loses the payload of the notification that
      // LAUNCHED the app. The symptom is "tapping a reminder opens Home", which
      // reads as a routing bug and sends the next maintainer into go_router.
      final String appDelegate = readProjectFile(
        'ios/Runner/AppDelegate.swift',
      );
      final int delegateAt = appDelegate.indexOf(
        'UNUserNotificationCenter.current().delegate',
      );
      final int registerAt = appDelegate.indexOf(
        'GeneratedPluginRegistrant.register',
      );

      expect(delegateAt, greaterThanOrEqualTo(0), reason: 'delegate never set');
      expect(
        registerAt,
        greaterThanOrEqualTo(0),
        reason: 'plugins never registered',
      );
      expect(delegateAt, lessThan(registerAt));
    });
  });
}
