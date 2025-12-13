import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import '../models/pantry_item.dart';

const String taskInventoryCheck = "inventoryCheck";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == taskInventoryCheck) {
      final notifs = NotificationService();
      await notifs.init();

      final storage = StorageService();
      final diet = await storage.loadDiet();
      final pantry = await storage.loadPantry();

      if (diet == null) return Future.value(true);

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dayName = _getDayName(tomorrow.weekday);

      if (diet['plan'] != null && diet['plan'][dayName] != null) {
        bool missing = _checkMissingIngredients(diet['plan'][dayName], pantry);

        if (missing) {
          await notifs.flutterLocalNotificationsPlugin.show(
            999,
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

class InventoryService {
  static Future<void> initialize() async {
    try {
      // ignore: deprecated_member_use
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        "1",
        taskInventoryCheck,
        frequency: const Duration(hours: 24),
        constraints: Constraints(networkType: NetworkType.notRequired),
      );
    } catch (e) {
      // Handle error
    }
  }
}

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
  return days[weekday - 1];
}

bool _checkMissingIngredients(
  Map<String, dynamic> dayPlan,
  List<PantryItem> pantry,
) {
  for (var meal in dayPlan.values) {
    if (meal is List) {
      for (var dish in meal) {
        String dishName = dish['name'].toString().toLowerCase();
        if (dishName.contains("libero") || dishName.contains("avanzi")) {
          continue;
        }

        bool found = pantry.any(
          (item) =>
              item.name.toLowerCase().contains(dishName) ||
              dishName.contains(item.name.toLowerCase()),
        );

        if (!found) return true;
      }
    }
  }
  return false;
}
