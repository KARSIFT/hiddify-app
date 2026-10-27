import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:toastification/toastification.dart';

void main() {
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
