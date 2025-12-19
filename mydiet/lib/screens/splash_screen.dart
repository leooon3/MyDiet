import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/inventory_service.dart';
import '../services/notification_service.dart';
import '../constants.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = "Avvio in corso...";
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 1. Env
      try {
        await dotenv.load(fileName: ".env");
      } catch (e) {
        debugPrint("Env Warning: $e");
      }

      // 2. Firebase
      setState(() => _status = "Connessione Cloud...");
      await Firebase.initializeApp();

      // 3. Services
      setState(() => _status = "Caricamento Servizi...");

      // Non-blocking notifications init
      _initNotifications();

      // Blocking Inventory init
      await InventoryService.initialize();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _status = "Errore di avvio:\n$e";
        });
      }
    }
  }

  Future<void> _initNotifications() async {
    try {
      final notifs = NotificationService();
      await notifs.init();
      // Safe subscribe
      await FirebaseMessaging.instance.subscribeToTopic('all_users');
    } catch (e) {
      debugPrint("Notif Init Error (Safe): $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon.png',
                width: 100,
                height: 100,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.eco, size: 80, color: Colors.white),
              ),
              const SizedBox(height: 24),
              if (_hasError) ...[
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.secondary,
                ),
                const SizedBox(height: 16),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _initializeApp,
                  child: const Text("Riprova"),
                ),
              ] else ...[
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text(_status, style: const TextStyle(color: Colors.white70)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
