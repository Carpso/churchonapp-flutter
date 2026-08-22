import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:church_on_app/core/widgets/church_map.dart';

void main() {
  setUp(() {
    // ChurchMap reads dotenv for the PMTiles source in _initializeProvider.
    dotenv.testLoad(fileInput: 'MAPS_ZAMBIA_URL=https://example.com/zambia');
  });

  testWidgets('ChurchMap renders without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChurchMap(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ChurchMap), findsOneWidget);
  });
}
