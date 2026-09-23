import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/permissions/app_permission.dart';
import 'package:tasuke_ai/features/tasks/domain/task_draft.dart';

import '_harness.dart';

/// One entry in the catalogue: what to pump, and whether it brings its own
/// scrolling.
typedef Specimen = ({String name, Widget widget, bool scrollable});

/// Every widget in the catalogue, built with the longest copy the app can
/// actually hand it.
///
/// ⚠️ This is the regression test for the bug that shipped in the sibling app:
/// a card with a `SizedBox(height:)` around its text renders perfectly at 1×
/// and paints a black-and-yellow stripe at 2×, where a fifth of users live.
/// Every one of these is intrinsic height, so the only thing that changes with
/// the scale is how tall it gets.
List<Specimen> catalogue(
  TextEditingController controller,
  ValueNotifier<double> ticker,
) {
  return <Specimen>[
    (
      name: 'PrimaryButton',
      widget: PrimaryButton(label: 'Save Tasks', onPressed: () {}),
      scrollable: true,
    ),
    (
      name: 'PrimaryButton (busy, long label)',
      widget: PrimaryButton(
        label: 'Subscribe and unlock your full potential',
        busy: true,
        onPressed: () {},
      ),
      scrollable: true,
    ),
    (
      name: 'PrimaryButton (disabled, leading)',
      widget: const PrimaryButton(
        label: 'Restore Purchases',
        leading: Icons.refresh_rounded,
        onPressed: null,
      ),
      scrollable: true,
    ),
    (
      name: 'SecondaryButton',
      widget: SecondaryButton(label: 'Not now', onPressed: () {}),
      scrollable: true,
    ),
    (
      name: 'DangerButton (filled)',
      widget: DangerButton(label: 'Stop', filled: true, onPressed: () {}),
      scrollable: true,
    ),
    (
      name: 'DangerButton (tinted)',
      widget: DangerButton(
        label: 'Delete Task',
        leading: Icons.delete_outline_rounded,
        onPressed: () {},
      ),
      scrollable: true,
    ),
    (
      name: 'TextLinkButton',
      widget: TextLinkButton(
        label: 'Terms of Use and Privacy Policy',
        onPressed: () {},
      ),
      scrollable: true,
    ),
    (
      name: 'TasukeSwitch',
      widget: TasukeSwitch(value: true, onChanged: (bool _) {}),
      scrollable: true,
    ),
    (
      name: 'TasukeScaffold',
      widget: TasukeScaffold(
        title: 'Terms of Service',
        showBack: true,
        bottomBar: PrimaryButton(label: 'Save Tasks', onPressed: () {}),
        child: const Text(
          'Speech recognition and task extraction both happen on this phone.',
        ),
      ),
      scrollable: false,
    ),
    (
      name: 'ScreenHeader',
      widget: const ScreenHeader(title: 'Help & Support'),
      scrollable: true,
    ),
    (
      name: 'TasukeCard',
      widget: const TasukeCard(
        child: Text(
          'Subscription renews automatically unless cancelled at least 24 '
          'hours before the end of the current period.',
        ),
      ),
      scrollable: true,
    ),
    (
      name: 'SectionHeader',
      widget: const SectionHeader(label: 'Next Week', trailing: Text('12')),
      scrollable: true,
    ),
    (
      name: 'IconTile',
      widget: const Align(
        alignment: Alignment.centerLeft,
        child: IconTile(icon: Icon(Icons.mic_rounded)),
      ),
      scrollable: true,
    ),
    (
      name: 'SettingsRow',
      widget: SettingsRow(
        title: 'All-day reminder time',
        subtitle: 'Reminders for the tasks you create.',
        leading: const IconTile(icon: Icon(Icons.notifications_rounded)),
        trailing: const Text('Unlimited'),
        onTap: () {},
      ),
      scrollable: true,
    ),
    (
      name: 'SettingsGroup',
      widget: SettingsGroup(
        header: 'Subscription',
        children: <Widget>[
          SettingsRow(title: 'Restore Purchases', onTap: () {}),
          SettingsRow(
            title: 'Usage',
            trailing: const Text('0 / 1 today'),
            onTap: () {},
          ),
        ],
      ),
      scrollable: true,
    ),
    (
      name: 'TasukeTextField',
      widget: TasukeTextField(
        controller: controller,
        hint: 'What needs doing?',
      ),
      scrollable: true,
    ),
    (
      name: 'SegmentedTabs',
      widget: SegmentedTabs(
        labels: const <String>['Today', 'Upcoming', 'Completed'],
        selected: 1,
        onSelected: (int _) {},
      ),
      scrollable: true,
    ),
    (
      name: 'TasukeBottomNav',
      widget: TasukeBottomNav(
        currentIndex: 0,
        onSelected: (int _) {},
        onMicTap: () {},
        micProgressLabel: 'Preparing AI — 42%',
      ),
      scrollable: true,
    ),
    (
      name: 'TaskListTile',
      widget: TaskListTile(
        task: makeTask(
          title:
              'Tomorrow at 3 PM send the build to James and then check '
              'App Store Connect for the review status',
        ),
        relativeDayLabel: 'Tomorrow',
        timeLabel: '3:00 PM',
        onToggle: (bool _) {},
      ),
      scrollable: true,
    ),
    (
      name: 'CheckCircle',
      widget: Align(
        alignment: Alignment.centerLeft,
        child: CheckCircle(checked: true, onChanged: (bool _) {}),
      ),
      scrollable: true,
    ),
    (
      name: 'DateChip',
      widget: Align(
        alignment: Alignment.centerLeft,
        child: DateChip(
          dateLabel: 'Tomorrow',
          timeLabel: '10:00 AM',
          flagged: true,
          onTap: () {},
        ),
      ),
      scrollable: true,
    ),
    (
      name: 'EditableTaskCard',
      widget: EditableTaskCard(
        draft: makeDraft(
          title: 'Check App Store Connect for the review status',
          lowConfidenceDate: true,
        ),
        onChanged: (TaskDraft _) {},
        onDelete: () {},
        onEditDate: () {},
        dateLabelBuilder: (TaskDraft _) => 'Tomorrow, 3:00 PM',
      ),
      scrollable: true,
    ),
    (
      name: 'DashedAddRow',
      widget: DashedAddRow(label: 'Add another task', onTap: () {}),
      scrollable: true,
    ),
    (
      name: 'MicFab',
      widget: Align(
        alignment: Alignment.centerLeft,
        child: MicFab(onTap: () {}),
      ),
      scrollable: true,
    ),
    (
      name: 'MicOrb',
      widget: MicOrb(amplitude: ticker, levelOf: () => ticker.value),
      scrollable: true,
    ),
    (
      name: 'WaveformView',
      widget: WaveformView(
        amplitude: ticker,
        samplesOf: () => const <double>[0.1, 0.6, 0.3],
      ),
      scrollable: true,
    ),
    (
      name: 'RecordingTimer',
      widget: RecordingTimer(
        elapsed: ticker,
        valueOf: () => const Duration(seconds: 72),
      ),
      scrollable: true,
    ),
    (name: 'GradientOrb', widget: const GradientOrb(), scrollable: true),
    // Both are fixed-size pictures with no text in them, so what is being
    // checked is the one thing that can still go wrong: that they keep their
    // box at 2× type scale instead of stretching and pushing a headline off
    // the page.
    (name: 'BlobOrb', widget: const BlobOrb(), scrollable: true),
    (
      name: 'SvgIllustration',
      widget: const SvgIllustration(asset: TasukeArt.guideVoice, size: 216),
      scrollable: true,
    ),
    (
      name: 'ProcessingChecklist',
      widget: const ProcessingChecklist(
        steps: <ProcessingStepView>[
          ProcessingStepView(
            label: 'Transcribing your voice',
            state: ProcessingStepState.done,
          ),
          ProcessingStepView(
            label: 'Understanding with AI',
            state: ProcessingStepState.active,
          ),
          ProcessingStepView(
            label: 'Finding tasks and dates',
            state: ProcessingStepState.pending,
          ),
        ],
      ),
      scrollable: true,
    ),
    (
      name: 'AsyncValueView (error)',
      widget: AsyncValueView<String>(
        value: AsyncValue<String>.error('boom', StackTrace.empty),
        data: (String value) => Text(value),
      ),
      scrollable: true,
    ),
    (
      name: 'EmptyState',
      widget: EmptyState(
        title: 'Nothing completed yet',
        message:
            'Finished tasks collect here so you can see what you got '
            'done.',
        actionLabel: 'Speak',
        icon: Icons.checklist_rounded,
        onAction: () {},
      ),
      scrollable: true,
    ),
    (
      name: 'ErrorState',
      widget: ErrorState(
        title: "Tasuke can't open its database",
        message: "This usually means the app's storage was damaged.",
        actionLabel: 'Try again',
        secondaryLabel: 'Reset app data',
        onRetry: () {},
        onSecondary: () {},
      ),
      scrollable: true,
    ),
    (
      name: 'LoadingState',
      widget: const LoadingState(message: 'Turning your thoughts into tasks…'),
      scrollable: true,
    ),
    (
      name: 'PermissionDeniedState',
      widget: PermissionDeniedState(
        title: 'Tasuke needs your microphone',
        message:
            "It's used only while you're recording a task, and the audio "
            'never leaves this device.',
        actionLabel: 'Open Settings',
        onAction: () {},
      ),
      scrollable: true,
    ),
    (
      name: 'PageDots',
      widget: const PageDots(count: 3, index: 1),
      scrollable: true,
    ),
    (
      name: 'PermissionCard',
      widget: PermissionCard(
        title: 'Notifications',
        subtitle: 'To remind you about your tasks',
        icon: const Icon(Icons.notifications_rounded),
        state: PermissionState.permanentlyDenied,
        onTap: () {},
      ),
      scrollable: true,
    ),
    (
      name: 'PlanCard',
      widget: PlanCard(
        title: 'Yearly',
        price: r'$39.99',
        period: 'per year',
        badge: 'Save 33%',
        footnote: r'$3.33 per month, billed yearly',
        selected: true,
        onTap: () {},
      ),
      scrollable: true,
    ),
    (
      name: 'BenefitRow',
      widget: const BenefitRow(label: 'Multiple tasks from one voice input'),
      scrollable: true,
    ),
    (
      name: 'CrownHeader',
      widget: const CrownHeader(
        title: 'Tasuke Pro',
        subtitle: 'Unlock your full potential',
      ),
      scrollable: true,
    ),
    (
      name: 'TasukeLogo',
      widget: const TasukeLogo(showWordmark: true),
      scrollable: true,
    ),
    (
      name: 'TasukeBanner',
      widget: TasukeBanner(
        message: 'This device may delay reminders to save battery.',
        tone: BannerTone.warning,
        onDismiss: () {},
      ),
      scrollable: true,
    ),
  ];
}

void main() {
  for (final double scale in <double>[1, 2]) {
    group('at $scale× type scale', () {
      testWidgets('nothing in the catalogue overflows or throws', (
        WidgetTester tester,
      ) async {
        final TextEditingController controller = TextEditingController(
          text: 'Send the build to James',
        );
        addTearDown(controller.dispose);
        final ValueNotifier<double> ticker = ValueNotifier<double>(0.7);
        addTearDown(ticker.dispose);

        for (final Specimen specimen in catalogue(controller, ticker)) {
          await pumpWidgetUnderTest(
            tester,
            specimen.widget,
            textScale: scale,
            scrollable: specimen.scrollable,
          );
          await tester.pump(const Duration(milliseconds: 16));

          // A RenderFlex overflow is reported as an exception during paint, so
          // this one assertion covers both halves of the promise.
          expect(
            tester.takeException(),
            isNull,
            reason: '${specimen.name} at $scale×',
          );
        }

        await tearDownTree(tester);
      });
    });
  }

  testWidgets('the overflow check above can actually fail', (
    WidgetTester tester,
  ) async {
    // Without this, a harness that swallowed paint-time errors would make
    // every assertion above pass by doing nothing at all.
    await pumpWidgetUnderTest(
      tester,
      const SizedBox(
        height: 20,
        child: Column(children: <Widget>[Text('one'), Text('two')]),
      ),
      textScale: 2,
    );
    await tester.pump();

    expect(tester.takeException(), isNotNull);
  });
}
