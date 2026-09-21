import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasuke_ai/core/clock/clock_provider.dart';
import 'package:tasuke_ai/core/database/database_provider.dart';
import 'package:tasuke_ai/features/usage/data/drift_usage_repository.dart';
import 'package:tasuke_ai/features/usage/domain/daily_usage.dart';

final Provider<UsageRepository> usageRepositoryProvider =
    Provider<UsageRepository>(
      (Ref ref) => DriftUsageRepository(dao: ref.watch(usageDaoProvider)),
    );

/// Today's voice usage.
///
/// Watches [todayProvider], so invalidating that at midnight re-points this at
/// the new day's row — which is what makes the free quota reset without the app
/// being restarted.
final StreamProvider<DailyUsage> todayUsageProvider =
    StreamProvider<DailyUsage>(
      (Ref ref) => ref
          .watch(usageRepositoryProvider)
          .watchToday(ref.watch(todayProvider)),
    );
