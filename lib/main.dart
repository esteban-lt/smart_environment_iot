import 'package:flutter/material.dart';

import 'screens/demo_screen.dart';

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
      home: const DemoScreen(),
    );
  }
}
