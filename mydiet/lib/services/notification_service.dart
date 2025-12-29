import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'storage_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("🌙 Background Notification: ${message.notification?.title}");
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestAlertPermission: false,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        debugPrint("🔔 Notification Tapped: ${details.payload}");
      },
    );

    await _setupFirebaseMessaging();

    _isInitialized = true;
    debugPrint("✅ Notification Service Initialized (Local + Push)");
  }

  Future<void> _setupFirebaseMessaging() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('✅ Push Permissions Granted');
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('☀️ Foreground Message: ${message.notification?.title}');
        if (message.notification != null) {
          _showLocalNotification(
            id: message.hashCode,
            title: message.notification!.title ?? 'Nuova notifica',
            body: message.notification!.body ?? '',
          );
        }
      });
    } else {
      debugPrint('❌ Push Permissions Denied');
    }
  }

  Future<String?> getFCMToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      debugPrint("⚠️ Error getting FCM Token: $e");
      return null;
    }
  }

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'high_importance_channel',
          'Avvisi Importanti',
          importance: Importance.max,
          priority: Priority.high,
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await flutterLocalNotificationsPlugin.show(id, title, body, details);
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.scheduleExactAlarm.status;
      if (status.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
    }
  }

  // --- GESTIONE ALLARMI DINAMICI ---

  Future<void> scheduleAllMeals() async {
    await flutterLocalNotificationsPlugin.cancelAll();

    final storage = StorageService();
    final alarms = await storage.loadAlarms();

    debugPrint("⏰ Scheduling ${alarms.length} alarms...");

    for (var alarm in alarms) {
      int id = alarm['id'] is int
          ? alarm['id']
          : int.tryParse(alarm['id'].toString()) ?? 0;
      String label = alarm['label'] ?? "Pasto";
      String time = alarm['time'] ?? "00:00";
      String body = alarm['body'] ?? "È ora di mangiare!";

      await _scheduleMeal(id, label, body, time);
    }
  }

  Future<void> _scheduleMeal(
    int id,
    String title,
    String body,
    String timeStr,
  ) async {
    try {
      final parts = timeStr.split(":");
      final int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);
      await _scheduleDaily(id, title, body, hour, minute);
      debugPrint("   -> Scheduled '$title' at $timeStr (ID: $id)");
    } catch (e) {
      debugPrint("⚠️ Error parsing time $timeStr for $title: $e");
    }
  }

  Future<void> _scheduleDaily(
    int id,
    String title,
    String body,
    int hour,
    int minute,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'meal_reminders_v2',
          'Promemoria Pasti',
          channelDescription: 'Ricorda i tuoi pasti giornalieri',
          importance: Importance.max,
          priority: Priority.high,
        );

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        _nextInstanceOfTime(hour, minute),
        const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint("⚠️ Exact Alarm Failed, using Inexact: $e");
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        _nextInstanceOfTime(hour, minute),
        const NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
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
