import 'package:flutter_test/flutter_test.dart';

import 'native_source.dart';

/// Guards `android/app/build.gradle.kts` and `android/app/proguard-rules.pro`.
///
/// A Gradle build cannot be run here, so this file is the only check these
/// settings get before they reach a release artifact — and every one of them
/// fails in release only, on a device only, or at upload only.
void main() {
  late String gradle;
  late String proguard;

  setUpAll(() {
    gradle = readProjectFile('android/app/build.gradle.kts');
    proguard = readProjectFile('android/app/proguard-rules.pro');
  });

  group('SDK versions come from the Flutter SDK', () {
    // Play's target-API floor moves every August. When every version is
    // `flutter.*`, `flutter upgrade` carries the new requirement in for free;
    // a literal here means the app quietly stops being updatable a year later
    // and the message arrives at upload, not at build.
    // ⚠️ compileSdk is the documented exception: permission_handler_android's
    // AAR metadata requires API 37 and Flutter 3.47.5 still defaults to 36.
    // The literal is asserted *with* its justification comment, so removing the
    // reasoning breaks the test rather than quietly leaving an orphan literal.
    test('compileSdk is pinned to 37 with its reason recorded', () {
      expect(gradle, contains('compileSdk = 37'));
      expect(gradle, contains('permission_handler_android'));
      expect(gradle, contains('flutter.compileSdkVersion'));
    });

    test('minSdk', () {
      expect(gradle, contains('minSdk = flutter.minSdkVersion'));
    });

    test('targetSdk', () {
      expect(gradle, contains('targetSdk = flutter.targetSdkVersion'));
    });

    test('ndkVersion', () {
      expect(gradle, contains('ndkVersion = flutter.ndkVersion'));
    });

    test('no numeric literal is assigned to any of them', () {
      // compileSdk is excluded deliberately — see the test above.
      for (final String setting in <String>['minSdk', 'targetSdk']) {
        expect(
          RegExp('$setting\\s*=\\s*\\d+').hasMatch(gradle),
          isFalse,
          reason: '$setting must be flutter.${setting}Version, not a literal',
        );
      }
      expect(
        RegExp(r'ndkVersion\s*=\s*"').hasMatch(gradle),
        isFalse,
        reason: 'ndkVersion must be flutter.ndkVersion, not a pinned string',
      );
    });
  });

  group('core library desugaring', () {
    // ⚠️ Two halves, and having only one of them is worse than having neither:
    // the project still compiles, and then every scheduled reminder dies at
    // runtime with NoClassDefFoundError on java.time. No test on a Linux box
    // and no debug build can see it.
    test('the compile option is enabled', () {
      expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
    });

    test('the desugar_jdk_libs dependency is declared', () {
      expect(
        RegExp(
          r'coreLibraryDesugaring\("com\.android\.tools:desugar_jdk_libs:[\d.]+"\)',
        ).hasMatch(gradle),
        isTrue,
        reason:
            'isCoreLibraryDesugaringEnabled without the dependency is a '
            'runtime NoClassDefFoundError on every notification',
      );
    });
  });

  group('Java 17', () {
    test('source and target compatibility', () {
      expect(gradle, contains('sourceCompatibility = JavaVersion.VERSION_17'));
      expect(gradle, contains('targetCompatibility = JavaVersion.VERSION_17'));
    });

    test('Kotlin jvmTarget', () {
      expect(gradle, contains('JvmTarget.JVM_17'));
    });
  });

  group('release signing', () {
    test('reads android/key.properties', () {
      expect(gradle, contains('rootProject.file("key.properties")'));
    });

    test('falls back to the debug key rather than failing the build', () {
      // The fallback is what keeps `flutter run --release` working on a machine
      // that has never seen the keystore — CI, and every new contributor.
      expect(gradle, contains('signingConfigs.getByName("debug")'));
      expect(gradle, contains('signingConfigs.getByName("release")'));
    });

    test('warns loudly at configure time when the keystore is missing', () {
      // An AAB signed with the debug key is rejected by Play *at upload*, after
      // the build and the upload, with a message that does not mention
      // key.properties. This warning is the only signal anybody gets.
      expect(gradle, contains('logger.warn'));
      expect(gradle, contains('key.properties'));
    });

    test('key.properties.example exists and holds no real secret', () {
      final String example = readProjectFile('android/key.properties.example');
      expect(example, contains('storePassword='));
      expect(example, contains('keyAlias='));
      expect(example, contains('storeFile='));
      expect(example, contains('CHANGEME'));
    });

    test('key.properties and keystores are gitignored', () {
      final String ignore = readProjectFile('android/.gitignore');
      expect(ignore, contains('key.properties'));
      expect(ignore, contains('*.jks'));
    });
  });

  group('release shrinking', () {
    test('minify and resource shrinking are on', () {
      expect(gradle, contains('isMinifyEnabled = true'));
      expect(gradle, contains('isShrinkResources = true'));
    });

    test('proguard-rules.pro is wired into the release build type', () {
      expect(gradle, contains('"proguard-rules.pro"'));
    });

    test('native method names survive R8', () {
      // ⚠️ whisper.cpp and llama.cpp are reached through dart:ffi by symbol
      // NAME. R8 renames them, DynamicLibrary.lookup throws, and transcription
      // fails in release builds only — i.e. in the build a reviewer runs.
      expect(proguard, contains('-keepclasseswithmembernames class * {'));
      expect(proguard, contains('native <methods>;'));
    });

    test('keeps the classes the manifest and Gson reach reflectively', () {
      expect(proguard, contains('com.dexterous'));
      expect(proguard, contains('com.google.gson'));
      expect(proguard, contains('com.android.billingclient'));
      expect(proguard, contains('sqflite'));
    });
  });

  group('identity and ABIs', () {
    test('namespace and applicationId are uz.digitalgroup.tasuke', () {
      expect(gradle, contains('namespace = "uz.digitalgroup.tasuke"'));
      expect(gradle, contains('applicationId = "uz.digitalgroup.tasuke"'));
    });

    test('debug and profile keep x86_64', () {
      // The only emulator image on this machine is x86_64. Trimming the ABI set
      // to ARM — the obvious release-size move — makes `flutter run` fail with
      // INSTALL_FAILED_NO_MATCHING_ABIS, which reads like a broken AVD.
      expect(
        RegExp('x86_64').allMatches(gradle).length,
        greaterThanOrEqualTo(2),
        reason: 'both the debug and the profile ABI set must include x86_64',
      );
    });
  });
}
