import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget createTestApp(Widget child) {
  return MaterialApp(home: child);
}

extension PumpApp on WidgetTester {
  Future<void> pumpWidgetWithApp(Widget widget) {
    return pumpWidget(
      ProviderScope(
        child: MaterialApp(home: widget),
      ),
    );
  }
}
