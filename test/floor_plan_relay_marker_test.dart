// El marcador del RELÉ-PULSADOR en el plano (EugeValeiras/CCE#40).
//
// El plano tiene TRES lecturas que el usuario tiene que poder separar de un
// vistazo: encendido, apagado y "no reporta estado" (el relé en detach). Este
// test monta el canvas real con los cuatro casos sembrados —una luz encendida,
// una apagada, una sin conexión y el relé con `state.on: true`— y verifica que
// el relé sea el ÚNICO con el rótulo "Pulsador" y que las excepciones que ya
// vivían en esa misma función (cerradura, robot) sigan intactas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cce_app/models/device.dart';
import 'package:cce_app/models/floor_plan.dart';
import 'package:cce_app/models/server_config.dart';
import 'package:cce_app/services/devices_service.dart';
import 'package:cce_app/services/socket_service.dart';
import 'package:cce_app/services/ui_settings_service.dart';
import 'package:cce_app/views/floor_plan_tab.dart';

Device dev(
  String id,
  String name,
  String type,
  List<String> caps, {
  bool on = false,
  bool reachable = true,
  Map<String, dynamic>? sensor,
}) =>
    Device.fromJson(<String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'capabilities': caps,
      'state': {'on': on, 'bri': on ? 200 : 1, 'reachable': reachable},
      'sensor': ?sensor,
    });

/// El relé real de la casa: `state.on: true` y alcanzable — el caso del bug.
final relay = dev(
  'dev_6ce4a4fffe449134',
  'Living patio interno',
  'eWeLink Switch Button',
  ['sensor', 'button', 'switch'],
  on: true,
  sensor: {'lastKey': 0},
);
final lightOn = dev('dev_on', 'Living left', 'Extended color light',
    ['brightness', 'color_hsv', 'color_temperature', 'switch'],
    on: true);
final lightOff = dev('dev_off', 'TV left light', 'Extended color light',
    ['brightness', 'color_hsv', 'color_temperature', 'switch']);
final lightOffline = dev('dev_offline', 'TV right light',
    'Extended color light', ['brightness', 'switch'],
    reachable: false);

void main() {
  const planSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"></svg>';

  Widget canvas(List<Device> devices, Map<String, LightPosition> positions) {
    final service =
        DevicesService(config: ServerConfig(), socket: SocketService());
    service.debugSeedDevices(devices);
    service.debugSeedFloorPlans(FloorPlansData(
      plans: [FloorPlan.fromJson({'id': 'p1', 'name': 'Living', 'svg': planSvg})],
      activePlanId: 'p1',
      positions: {'p1': positions},
    ));
    return MaterialApp(
      home: Scaffold(
        body: FloorPlanPanel(
          service: service,
          ui: UiSettingsService(),
          planId: 'p1',
          showPlanChips: false,
        ),
      ),
    );
  }

  testWidgets('el relé es el único marcador rotulado "Pulsador"',
      (tester) async {
    await tester.pumpWidget(canvas(
      [relay, lightOn, lightOff, lightOffline],
      {
        'dev_6ce4a4fffe449134': LightPosition(100, 150),
        'dev_on': LightPosition(60, 40),
        'dev_off': LightPosition(140, 40),
        'dev_offline': LightPosition(100, 95),
      },
    ));
    await tester.pump();

    expect(find.text('Pulsador'), findsOneWidget,
        reason: 'el relé se rotula; las tres luces no');
  });

  testWidgets('una luz encendida NO se rotula, aunque comparta state.on',
      (tester) async {
    await tester.pumpWidget(canvas([lightOn], {'dev_on': LightPosition(100, 100)}));
    await tester.pump();
    expect(find.text('Pulsador'), findsNothing);
  });

  testWidgets('la cerradura y el robot conservan su propio marcador',
      (tester) async {
    final lock = dev('dev_lock', 'Puerta', 'EZVIZ lock', ['lock'], on: true);
    final vacuum = dev('dev_vac', 'Roborock', 'Robotic vacuum', ['vacuum']);
    await tester.pumpWidget(canvas(
      [lock, vacuum],
      {'dev_lock': LightPosition(60, 100), 'dev_vac': LightPosition(140, 100)},
    ));
    await tester.pump();

    expect(find.text('Pulsador'), findsNothing,
        reason: 'ni la cerradura ni el robot caen en la rama del relé');
  });
}
