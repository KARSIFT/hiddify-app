import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/profile/data/aggregate_config.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/aggregate_profile.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

abstract interface class ConnectionRepository {
  SingboxConfigOption? get configOptionsSnapshot;

  TaskEither<ConnectionFailure, Unit> setup();
  Stream<ConnectionStatus> watchConnectionStatus();

  /// Whether the core is applying a new config without a restart; the connection stays up
  /// (watchConnectionStatus keeps reporting it as connected).
  Stream<bool> watchHotReloading();
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit);
  TaskEither<ConnectionFailure, Unit> disconnect();
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit);
}

class ConnectionRepositoryImpl with ExceptionHandler, InfraLogger implements ConnectionRepository {
  ConnectionRepositoryImpl({
    required this.ref,
    required this.directories,
    required this.singbox,
    required this.configOptionRepository,
    required this.profilePathResolver,
  });

  final Ref ref;

  final Directories directories;
  final HiddifyCoreService singbox;

  final ConfigOptionRepository configOptionRepository;
  final ProfilePathResolver profilePathResolver;

  SingboxConfigOption? _configOptionsSnapshot;
  @override
  SingboxConfigOption? get configOptionsSnapshot => _configOptionsSnapshot;

  bool _initialized = false;

  @override
  TaskEither<ConnectionFailure, Unit> setup() {
    if (_initialized) return TaskEither.of(unit);
    return exceptionHandler(() {
      loggy.debug("setting up singbox");

      return singbox
          .setup()
          .map((r) {
            _initialized = true;
            return r;
          })
          .mapLeft(UnexpectedConnectionFailure.new)
          .run();
    }, UnexpectedConnectionFailure.new);
  }

  @override
  Stream<ConnectionStatus> watchConnectionStatus() {
    return singbox.watchStatus().map(
      (event) => switch (event) {
        CoreStopped() => Disconnected(event.getCoreAlert()),
        CoreStarting() => const Connecting(),
        CoreStarted() => const Connected(),
        CoreStopping() => const Disconnecting(),
        CoreHotReloading() => const Connected(),
      },
    );
  }

  @override
  Stream<bool> watchHotReloading() => singbox.watchStatus().map((event) => event is CoreHotReloading).distinct();

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit) => setup().flatMap(
    (_) => prepareProfile(activeProfile).flatMap(
      (outboundTag) => applyConfigOption(activeProfile).flatMap(
        (_) => singbox
            .start(profilePathResolver.file(activeProfile.id).path, activeProfile.name, disableMemoryLimit)
            .flatMap((_) => _selectPreparedOutbound(outboundTag)),
      ),
    ),
  );

  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => singbox.stop().mapLeft(UnexpectedConnectionFailure.new);

  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      prepareProfile(activeProfile).flatMap(
        // hot reload when possible, restart otherwise
        (outboundTag) => applyConfigOption(activeProfile).flatMap(
          (_) => singbox
              .reload(profilePathResolver.file(activeProfile.id).path, activeProfile.name, disableMemoryLimit)
              .mapLeft<ConnectionFailure>(UnexpectedConnectionFailure.new)
              .flatMap((_) => _selectPreparedOutbound(outboundTag)),
        ),
      );

  TaskEither<ConnectionFailure, Unit> _selectPreparedOutbound(String? outboundTag) {
    if (outboundTag == null) return TaskEither.of(unit);
    return TaskEither.tryCatch(() async {
      try {
        (await singbox.selectOutbound('select', outboundTag).run()).getOrElse((error) => throw error);
      } catch (error, stack) {
        // Never leave the core routing through its default Balance group when
        // the requested automatic mode could not be selected.
        try {
          await singbox.stop().run();
        } catch (stopError) {
          loggy.warning('error stopping after outbound selection failed', stopError);
        }
        Error.throwWithStackTrace(error, stack);
      }
      return unit;
    }, (error, stack) => ConnectionFailure.unexpected(error, stack));
  }

  /// Rebuild on every connect/reload so additions, updates and removals are used.
  TaskEither<ConnectionFailure, String?> prepareProfile(ProfileEntity profile) => TaskEither.tryCatch(() async {
    final mode = AggregateMode.fromId(profile.id);
    if (mode == null) return null;
    final repo = await ref.read(profileRepositoryProvider.future);
    final profiles = (await repo.watchAll().first).getOrElse((err) => throw err);
    final sources = <({String id, String name, Map<String, dynamic> config})>[];
    for (final source in profiles) {
      final content = await profilePathResolver.file(source.id).readAsString();
      sources.add((id: source.id, name: source.name, config: jsonDecode(content) as Map<String, dynamic>));
    }
    final strategy = mode == AggregateMode.lowest ? 'lowest-delay' : ref.read(ConfigOptions.balancerStrategy).key;
    final aggregate = aggregateConfig(sources, strategy: strategy);
    final content = jsonEncode(aggregate.config);
    final temp = profilePathResolver.tempFile(profile.id);
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(profilePathResolver.file(profile.id).path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
    return aggregate.outboundTag;
  }, (err, st) => ConnectionFailure.unexpected(err, st));

  @visibleForTesting
  TaskEither<ConnectionFailure, Unit> applyConfigOption(ProfileEntity prof) =>
      TaskEither.fromEither(configOptionRepository.fullOptionsOverrided(prof.profileOverride()))
          .mapLeft((l) => ConnectionFailure.invalidConfigOption(null, l))
          .flatMap(
            (overridedOptions) => TaskEither.tryCatch(() async {
              if (!overridedOptions.chainStatus.isOff()) {
                final isWarpLicenseAgreed = ref.read(Preferences.warpConsentGiven) == true;
                final isWarpEnabled =
                    overridedOptions.unblocker.mode.isWarp() || overridedOptions.extraSecurity.mode.isWarp();
                if (!isWarpLicenseAgreed && isWarpEnabled) {
                  final isAgreed = await ref.read(dialogNotifierProvider.notifier).showWarpLicense();
                  if (isAgreed == true) {
                    await ref.read(Preferences.warpConsentGiven.notifier).update(true);
                    // return (await applyConfigOption(prof).run()).match((l) => throw l, (_) => unit);
                  } else {
                    throw const MissingWarpLicense();
                  }
                }

                final isPsiphonLicenseAgreed = ref.read(Preferences.psiphonConsentGiven) == true;
                final isPsiphonEnabled =
                    overridedOptions.unblocker.mode.isPsiphon() || overridedOptions.extraSecurity.mode.isPsiphon();
                if (!isPsiphonLicenseAgreed && isPsiphonEnabled) {
                  final isAgreed = await ref.read(dialogNotifierProvider.notifier).showPsiphonLicense();
                  if (isAgreed == true) {
                    await ref.read(Preferences.psiphonConsentGiven.notifier).update(true);
                  } else {
                    throw const MissingPsiphonLicense();
                  }
                }
              }

              _configOptionsSnapshot = overridedOptions;
              await singbox.changeOptions(overridedOptions).run();
              return unit;
            }, (err, st) => err is ConnectionFailure ? err : ConnectionFailure.unexpected(err, st)),
          );
}
