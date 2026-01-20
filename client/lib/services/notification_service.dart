import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../services/storage_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  FlutterLocalNotificationsPlugin get flutterLocalNotificationsPlugin =>
      _localNotifications;

  bool _isInitialized = false;

  // [FIX] Nome risorsa senza estensione e senza @drawable/
  // [TEST] Usa l'icona di avvio temporaneamente
  static const String _iconName = '@mipmap/launcher_icon';

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      tz.initializeTimeZones();
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));

      // [FIX] Inizializzazione corretta per Flutter (Raw resource name)
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings(_iconName);

      final DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      final InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(initSettings);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showLocalNotification(message);
      });

      _isInitialized = true;
      debugPrint("✅ Notification Service Initialized");
    } catch (e) {
      debugPrint("⚠️ Notification Init Error: $e");
    }
  }

  Future<void> requestPermissions() async {
    try {
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (Platform.isAndroid) {
        final androidPlugin =
            _localNotifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
        await androidPlugin?.requestExactAlarmsPermission();
      }
    } catch (e) {
      debugPrint("Permission Error: $e");
    }
  }

  Future<String?> getFCMToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      return null;
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            // [FIX] NUOVO ID CANALE per forzare aggiornamento cache Android
            'kybo_channel_v3',
            'Notifiche Kybo',
            channelDescription: 'Canale principale notifiche',
            importance: Importance.max,
            priority: Priority.high,
            icon: _iconName, // [FIX] Icona esplicita
            color: Color(0xFF4CAF50), // Verde Kybo
          ),
        ),
      );
    }
  }

  Future<void> scheduleDietNotifications(dynamic dietPlan) async {
    // Attualmente usiamo gli orari preferiti dell'utente (Allarmi)
    // In futuro qui potrai usare 'dietPlan' per mettere il nome del piatto nella notifica
    await scheduleAllMeals();
    debugPrint("📅 Notifiche dieta aggiornate in base al piano.");
  }

  Future<void> scheduleAllMeals() async {
    if (!_isInitialized) await init();
    await _localNotifications.cancelAll();

    final storage = StorageService();
    List<Map<String, dynamic>> alarms = await storage.loadAlarms();

    for (var alarm in alarms) {
      final int id =
          alarm['id'] ?? DateTime.now().millisecondsSinceEpoch % 100000;
      final String timeStr = alarm['time'] ?? "08:00";
      final parts = timeStr.split(":");

      await _scheduleDaily(
        id,
        alarm['label'] ?? "Pasto",
        alarm['body'] ?? "È ora di mangiare!",
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    }
  }

  Future<void> _scheduleDaily(
    int id,
    String title,
    String body,
    int hour,
    int minute,
  ) async {
    try {
      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        _nextInstanceOf(hour, minute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'kybo_meals_channel_v3', // [FIX] Nuovo ID anche qui
            'Promemoria Pasti',
            channelDescription: 'Canale pasti giornalieri',
            importance: Importance.high,
            priority: Priority.high,
            icon: _iconName, // [FIX] Icona esplicita
            color: Color(0xFF4CAF50),
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint("❌ Errore schedulazione: $e");
    }
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
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
    return scheduledDate;
  }
}
