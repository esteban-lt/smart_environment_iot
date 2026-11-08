import 'package:flutter/material.dart';

import 'screens/demo_screen.dart';
import 'screens/historical_alerts_screen.dart';
import 'screens/readings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartEnvironmentApp());
}

class SmartEnvironmentApp extends StatelessWidget {
  const SmartEnvironmentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart-Environment IoT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

/// Navegación principal (barra inferior).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Se reconstruye la pestaña al cambiar, así cada una lee la BD fresca.
      body: [
        const HistoricalAlertsScreen(),
        const ReadingsScreen(),
        const DemoScreen(),
      ][_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.notifications_active_outlined), label: 'Alertas'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Lecturas'),
          NavigationDestination(icon: Icon(Icons.science), label: 'Demo'),
        ],
      ),
    );
  }
}
