import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/inventory_service.dart';
import '../services/notification_service.dart';
import '../constants.dart';
import 'home_screen.dart';
import 'login_screen.dart'; // Ensure you import your LoginScreen
import '../widgets/diet_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = "Avvio in corso...";
  bool _isMaintenance = false;
  String _maintenanceMsg = "";

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 1. Load Env
      try {
        await dotenv.load(fileName: ".env");
      } catch (_) {}

      // 2. Firebase Core
      setState(() => _status = "Connessione Server...");
      await Firebase.initializeApp();

      // 3. KILL SWITCH (Remote Config)
      setState(() => _status = "Verifica aggiornamenti...");
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(minutes: 1),
          minimumFetchInterval: Duration.zero, // Keep low for beta testing
        ),
      );

      // Defaults
      await remoteConfig.setDefaults({
        "maintenance_mode": false,
        "maintenance_message": "App in manutenzione. Riprova più tardi.",
      });

      await remoteConfig.fetchAndActivate();

      bool maintenanceMode = remoteConfig.getBool('maintenance_mode');
      if (maintenanceMode) {
        setState(() {
          _isMaintenance = true;
          _maintenanceMsg = remoteConfig.getString('maintenance_message');
        });
        return; // STOP EXECUTION HERE
      }

      // 4. Notification & Permissions
      setState(() => _status = "Setup Notifiche...");
      final notifs = NotificationService();
      await notifs.init();
      // Non-blocking permission request is better for UX, but keeping your logic:
      await notifs.requestPermissions();
      try {
        await FirebaseMessaging.instance.subscribeToTopic('all_users');
      } catch (_) {}

      // 5. User Status Check (Banned/Active)
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        setState(() => _status = "Verifica Account...");

        // Force refresh token to ensure validity
        await currentUser.reload();

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data();
          final isActive =
              data?['is_active'] ?? true; // Default to true if missing

          if (!isActive) {
            await FirebaseAuth.instance.signOut();
            if (mounted) _showBannedDialog();
            return;
          }
        }
      }

      // 6. Business Logic
      setState(() => _status = "Caricamento dati...");
      await InventoryService.initialize();

      if (mounted) {
        // Navigate based on Auth State
        Widget nextScreen = (FirebaseAuth.instance.currentUser != null)
            ? const MainScreen()
            : const LoginScreen(); // Redirect to Login if no user

        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => nextScreen));
      }
    } catch (e) {
      if (mounted) {
        // If it's a critical remote config error, ignore and proceed,
        // otherwise show error.
        setState(() => _status = "Errore: $e");
      }
    }
  }

  void _showBannedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Accesso Negato"),
        content: const Text(
          "Il tuo account è stato disabilitato dall'amministratore.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isMaintenance) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.build_circle, size: 80, color: Colors.orange),
                const SizedBox(height: 24),
                const Text(
                  "Manutenzione in corso",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  _maintenanceMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DietLogo(size: 120),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
