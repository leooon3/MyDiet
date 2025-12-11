import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'repositories/diet_repository.dart';
import 'providers/diet_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'models/pantry_item.dart';

// --- BACKGROUND TASK LOGIC ---
const String taskInventoryCheck = "inventoryCheck";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == taskInventoryCheck) {
      // 1. Initialize dependencies inside the background isolate
      final notifs = NotificationService();
      await notifs.init();

      // 2. Load Data from Storage
      final storage = StorageService();
      final diet = await storage.loadDiet();
      final pantry = await storage.loadPantry();

      if (diet == null) return Future.value(true);

      // 3. Determine Tomorrow's Day Name
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dayName = _getDayName(tomorrow.weekday);

      // 4. Check if ingredients are missing
      if (diet.containsKey(dayName)) {
        bool missing = _checkMissingIngredients(diet[dayName], pantry);

        if (missing) {
          // 5. Trigger Notification directly
          await notifs.flutterLocalNotificationsPlugin.show(
            999, // Unique ID for inventory alert
            "Occhio alla spesa! 🛒",
            "Ti mancano alcuni ingredienti per domani ($dayName).",
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'inventory_channel',
                'Inventory Checks',
                channelDescription: 'Alerts for missing ingredients',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
          );
        }
      }
    }
    return Future.value(true);
  });
}

// Helper to get Italian day name
String _getDayName(int weekday) {
  const days = [
    "Lunedì",
    "Martedì",
    "Mercoledì",
    "Giovedì",
    "Venerdì",
    "Sabato",
    "Domenica",
  ];
  // DateTime.weekday returns 1 for Monday, 7 for Sunday
  return days[weekday - 1];
}

// Logic to compare Plan vs Pantry
bool _checkMissingIngredients(
  Map<String, dynamic> dayPlan,
  List<PantryItem> pantry,
) {
  // Iterate all meals (Pranzo, Cena, etc.)
  for (var meal in dayPlan.values) {
    if (meal is List) {
      for (var dish in meal) {
        String dishName = dish['name'].toString().toLowerCase();
        // Skip placeholders
        if (dishName.contains("libero") || dishName.contains("avanzi")) {
          continue;
        }

        // Check if exists in pantry (Simple check)
        bool found = pantry.any(
          (item) =>
              item.name.toLowerCase().contains(dishName) ||
              dishName.contains(item.name.toLowerCase()),
        );

        if (!found) return true; // Found at least one missing item
      }
    }
  }
  return false;
}

// --- MAIN APP ---

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Init Environment
  await dotenv.load(fileName: ".env");

  // 2. Init Firebase (Push Notifications)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init error (ignore if testing offline): $e");
  }

  // 3. Init Local Notifications
  await NotificationService().init();

  // 4. Init Workmanager (Background Tasks)
  try {
    await Workmanager().initialize(callbackDispatcher);
    // Schedule the check to run periodically (every 24 hours)
    await Workmanager().registerPeriodicTask(
      "1",
      taskInventoryCheck,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.not_required),
    );
  } catch (e) {
    debugPrint("Workmanager init error: $e");
  }

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
