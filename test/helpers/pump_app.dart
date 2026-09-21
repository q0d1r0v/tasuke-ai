import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x does not export `Override`, `ProviderListenable` or the
// `*Family` types from its main library — only from `misc.dart`. Naming any of
// them without this import is a `non_type_as_type_argument` error that reads
// like a missing dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/core/audio/audio_providers.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/models/model_providers.dart';
import 'package:tasuke_ai/core/notifications/notification_providers.dart';
import 'package:tasuke_ai/core/permissions/permission_providers.dart';
import 'package:tasuke_ai/core/purchases/purchase_providers.dart';
import 'package:tasuke_ai/core/speech/speech_providers.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';

import 'fakes.dart';

/// Device frames the layout is verified against.
///
/// The design sheet has no system chrome, so none of its numbers can stand in
/// for a real device's insets. [android3Button] is the one that catches a nav
/// bar drawn underneath the back/home/recents glyphs — a bug a sibling app in
/// this repo shipped.
enum DeviceFrame {
  iPhoneNotch(Size(375, 812), EdgeInsets.only(top: 44, bottom: 34)),
  android3Button(Size(393, 873), EdgeInsets.only(top: 33, bottom: 48)),
  androidGesture(Size(393, 873), EdgeInsets.only(top: 33, bottom: 24)),

  /// The smallest phone still supported. Used for the paywall golden, because
  /// the store-required disclosures must not fall below the fold.
  smallNoInsets(Size(320, 568), EdgeInsets.zero),

  /// The design sheet's own frame, with no chrome at all.
  figmaSheet(Size(375, 812), EdgeInsets.zero);

  const DeviceFrame(this.size, this.padding);

  final Size size;
  final EdgeInsets padding;
}

/// Installs a fake for **every** port, whether or not the test asks.
///
/// ⚠️ This is the whole point of the helper. A screen that reaches a real
/// MethodChannel under `flutter_test` throws inside a Future; the error lands
/// in an `AsyncValue.error` the widget quietly renders as a spinner, and the
/// test passes having exercised nothing.
List<Override> defaultOverrides({
  Clock? clock,
  FakeAudioRecorder? recorder,
  FakeSpeechRecognizer? recognizer,
  FakePermissionService? permissions,
  FakeLocalNotifier? notifier,
  FakePurchaseGateway? purchases,
  FakeModelInstaller? models,
  SharedPreferences? preferences,
}) {
  return <Override>[
    clockProvider.overrideWithValue(
      clock ?? FixedClock(DateTime(2026, 9, 21, 10, 30)),
    ),
    audioRecorderProvider.overrideWithValue(recorder ?? FakeAudioRecorder()),
    speechRecognizerProvider.overrideWithValue(
      recognizer ?? FakeSpeechRecognizer(),
    ),
    permissionServiceProvider.overrideWithValue(
      permissions ?? FakePermissionService(),
    ),
    localNotifierProvider.overrideWithValue(notifier ?? FakeLocalNotifier()),
    purchaseGatewayProvider.overrideWithValue(
      purchases ?? FakePurchaseGateway(),
    ),
    modelInstallerProvider.overrideWithValue(models ?? FakeModelInstaller()),
    if (preferences != null)
      sharedPreferencesProvider.overrideWithValue(preferences),
  ];
}

/// Pumps one screen with the real theme, real fonts and real localizations.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const <Override>[],
  DeviceFrame frame = DeviceFrame.iPhoneNotch,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(frame.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: TasukeTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: frame.size,
            padding: frame.padding,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child,
        ),
      ),
    ),
  );
  await pumpSettled(tester);
}

/// ⚠️ Never `pumpAndSettle` in this app.
///
/// The Recording screen's waveform and the mic orb animate forever, so
/// `pumpAndSettle` times out rather than settling. Four fixed frames is enough
/// for every transition the app actually uses.
Future<void> pumpSettled(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Reads a provider without building a widget.
T readProvider<T>(WidgetTester tester, ProviderListenable<T> provider) {
  final Element element = tester.element(find.byType(MaterialApp));
  return ProviderScope.containerOf(element, listen: false).read(provider);
}

/// Loads the bundled Inter faces so text measures like it does on a device.
///
/// Without this every golden is laid out in the test stub font and every
/// overflow assertion is measuring the wrong glyphs.
Future<void> loadAppFonts() async {
  final FontLoader loader = FontLoader('Inter');
  loader.addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
  await loader.load();
}
