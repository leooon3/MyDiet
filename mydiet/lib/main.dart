import 'package:flutter/material.dart';
import 'package:mydiet/services/notification_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Non usiamo await qui per non bloccare lo splash screen.
  // L'init è gestito internamente in modo sicuro o può essere chiamato nella HomeScreen.
  NotificationService().init();

  runApp(const DietApp());
}

class DietApp extends StatelessWidget {
  const DietApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NutriScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          secondary: const Color(0xFFE65100),
          surface: const Color(0xFFF5F7F6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF1B5E20),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
          iconTheme: IconThemeData(color: Color(0xFF1B5E20)),
        ),
      ),
      home: const MainScreen(),
    );
  }
}
