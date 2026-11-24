import 'package:flutter_test/flutter_test.dart';
import 'package:upi_extractor/main.dart';

void main() {
  testWidgets('App launches with title and navigation destinations', (WidgetTester tester) async {
    await tester.pumpWidget(const UpiExtractorApp());
    expect(find.text('Extract'), findsOneWidget);
    expect(find.text('Mappings'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });
}
