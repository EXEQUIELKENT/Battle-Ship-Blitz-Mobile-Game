import 'package:battleship_blitz/widgets/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('probe timing', (tester) async {
    BuildContext? ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.expand());
      }),
    ));
    AppNotification.show(ctx!, 'fleeting', duration: const Duration(milliseconds: 400));
    Future<void> dump(String tag) async {
      final found = tester.widgetList(find.text('fleeting')).length;
      // ignore: avoid_print
      print('$tag texts=$found');
    }
    await tester.pump(const Duration(milliseconds: 100));
    await dump('t=100');
    await tester.pump(const Duration(milliseconds: 500)); // t=600, past timer
    await dump('t=600');
    await tester.pump(const Duration(milliseconds: 400)); // t=1000
    await dump('t=1000');
    await tester.pump(const Duration(milliseconds: 600)); // t=1600
    await dump('t=1600');
  });
}
