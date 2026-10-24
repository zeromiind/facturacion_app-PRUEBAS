import 'package:flutter/material.dart';

class PantallaCocina extends StatelessWidget {
  const PantallaCocina({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cocina')),
      body: const Center(
        child: Text('Pantalla de comandas (próximamente)'),
      ),
    );
  }
}
