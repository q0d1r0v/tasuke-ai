import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/models/model_installer.dart';
import 'package:tasuke_ai/core/models/model_providers.dart';

/// The extractor model's state, synchronously.
///
/// The router's redirect and the mic button both need an answer on the frame
/// they are built, and neither can render an `AsyncValue`: a guard that returns
/// "loading" sends the user to the splash, and a mic button that shows a
/// spinner while the stream warms up flickers on every cold start. Falling back
/// to the installer's last known state gives a real answer immediately.
final Provider<ModelState> currentExtractorModelStateProvider =
    Provider<ModelState>((Ref ref) {
      final AsyncValue<ModelState> live = ref.watch(
        extractorModelStateProvider,
      );
      return live.value ??
          ref.watch(modelInstallerProvider).stateOf(TasukeModels.extractor);
    });
