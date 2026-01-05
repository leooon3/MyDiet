import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../services/storage_service.dart'; // Assicurati che l'import sia corretto

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Getter per inventory_service
  FlutterLocalNotificationsPlugin get flutterLocalNotificationsPlugin =>
      _localNotifications;

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 1. Inizializza Timezones (Fondamentale per gli allarmi orari)
      tz.initializeTimeZones();
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));

      // 2. Setup Android
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@drawable/ic_stat_logo');

      // 3. Setup iOS (Permessi base)
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

      // 4. Setup Firebase (Push esterne)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showLocalNotification(message);
      });

      _isInitialized = true;
      debugPrint("✅ Notification Service Initialized (con Timezones)");
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
        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();

        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestExactAlarmsPermission();
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

  /// Mostra notifica push in primo piano
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
            'high_importance_channel',
            'Notifiche Importanti',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  }

  /// [RIPRISTINATO] Schedula gli allarmi salvati in locale
  Future<void> scheduleAllMeals() async {
    if (!_isInitialized) await init();

    // Cancelliamo i vecchi per non averne doppi
    await _localNotifications.cancelAll();

    // Carichiamo gli allarmi salvati dall'utente
    final storage = StorageService();
    List<Map<String, dynamic>> alarms = await storage.loadAlarms();

    debugPrint("⏰ Schedulazione ${alarms.length} allarmi...");

    for (var alarm in alarms) {
      final int id =
          alarm['id'] ?? DateTime.now().millisecondsSinceEpoch % 100000;
      final String timeStr = alarm['time'] ?? "08:00";
      final String title = alarm['label'] ?? "Pasto";
      final String body = alarm['body'] ?? "È ora di mangiare!";

      // Parsing ora:minuti
      final parts = timeStr.split(":");
      final int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);

      await _scheduleDaily(id, title, body, hour, minute);
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
            'daily_meals_channel',
            'Promemoria Pasti',
            channelDescription: 'Canale per gli allarmi dei pasti giornalieri',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents:
            DateTimeComponents.time, // Ripeti ogni giorno alla stessa ora
      );
      debugPrint("✅ Allarme impostato: $title alle $hour:$minute");
    } catch (e) {
      debugPrint("❌ Errore schedulazione $title: $e");
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
