import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

class _Notifications extends InAppNotificationController {
  final messages = <String>[];

  @override
  ToastificationItem? showErrorToast(String message) {
    messages.add(message);
    return null;
  }

  @override
  ToastificationItem? showSuccessToast(String message, {ToastAction? action}) {
    messages.add(message);
    return null;
  }
}

class _Profiles implements ProfileRepository {
  final profiles = List.generate(
    3,
    (i) =>
        ProfileEntity.remote(
              id: '$i',
              active: i == 0,
              name: 'Provider $i',
              url: 'https://example.com/$i',
              lastUpdate: DateTime(2020),
              options: const ProfileOptions(updateInterval: Duration(hours: 1)),
            )
            as RemoteProfileEntity,
  );
  final failures = <String>{};

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) => Stream.value(right(profiles));

  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(String url, {UserOverride? userOverride, CancelToken? cancelToken}) =>
      failures.contains(url) ? TaskEither.left(const ProfileFailure.unexpected()) : TaskEither.of(unit);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Active extends ActiveProfile {
  _Active(this.profile);
  ProfileEntity? profile;
  @override
  Stream<ProfileEntity?> build() => Stream.value(profile);
}

class _Reconnect extends ConnectionNotifier {
  bool? reportedError;
  @override
  Stream<ConnectionStatus> build() => Stream.value(const Connected());
  @override
  Future<void> reconnect(ProfileEntity? profile, {bool reportError = true}) {
    reportedError = reportError;
    return Future.error(StateError('reload failed'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _Profiles repo;
  late _Notifications notifications;
  late _Reconnect connection;
  late _Active active;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'intro_completed': false});
    final prefs = await SharedPreferences.getInstance();
    active = _Active(null);
    repo = _Profiles();
    notifications = _Notifications();
    connection = _Reconnect();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
        translationsProvider.overrideWith((ref) => AppLocale.en.build()),
        profileRepositoryProvider.overrideWith((ref) => repo),
        inAppNotificationControllerProvider.overrideWithValue(notifications),
        activeProfileProvider.overrideWith(() => active),
        connectionNotifierProvider.overrideWith(() => connection),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    await container.read(translationsProvider.future);
    await container.read(profileRepositoryProvider.future);
    await container.read(activeProfileProvider.future);
  });
  tearDown(() => container.dispose());

  test('several successful subscription updates produce one summary', () async {
    await container.read(foregroundProfilesUpdateNotifierProvider.notifier).updateProfiles();
    final t = container.read(translationsProvider).requireValue;
    expect(notifications.messages, [t.pages.profiles.msg.update.bulkSuccess(count: 3)]);
  });

  test('multiple failures are combined with successful updates in one summary', () async {
    repo.failures.addAll(repo.profiles.take(2).map((profile) => profile.url));
    await container.read(foregroundProfilesUpdateNotifierProvider.notifier).updateProfiles();
    final t = container.read(translationsProvider).requireValue;
    expect(notifications.messages, [
      t.pages.profiles.msg.update.bulkPartial(success: 1, failed: 2, names: 'Provider 0, Provider 1'),
    ]);
  });

  test('reconnect errors stay in the bulk result without opening dialogs', () async {
    active.profile = repo.profiles.first;
    container.invalidate(activeProfileProvider);
    await container.read(activeProfileProvider.future);
    await container.read(updateProfileNotifierProvider('0').notifier).updateProfile(repo.profiles.first, isBulk: true);
    expect(connection.reportedError, false);
    expect(container.read(updateProfileNotifierProvider('0')).hasError, true);
    expect(notifications.messages, isEmpty);
  });
}
