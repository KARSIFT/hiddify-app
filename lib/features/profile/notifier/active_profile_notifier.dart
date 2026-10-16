import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/aggregate_profile.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_profile_notifier.g.dart';

@Riverpod(keepAlive: true)
class ActiveProfile extends _$ActiveProfile with AppLogger {
  @override
  Stream<ProfileEntity?> build() {
    loggy.debug("watching active profile");
    final mode = ref.watch(Preferences.aggregateMode);
    if (mode != null) {
      final t = ref.watch(translationsProvider).requireValue.pages.profiles;
      return ref
          .watch(profileDataSourceProvider)
          .watchAll(sort: ProfilesSort.name, sortMode: SortMode.ascending)
          .map(
            (profiles) => profiles.isEmpty
                ? null
                : mode.profile(
                    mode == AggregateMode.lowest ? t.allSubscriptionsLowest : t.allSubscriptionsBalance,
                    DateTime.now(),
                  ),
          );
    }
    return ref.watch(profileDataSourceProvider).watchActiveProfile().map((event) => event?.toEntity());
  }
}

// TODO: move to specific feature
@Riverpod(keepAlive: true)
Stream<bool> hasAnyProfile(Ref ref) {
  return ref.watch(profileDataSourceProvider).watchProfilesCount().map((event) => event != 0).distinct();
}
