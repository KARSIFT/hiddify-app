import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:toastification/toastification.dart';

void main() {
  testWidgets('rapid Android update results never overlap, including animation frames', (tester) async {
    await tester.pumpWidget(const ToastificationWrapper(child: MaterialApp(home: Scaffold())));
    final notifications = InAppNotificationController();
    notifications.showErrorToast('0 updated, 1 failed');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    for (var i = 0; i < 3; i++) {
      notifications.showErrorToast('0 updated, 1 failed');
      await tester.pump();
      expect(find.text('0 updated, 1 failed').evaluate().length, lessThanOrEqualTo(1));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('0 updated, 1 failed').evaluate().length, lessThanOrEqualTo(1));
    }
    for (var frame = 0; frame < 45; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('0 updated, 1 failed').evaluate().length, lessThanOrEqualTo(1));
    }
    expect(find.text('0 updated, 1 failed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('0 updated, 1 failed'), findsNothing);
  });

  testWidgets('several results queued before a frame leave only the latest card', (tester) async {
    await tester.pumpWidget(const ToastificationWrapper(child: MaterialApp(home: Scaffold())));
    final notifications = InAppNotificationController();
    notifications.showErrorToast('first failure');
    notifications.showErrorToast('second failure');
    notifications.showSuccessToast('latest result');
    for (var frame = 0; frame < 45; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final messages = find.byType(Text).evaluate().map((e) => (e.widget as Text).data);
      expect(
        messages.where((m) => ['first failure', 'second failure', 'latest result'].contains(m)).length,
        lessThanOrEqualTo(1),
      );
    }
    expect(find.text('first failure'), findsNothing);
    expect(find.text('second failure'), findsNothing);
    expect(find.text('latest result'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('update notifications replace the previous message and close automatically', (tester) async {
    await tester.pumpWidget(const ToastificationWrapper(child: MaterialApp(home: Scaffold())));
    final notifications = InAppNotificationController();
    notifications.showSuccessToast('3 subscriptions updated');
    await tester.pumpAndSettle();
    expect(find.text('3 subscriptions updated'), findsOneWidget);

    notifications.showErrorToast('2 updated, 1 failed');
    await tester.pumpAndSettle();
    expect(find.text('3 subscriptions updated'), findsNothing);
    expect(find.text('2 updated, 1 failed'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('2 updated, 1 failed'), findsNothing);
  });
}
