import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cce_app/main.dart';

void main() {
  // Smoke test del arranque: la app construye (tema, fuentes, splash) y
  // renderiza el primer frame "Preparando tu hogar".
  //
  // NO se avanza más allá del splash a propósito: ServerConfig tiene host por
  // defecto (isConfigured == true), así que pasado el timer el home real
  // abriría sockets y HTTP, que no existen en el entorno de test. El texto
  // viejo 'Configurar servidor' era de AlarmView (flujo previo al splash);
  // este test no corría en CI mientras la dep material_design_icons rompía la
  // compilación del test target — hoy la fuente MDI está vendoreada.
  testWidgets('App renders', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CCEApp());
    expect(find.text('Preparando tu hogar...'), findsOneWidget);

    // Desmonta ANTES de que el timer del splash (2.5s) navegue al home; el
    // dispose del splash cancela el timer y el test termina sin pendientes.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
