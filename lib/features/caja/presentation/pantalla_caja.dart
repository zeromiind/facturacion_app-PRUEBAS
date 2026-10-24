import 'package:flutter/material.dart';

class PantallaCaja extends StatelessWidget {
  const PantallaCaja({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caja')),
      body: const Center(
        child: Text('Apertura / cobro (próximamente)'),
      ),
    );
  }
}
