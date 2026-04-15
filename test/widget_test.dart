import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const CCEApp());
    expect(find.text('Configurar servidor'), findsOneWidget);
  });
}
