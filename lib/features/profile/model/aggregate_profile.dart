import 'package:hiddify/features/profile/model/profile_entity.dart';

enum AggregateMode {
  lowest,
  balance;

  String get id => 'all-subscriptions-$name';

  static AggregateMode? fromId(String id) {
    for (final mode in values) {
      if (mode.id == id) return mode;
    }
    return null;
  }

  ProfileEntity profile(String label, DateTime revision) =>
      ProfileEntity.local(id: id, active: true, name: label, lastUpdate: revision);
}
