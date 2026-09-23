import 'package:flutter_test/flutter_test.dart';

import 'native_source.dart';

/// Guards `packages/whisper_ggml/ios/whisper_ggml.podspec`.
///
/// ⚠️ `s.xcconfig` is the deprecated attribute CocoaPods merges into the APP
/// target's xcconfig as well as the pod's. Its `IPHONEOS_DEPLOYMENT_TARGET =
/// 15.6` came through `Pods-Runner.*.xcconfig`, which Runner's configurations
/// include, and beat the project-level 16.4: the archive declared
/// MinimumOSVersion 15.6 while every embedded pod said 16.4. Nothing here can
/// run `pod install`, and the Podfile and pbxproj checks in
/// `ios_plist_test.dart` both passed, so the podspec text is the only thing to
/// check.
void main() {
  late String code;
  late String podTargetXcconfig;

  setUpAll(() {
    // Comments dropped: the podspec explains, by name, the key it must not use.
    code = readProjectFile('packages/whisper_ggml/ios/whisper_ggml.podspec')
        .split('\n')
        .where((String line) => !line.trimLeft().startsWith('#'))
        .join('\n');
    final int start = code.indexOf('s.pod_target_xcconfig = {');
    expect(start, isNot(-1), reason: 'the pod has no pod_target_xcconfig');
    podTargetXcconfig = code.substring(start, code.indexOf('\n  }', start));
  });

  test('sets nothing on the app target', () {
    expect(code, isNot(contains('s.xcconfig')));
    expect(code, isNot(contains('user_target_xcconfig')));
  });

  test('declares the app floor, 16.4, and nothing lower', () {
    expect(code, contains("s.platform = :ios, '16.4'"));
    expect(code, matches(RegExp(r"s\.ios\.deployment_target\s*=\s*'16\.4'")));
    expect(code, isNot(contains('15.6')));
  });

  test('still compiles its own sources as C++20', () {
    // It came through `s.xcconfig` before; dropping that must not drop this.
    expect(
      podTargetXcconfig,
      contains("'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20'"),
    );
  });
}
