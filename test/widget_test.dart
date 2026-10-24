import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facturacion_app/main.dart';

void main() {
  testWidgets('permite agregar un producto a la venta', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(const FacturacionApp());

    expect(find.text('Nueva venta'), findsOneWidget);
    expect(find.text('Detalle de venta'), findsOneWidget);
    expect(find.text('Agrega productos para comenzar.'), findsOneWidget);

    await tester.tap(find.text('Polo básico'));
    await tester.pump();

    expect(find.text('Polo básico'), findsNWidgets(2));
    expect(find.text('1'), findsNWidgets(2));
    expect(find.text('Preparar venta'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });
}
