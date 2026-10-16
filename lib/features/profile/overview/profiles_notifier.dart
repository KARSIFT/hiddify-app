import 'dart:async';

import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/aggregate_profile.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_notifier.g.dart';

@riverpod
class ProfilesSortNotifier extends _$ProfilesSortNotifier with AppLogger {
  @override
  ({ProfilesSort by, SortMode mode}) build() => ref.watch(Preferences.profilesSort);

  void changeSort(ProfilesSort sortBy) {
    ref.read(Preferences.profilesSort.notifier).update((
      by: sortBy,
      mode: switch (sortBy) {
        ProfilesSort.name => SortMode.ascending, // A → Z
        ProfilesSort.lastUpdate => SortMode.descending, // newest first
      },
    ));
  }

  void toggleMode() {
    final current = ref.read(Preferences.profilesSort);
    ref.read(Preferences.profilesSort.notifier).update((
      by: current.by,
      mode: current.mode == SortMode.ascending ? SortMode.descending : SortMode.ascending,
    ));
  }
}

@riverpod
class ProfilesNotifier extends _$ProfilesNotifier with AppLogger {
  @override
  Stream<List<ProfileEntity>> build() {
    final sort = ref.watch(profilesSortNotifierProvider);
    final mode = ref.watch(Preferences.aggregateMode);
    final t = ref.watch(translationsProvider).requireValue.pages.profiles;
    return _profilesRepo.watchAll(sort: sort.by, sortMode: sort.mode).map((event) {
      final profiles = event.getOrElse((l) => throw l);
      if (profiles.isEmpty) return profiles;
      return [
        for (final choice in AggregateMode.values)
          choice
              .profile(
                choice == AggregateMode.lowest ? t.allSubscriptionsLowest : t.allSubscriptionsBalance,
                DateTime.fromMillisecondsSinceEpoch(0),
              )
              .copyWith(active: mode == choice),
        for (final profile in profiles) profile.copyWith(active: mode == null && profile.active),
      ];
    });
  }

  ProfileRepository get _profilesRepo => ref.read(profileRepositoryProvider).requireValue;

  Future<Unit> selectActiveProfile(String id) async {
    loggy.debug('changing active profile to: [$id]');
    await ref.read(hapticServiceProvider.notifier).lightImpact();
    final mode = AggregateMode.fromId(id);
    if (mode != null) {
      await ref.read(Preferences.aggregateMode.notifier).update(mode);
      return unit;
    }
    // Set the real profile first so leaving aggregate mode restores this choice.
    await _profilesRepo.setAsActive(id).getOrElse((err) => throw err).run();
    await ref.read(Preferences.aggregateMode.notifier).update(null);
    return unit;
  }

  Future<void> togglePin(ProfileEntity profile) async {
    loggy.debug('toggling pin for profile: [${profile.id}] -> ${!profile.pinned}');
    await _profilesRepo.setPinned(profile.id, !profile.pinned).getOrElse((err) {
      loggy.warning('failed to toggle pin for [${profile.id}]', err);
      throw err;
    }).run();
  }

  Future<void> deleteProfile(ProfileEntity profile) async {
    loggy.debug('deleting profile: ${profile.name}');

    if (profile.active) await ref.read(connectionNotifierProvider.notifier).abortConnection();
    await _profilesRepo
        .deleteById(profile.id, profile.active)
        .match(
          (err) {
            loggy.warning('failed to delete profile', err);
            throw err;
          },
          (_) async {
            loggy.info('successfully deleted profile, was active? [${profile.active}]');
            final t = ref.read(translationsProvider).requireValue;
            ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.profiles.msg.delete.success);

            final activePrfile = await ref.read(activeProfileProvider.future);
            if (activePrfile != null && AggregateMode.fromId(activePrfile.id) != null) {
              await ref.read(connectionNotifierProvider.notifier).reconnect(activePrfile);
            }
            if (profile.id == ref.read(ConfigOptions.extraSecurityProfileId)) {
              ref.read(ConfigOptions.extraSecurityProfileId.notifier).update(activePrfile?.id);
            }
            if (profile.id == ref.read(ConfigOptions.unblockerProfileId)) {
              ref.read(ConfigOptions.unblockerProfileId.notifier).update(activePrfile?.id);
            }

            return unit;
          },
        )
        .run();
  }

  Future<void> exportConfigToClipboard(ProfileEntity profile) async {
    await _profilesRepo
        .generateConfig(profile.id)
        .match(
          (err) {
            loggy.warning('error generating config', err);
            throw err;
          },
          (configJson) async {
            await Clipboard.setData(ClipboardData(text: configJson));
            final t = ref.read(translationsProvider).requireValue;
            ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
          },
        )
        .run();
  }
}
