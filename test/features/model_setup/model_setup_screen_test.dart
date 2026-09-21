import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`. Naming it without
// this import is a `non_type_as_type_argument` error that reads like a missing
// dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';
import 'package:tasuke_ai/features/model_setup/presentation/model_setup_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// The one-time model download.
///
/// ⚠️ Everything here is built around the fact that this screen is an OFFER.
/// The app is fully usable without the model — manual tasks, reminders, every
/// screen — and only voice capture waits, so "Not now" has to be a real way
/// out rather than a button that leaves the user on a progress bar.
void main() {
  late FakeModelInstaller installer;

  setUp(() => installer = FakeModelInstaller());
  tearDown(() => installer.dispose());

  Future<void> pumpSetup(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[...defaultOverrides(models: installer)],
        child: MaterialApp.router(
          theme: TasukeTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            initialLocation: AppRoute.modelSetup.path,
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.modelSetup.path,
                builder: (_, _) => const ModelSetupScreen(),
              ),
              GoRoute(
                path: AppRoute.home.path,
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('Home'))),
              ),
            ],
          ),
        ),
      ),
    );
    await pumpSettled(tester);
  }

  /// Pushes a state through the installer's stream, the way a real download
  /// reports itself.
  Future<void> emit(WidgetTester tester, ModelState state) async {
    installer.emit(state);
    await pumpSettled(tester);
  }

  PrimaryButton cta(WidgetTester tester) =>
      tester.widget<PrimaryButton>(find.byType(PrimaryButton));

  testWidgets('offers the download with its real size and the Wi-Fi hint', (
    WidgetTester tester,
  ) async {
    await pumpSetup(tester);

    expect(find.text('Preparing your AI'), findsOneWidget);
    // The size comes from the spec, so a model swapped for a bigger one cannot
    // leave a stale number in front of someone on a metered connection.
    expect(TasukeModels.extractor.sizeLabel, '219 MB');
    expect(
      find.text(
        'Tasuke AI is downloading its language model. This happens once, '
        'and only needs 219 MB.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Best over Wi-Fi. You can keep using the app while it downloads.',
      ),
      findsOneWidget,
    );
    expect(find.text('Download now'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Download now hands the spec to the installer', (
    WidgetTester tester,
  ) async {
    await pumpSetup(tester);

    await tester.tap(find.text('Download now'));
    await pumpSettled(tester);

    expect(installer.stateOf(TasukeModels.extractor), isA<ModelReady>());
    expect(find.text('Your AI is ready'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a download in flight shows its progress and blocks a second '
      'tap', (WidgetTester tester) async {
    await pumpSetup(tester);

    await emit(
      tester,
      const ModelDownloading(receivedBytes: 45, totalBytes: 100),
    );

    // Once as the subtitle, once on the button the user is looking at.
    expect(find.text('45% downloaded'), findsNWidgets(2));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(0.45, 0.001),
    );
    expect(cta(tester).busy, isTrue);
    expect(cta(tester).onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelling a download returns to the offer, not to Home', (
    WidgetTester tester,
  ) async {
    await pumpSetup(tester);
    await emit(
      tester,
      const ModelDownloading(receivedBytes: 10, totalBytes: 100),
    );

    // The secondary action becomes Cancel while bytes are moving: "Not now"
    // there would read as a way to leave, and leaving would abandon the
    // download without saying so.
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Not now'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await pumpSettled(tester);

    expect(find.byType(ModelSetupScreen), findsOneWidget);
    expect(find.text('Download now'), findsOneWidget);
    expect(find.text('Home'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed download says what happened and offers a retry', (
    WidgetTester tester,
  ) async {
    await pumpSetup(tester);

    await emit(
      tester,
      const ModelFailed(
        'The downloaded file was incomplete and has been '
        'removed.',
      ),
    );

    expect(find.text("The download didn't finish"), findsOneWidget);
    // The installer's own message, not a generic one: "incomplete" and "no
    // space" need different reactions from the user.
    expect(
      find.text('The downloaded file was incomplete and has been removed.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(cta(tester).busy, isFalse);

    await tester.tap(find.text('Try again'));
    await pumpSettled(tester);

    expect(installer.stateOf(TasukeModels.extractor), isA<ModelReady>());

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Not now leaves the screen with nothing downloaded', (
    WidgetTester tester,
  ) async {
    await pumpSetup(tester);

    await tester.tap(find.text('Not now'));
    await pumpSettled(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(ModelSetupScreen), findsNothing);
    // ⚠️ Skippable by design. A first launch that is nothing but a progress
    // bar is bad retention and an App Review "minimum functionality" risk.
    expect(installer.stateOf(TasukeModels.extractor), isA<ModelNotInstalled>());

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
