import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasuke_ai/app/l10n/l10n_context.dart';
import 'package:tasuke_ai/app/router/routes.dart';
import 'package:tasuke_ai/app/theme/tasuke_colors.dart';
import 'package:tasuke_ai/app/theme/tasuke_spacing.dart';
import 'package:tasuke_ai/app/theme/tasuke_typography.dart';
import 'package:tasuke_ai/app/widgets/widgets.dart';
import 'package:tasuke_ai/core/storage/prefs.dart';
import 'package:tasuke_ai/features/onboarding/presentation/widgets/onboarding_illustration.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static const int _pageCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(onboardingSeenProvider.notifier).complete();
    context.go(AppRoute.permissions.path);
  }

  void _next() {
    if (_index >= _pageCount - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_Page> pages = <_Page>[
      _Page(
        title: context.l10n.onboardingTitle1,
        body: context.l10n.onboardingBody1,
        art: TasukeArt.guideVoice,
      ),
      _Page(
        title: context.l10n.onboardingTitle2,
        body: context.l10n.onboardingBody2,
        art: TasukeArt.guideTasks,
      ),
      _Page(
        title: context.l10n.onboardingTitle3,
        body: context.l10n.onboardingBody3,
        art: TasukeArt.guidePrivacy,
      ),
    ];

    return Scaffold(
      backgroundColor: TasukeColors.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(
                  right: TasukeSpacing.gutter,
                  top: TasukeSpacing.sm,
                ),
                child: TextLinkButton(
                  label: context.l10n.actionSkip,
                  onPressed: _finish,
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageCount,
                onPageChanged: (int index) => setState(() => _index = index),
                itemBuilder: (_, int index) => pages[index],
              ),
            ),
            PageDots(count: _pageCount, index: _index),
            const SizedBox(height: TasukeSpacing.xxl),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TasukeSpacing.gutter,
              ),
              child: PrimaryButton(
                label: _index >= _pageCount - 1
                    ? context.l10n.actionContinue
                    : context.l10n.actionNext,
                onPressed: _next,
              ),
            ),
            const SizedBox(height: TasukeSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, required this.art});

  final String title;
  final String body;
  final String art;

  @override
  Widget build(BuildContext context) {
    // ⚠️ Scrolls when it has to. At the largest accessibility text sizes the
    // copy outgrows the pager on every iPhone, and a plain Column clipped the
    // last lines — on page 3, the privacy promise itself.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: TasukeSpacing.gutter),
          child: ConstrainedBox(
            // Centred on a roomy phone, scrollable on a small one.
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                OnboardingIllustration(asset: art),
                const SizedBox(height: TasukeSpacing.huge),
                Text(
                  title,
                  style: TasukeTypography.displayLg,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: TasukeSpacing.lg),
                Text(
                  body,
                  style: TasukeTypography.bodyMd,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
