import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';

import '_harness.dart';

/// Hosts a widget that needs a Navigator and a ScaffoldMessenger above it.
Widget hostedAction(void Function(BuildContext) onPressed) {
  return TasukeScaffold(
    child: Builder(
      builder: (BuildContext context) {
        return PrimaryButton(label: 'go', onPressed: () => onPressed(context));
      },
    ),
  );
}

void main() {
  group('PageDots', () {
    testWidgets('widens the active dot rather than only recolouring it', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(tester, const PageDots(count: 3, index: 1));

      final List<Size> dots = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((AnimatedContainer dot) => tester.getSize(find.byWidget(dot)))
          .toList();

      expect(dots.length, 3);
      expect(dots[1].width, greaterThan(dots[0].width));
      expect(dots[0].width, dots[2].width);
    });
  });

  group('PermissionCard', () {
    testWidgets('asks while it can, and stops asking once granted', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        PermissionCard(
          title: 'Microphone',
          subtitle: 'To record your voice',
          icon: const Icon(Icons.mic_rounded),
          state: PermissionState.notDetermined,
          onTap: () => taps++,
        ),
      );
      expect(find.text('Allow'), findsOneWidget);
      await tester.tap(find.text('Microphone'));
      expect(taps, 1);

      await pumpWidgetUnderTest(
        tester,
        PermissionCard(
          title: 'Microphone',
          subtitle: 'To record your voice',
          icon: const Icon(Icons.mic_rounded),
          state: PermissionState.granted,
          onTap: () => taps++,
        ),
      );
      expect(find.text('Allowed'), findsOneWidget);
      await tester.tap(find.text('Microphone'));
      expect(taps, 1, reason: 'a granted permission has nothing left to ask');
    });

    testWidgets('a permanent denial points at Settings, not at a retry', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        PermissionCard(
          title: 'Notifications',
          subtitle: 'To remind you about your tasks',
          icon: const Icon(Icons.notifications_rounded),
          state: PermissionState.permanentlyDenied,
          onTap: () {},
        ),
      );

      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Allow'), findsNothing);
    });
  });

  group('PlanCard', () {
    testWidgets('renders price, period, badge and footnote', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpWidgetUnderTest(
        tester,
        PlanCard(
          title: 'Yearly',
          price: r'$39.99',
          period: 'per year',
          badge: 'Save 33%',
          footnote: r'$3.33 per month, billed yearly',
          selected: true,
          onTap: () => taps++,
        ),
      );

      expect(find.text('Yearly'), findsOneWidget);
      expect(find.text(r'$39.99'), findsOneWidget);
      expect(find.text('Save 33%'), findsOneWidget);
      expect(find.text(r'$3.33 per month, billed yearly'), findsOneWidget);

      await tester.tap(find.text('Yearly'));
      expect(taps, 1);
    });

    testWidgets('selection is a card state, not a Radio', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        PlanCard(
          title: 'Monthly',
          price: r'$4.99',
          period: 'per month',
          selected: false,
          onTap: () {},
        ),
      );
      expect(find.byType(Radio<Object>), findsNothing);

      final TasukeCard unselected = tester.widget<TasukeCard>(
        find.byType(TasukeCard),
      );
      expect(unselected.background, TasukeColors.surface);

      await pumpWidgetUnderTest(
        tester,
        PlanCard(
          title: 'Monthly',
          price: r'$4.99',
          period: 'per month',
          selected: true,
          onTap: () {},
        ),
      );
      expect(
        tester.widget<TasukeCard>(find.byType(TasukeCard)).background,
        TasukeColors.primaryTint,
      );
    });
  });

  group('BenefitRow and CrownHeader', () {
    testWidgets('render their copy', (WidgetTester tester) async {
      await pumpWidgetUnderTest(
        tester,
        const Column(
          children: <Widget>[
            CrownHeader(
              title: 'Tasuke Pro',
              subtitle: 'Unlock your full potential',
            ),
            BenefitRow(label: 'Unlimited voice processing'),
          ],
        ),
      );

      expect(find.text('Tasuke Pro'), findsOneWidget);
      expect(find.text('Unlock your full potential'), findsOneWidget);
      expect(find.text('Unlimited voice processing'), findsOneWidget);
      expect(find.byType(CheckCircle), findsOneWidget);
    });
  });

  group('TasukeLogo', () {
    testWidgets('paints the mark, and adds the wordmark on request', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const Align(alignment: Alignment.centerLeft, child: TasukeLogo()),
      );
      expect(find.text('Tasuke AI'), findsNothing);
      expect(tester.getSize(find.byType(TasukeLogo)).width, 88);

      await pumpWidgetUnderTest(tester, const TasukeLogo(showWordmark: true));
      expect(find.text('Tasuke AI'), findsOneWidget);
    });
  });

  group('TasukeBanner', () {
    testWidgets('tints itself by tone and dismisses', (
      WidgetTester tester,
    ) async {
      int dismissals = 0;
      await pumpWidgetUnderTest(
        tester,
        TasukeBanner(
          message: 'Reminders may arrive a few minutes late on this device.',
          tone: BannerTone.warning,
          onDismiss: () => dismissals++,
        ),
      );

      final DecoratedBox box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(TasukeBanner),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color, TasukeColors.goldTint);

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(dismissals, 1);
    });

    testWidgets('has no dismiss affordance without a callback', (
      WidgetTester tester,
    ) async {
      await pumpWidgetUnderTest(
        tester,
        const TasukeBanner(message: 'Reminders are off.'),
      );

      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('AppSnack', () {
    testWidgets('shows one snack at a time', (WidgetTester tester) async {
      await pumpWidgetUnderTest(
        tester,
        hostedAction((BuildContext context) {
          AppSnack.success(context, 'Task deleted');
        }),
        scrollable: false,
      );

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(find.text('Task deleted'), findsOneWidget);

      // A second call replaces the first rather than queueing behind it.
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Task deleted'), findsOneWidget);
    });

    testWidgets('error and info render too', (WidgetTester tester) async {
      await pumpWidgetUnderTest(
        tester,
        hostedAction((BuildContext context) {
          AppSnack.error(context, 'Something went wrong');
        }),
        scrollable: false,
      );

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
    });
  });

  group('app dialogs', () {
    Future<bool?> runDialog(
      WidgetTester tester,
      Future<bool?> Function(BuildContext) open,
      String tapLabel,
    ) async {
      Future<bool?>? result;
      await pumpWidgetUnderTest(
        tester,
        hostedAction((BuildContext context) => result = open(context)),
        scrollable: false,
      );

      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tapLabel));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('discarding drafts asks first', (WidgetTester tester) async {
      expect(
        await runDialog(tester, showDiscardDraftsDialog, 'Discard'),
        isTrue,
      );
    });

    testWidgets('cancelling answers false, never null', (
      WidgetTester tester,
    ) async {
      expect(await runDialog(tester, showDeleteTaskDialog, 'Cancel'), isFalse);
    });

    testWidgets('deleting a task asks first', (WidgetTester tester) async {
      Future<bool?>? result;
      await pumpWidgetUnderTest(
        tester,
        hostedAction(
          (BuildContext context) => result = showDeleteTaskDialog(context),
        ),
        scrollable: false,
      );

      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(find.text('Delete this task?'), findsOneWidget);
      expect(find.text("This can't be undone."), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('resetting and deleting everything both confirm', (
      WidgetTester tester,
    ) async {
      expect(await runDialog(tester, showResetDataDialog, 'Continue'), isTrue);
      expect(
        await runDialog(tester, showDeleteAllDataDialog, 'Delete'),
        isTrue,
      );
    });
  });
}
