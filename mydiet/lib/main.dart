import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'repositories/diet_repository.dart';
import 'providers/diet_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/inventory_service.dart'; // New Service

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  try {
    await Firebase.initializeApp();
    await FirebaseMessaging.instance.subscribeToTopic('all_users');
  } catch (e) {
    debugPrint("⚠️ Firebase Init Error: $e");
  }

  try {
    final notifs = NotificationService();
    await notifs.init();
    await notifs.requestPermissions();
  } catch (e) {
    debugPrint("⚠️ Notification Init Error: $e");
  }

  // Init Background Tasks
  await InventoryService.initialize();

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => DietRepository()),
        ChangeNotifierProxyProvider<DietRepository, DietProvider>(
          create: (context) => DietProvider(context.read<DietRepository>()),
          update: (context, repo, prev) => prev ?? DietProvider(repo),
        ),
      ],
      child: const DietApp(),
    ),
  );
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
      ),
      home: const MainScreen(),
    );
  }
}
