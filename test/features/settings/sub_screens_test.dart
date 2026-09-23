import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ⚠️ riverpod 3.x exports `Override` only from `misc.dart`. Naming it without
// this import is a `non_type_as_type_argument` error that reads like a missing
// dependency.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tasuke_ai/app/l10n/app_localizations.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/app_theme.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/clock/clock.dart';
import 'package:tasuke_ai/core/purchases/purchase_gateway.dart';
import 'package:tasuke_ai/core/time/local_date.dart';
import 'package:tasuke_ai/features/settings/presentation/about_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/help_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/language_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/legal_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/settings_screen.dart';
import 'package:tasuke_ai/features/settings/presentation/usage_screen.dart';
import 'package:tasuke_ai/features/usage/data/usage_providers.dart';

import '../../helpers/fakes.dart';
import '../../helpers/pump_app.dart';

/// The screens behind the Settings rows.
///
/// The two legal ones are the reason this file exists: an offline-first app
/// whose Privacy Policy opens a dead page on a plane is a bad look, and Apple
/// expects the EULA to be reachable inside the binary.
void main() {
  final DateTime testNow = DateTime(2026, 9, 21, 10, 30);
  final Clock clock = FixedClock(testNow);
  final LocalDate today = LocalDate.today(testNow);

  late FakeUsageRepository usage;
  late FakePurchaseGateway store;

  setUp(() {
    usage = FakeUsageRepository();
    store = FakePurchaseGateway();
  });

  tearDown(() {
    usage.dispose();
    unawaited(store.dispose());
  });

  /// Pumps one sub-screen with a router under it, because Usage pushes the
  /// paywall and About pushes the licence page.
  Future<void> pumpSub(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(DeviceFrame.iPhoneNotch.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...defaultOverrides(clock: clock, purchases: store),
          usageRepositoryProvider.overrideWithValue(usage),
          packageInfoProvider.overrideWith(
            (Ref ref) async => PackageInfo(
              appName: 'Tasuke AI',
              packageName: 'com.tasuke.ai',
              version: '1.4.2',
              buildNumber: '142',
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: TasukeTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/subject',
            routes: <RouteBase>[
              GoRoute(path: '/subject', builder: (_, _) => screen),
              GoRoute(
                path: AppRoute.paywall.path,
                builder: (_, _) =>
                    const Scaffold(body: Center(child: Text('Paywall screen'))),
              ),
            ],
          ),
        ),
      ),
    );
    await pumpSettled(tester);
  }

  group('About', () {
    testWidgets('shows the platform version and the on-device promise', (
      WidgetTester tester,
    ) async {
      await pumpSub(tester, const AboutScreen());

      expect(find.text('Tasuke AI'), findsOneWidget);
      expect(find.text('v1.4.2'), findsOneWidget);
      expect(find.text('Everything runs on your device'), findsOneWidget);
      expect(
        find.text(
          'Speech recognition and task extraction both happen on this phone, '
          'and Tasuke AI downloads nothing after you install it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Speak. Plan. Done.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('opens the licence page, which the bundled packages need', (
      WidgetTester tester,
    ) async {
      await pumpSub(tester, const AboutScreen());

      await tester.tap(find.text('Open source licenses'));
      await pumpSettled(tester);

      expect(find.byType(LicensePage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Language', () {
    testWidgets('offers the one locale v1 ships, and marks it chosen', (
      WidgetTester tester,
    ) async {
      await pumpSub(tester, const LanguageScreen());

      expect(find.text('Language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      // A row that opens nothing would be worse than a screen with one option.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byType(SettingsRow), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Help', () {
    testWidgets('answers the three questions support actually receives', (
      WidgetTester tester,
    ) async {
      await pumpSub(tester, const HelpScreen());

      expect(find.text('How to capture a task'), findsOneWidget);
      expect(find.text('Does it work offline?'), findsOneWidget);
      expect(find.text('My reminders are late'), findsOneWidget);
      expect(
        find.textContaining('Some devices delay alarms to save battery'),
        findsOneWidget,
      );
      // Nothing is downloaded any more; the answer must not promise a model.
      expect(find.textContaining('language model'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows the support inbox the store listing names', (
      WidgetTester tester,
    ) async {
      await pumpSub(tester, const HelpScreen());
      await tester.scrollUntilVisible(
        find.text('info@digital-group.uz'),
        120,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Contact support'), findsOneWidget);
      expect(find.text('info@digital-group.uz'), findsOneWidget);

      // One inbox everywhere: the listing, the review notes and both policies.
      for (final String path in <String>[
        'store/store-listing.txt',
        'store/REVIEW_NOTES.md',
        'store/privacy-policy.html',
        'store/terms.html',
        'assets/legal/privacy_en.md',
        'assets/legal/terms_en.md',
      ]) {
        final String text = File(path).readAsStringSync();
        expect(text, contains('info@digital-group.uz'), reason: path);
        expect(text, isNot(contains('support@tasuke.app')), reason: path);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the legal documents', () {
    testWidgets('the Privacy Policy renders the bundled Markdown', (
      WidgetTester tester,
    ) async {
      await pumpSub(tester, const LegalScreen(document: LegalDocument.privacy));

      // The header and the document's own `# ` heading.
      expect(find.text('Privacy Policy'), findsNWidgets(2));
      expect(find.text('The short version'), findsOneWidget);
      expect(find.text('Tasuke AI collects nothing.'), findsOneWidget);
      expect(
        find.text('the text your speech is transcribed into'),
        findsOneWidget,
        reason: 'bullets are one of the three constructs the renderer handles',
      );

      // ⚠️ Bundled, not linked. The premise of the app is that it works with
      // no connection, so there is nothing here to open a browser with.
      expect(find.text('View online'), findsNothing);
      expect(find.byType(LoadingState), findsNothing);
      expect(find.byType(ErrorState), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the Terms carry the EULA clause Apple looks for', (
      WidgetTester tester,
    ) async {
      await pumpSub(tester, const LegalScreen(document: LegalDocument.terms));

      expect(find.text('Terms of Service'), findsNWidgets(2));
      expect(find.text('1. Agreement'), findsOneWidget);
      expect(
        find.textContaining('Licensed Application'),
        findsOneWidget,
        reason: "Apple's standard EULA has to be reachable inside the binary",
      );
      // The subscription terms live in the document too, not only on the
      // paywall: both stores expect them in the agreement the user accepts.
      expect(find.textContaining('renews automatically'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Usage', () {
    testWidgets('a free account sees the count, the bar and the way up', (
      WidgetTester tester,
    ) async {
      await usage.recordCapture(today, taskCount: 2);

      await pumpSub(tester, const UsageScreen());

      // One free capture a day: after it, the bar is full.
      expect(find.text('1 / 1'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(1, 0.001),
      );

      await tester.tap(find.text('See Pro plans'));
      await pumpSettled(tester);
      expect(find.text('Paywall screen'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a subscriber is shown neither a quota nor an upsell', (
      WidgetTester tester,
    ) async {
      store.emit(
        const Entitlement(
          status: EntitlementStatus.proActive,
          productId: 'pro.yearly',
        ),
      );
      await usage.recordCapture(today, taskCount: 2);

      await pumpSub(tester, const UsageScreen());

      expect(find.text('Unlimited'), findsOneWidget);
      expect(find.textContaining('/ 1'), findsNothing);
      // Selling Pro to someone who already bought it is how a refund starts.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('See Pro plans'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
