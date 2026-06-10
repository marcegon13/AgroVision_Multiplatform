import 'package:flutter/material.dart';
import 'presentation/home/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AgroVisionApp());
}

class AgroVisionApp extends StatelessWidget {
  const AgroVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroVision Offline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4AF37), // Dorado
          secondary: Color(0xFF9E782F), // Marrón/Dorado oscuro
          surface: Color(0xFF121212), // Tarjetas oscuras
          onSurface: Color(0xFFE5E7EB),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000), // Negro profundo
      ),
      home: const HomePage(),
    );
  }
}
