import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Timezone
    tz.initializeTimeZones();
    try {
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));
      debugPrint("🌍 Timezone: ${timeZoneInfo.identifier}");
    } catch (e) {
      debugPrint("⚠️ Timezone Error: $e. Fallback UTC.");
      tz.setLocalLocation(tz.UTC);
    }

    // 2. Android: USARE ic_launcher (PNG) NON launcher_icon (XML)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint("🔔 Click: ${details.payload}");
      },
    );

    // 3. Canale Android
    if (Platform.isAndroid) {
      final AndroidNotificationChannel channel =
          const AndroidNotificationChannel(
            'mydiet_channel_id',
            'Promemoria Pasti',
            description: 'Notifiche Dieta',
            importance: Importance.max,
            playSound: true,
          );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    _isInitialized = true;
  }

  // --- PERMESSI ---
  Future<bool> checkPermissions() async {
    if (Platform.isAndroid) {
      // 1. Notifiche (Android 13+)
      final notif = await Permission.notification.status;
      if (notif.isDenied || notif.isPermanentlyDenied) {
        debugPrint("Richiedo permesso Notifiche...");
        final res = await Permission.notification.request();
        if (!res.isGranted) return false;
      }

      // 2. Sveglie Esatte (Android 12+)
      final alarm = await Permission.scheduleExactAlarm.status;
      if (alarm.isDenied) {
        debugPrint("Richiedo permesso Sveglie Esatte...");
        final res = await Permission.scheduleExactAlarm.request();
        if (!res.isGranted) return false; // Potrebbe richiedere riavvio app
      }
      return true;
    }
    return true; // iOS gestito in init
  }

  // --- SCHEDULING ---
  Future<void> scheduleTestNotification() async {
    await init();
    bool hasPerms = await checkPermissions();
    if (!hasPerms) {
      debugPrint("❌ Permessi mancanti per il test!");
      return;
    }

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    // Aggiungiamo 15 secondi per essere sicuri
    final tz.TZDateTime scheduledDate = now.add(const Duration(seconds: 15));

    debugPrint("⏳ Scheduling Test tra 15s: $scheduledDate");

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        999,
        'Funziona! 🚀',
        'Se leggi questo, il sistema è operativo.',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'mydiet_channel_id',
            'Promemoria Pasti',
            importance: Importance.max,
            priority: Priority.high,
            fullScreenIntent: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint("✅ Comando inviato al sistema.");
    } catch (e) {
      debugPrint("❌ Errore ZonedSchedule: $e");
    }
  }

  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    await init();

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'mydiet_channel_id',
            'Promemoria Pasti',
            importance: Importance.max,
            priority: Priority.high,
            fullScreenIntent: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint("📅 Programmato ID $id: $scheduledDate");
    } catch (e) {
      debugPrint("❌ Errore Daily: $e");
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }
}
