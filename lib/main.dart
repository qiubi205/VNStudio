import 'package:flutter/material.dart';
import 'screens.dart';

void main() {
  runApp(const VnStudioApp());
}

class VnStudioApp extends StatelessWidget {
  const VnStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VN Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF7C6CFF),
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}
