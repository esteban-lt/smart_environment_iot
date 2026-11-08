import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/demo_screen.dart';
import 'screens/historical_alerts_screen.dart';
import 'screens/readings_screen.dart';
import 'sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // SQLite es el ÚNICO almacén offline: se apaga la caché local de Firestore
  // para que nada se "sincronice solo" por detrás de nuestra lógica.
  FirebaseFirestore.instance.settings =
      const Settings(persistenceEnabled: false);

  runApp(const SmartEnvironmentApp());

  // Listener de conectividad + primera sincronización (no bloquea la UI).
  SyncService.instance.start();
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

/// Navegación principal (barra inferior) + barra de estado de sincronización.
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
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const SyncBanner(),
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.notifications_active_outlined),
                label: 'Alertas'),
            NavigationDestination(icon: Icon(Icons.list_alt), label: 'Lecturas'),
            NavigationDestination(icon: Icon(Icons.science), label: 'Demo'),
          ],
        ),
      ]),
    );
  }
}

/// Franja con el estado de red y de la cola de sincronización. Es solo
/// informativa: estar offline NO es un error, la app sigue funcionando.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: SyncService.instance.status,
      builder: (context, s, _) {
        final (icon, color, text) = !s.online
            ? (Icons.cloud_off, Colors.orange.shade800,
                'Sin conexión · ${s.pending} pendientes en SQLite')
            : s.syncing
                ? (Icons.cloud_sync, Colors.blue.shade700, 'Sincronizando…')
                : s.pending > 0
                    ? (Icons.cloud_upload, Colors.blue.shade700,
                        'En línea · ${s.pending} pendientes')
                    : (Icons.cloud_done, Colors.green.shade700,
                        'En línea · todo sincronizado (${s.synced})');
        return Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          ]),
        );
      },
    );
  }
}
