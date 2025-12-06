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

  // IMPORTANTE: Cambiando questo ID, Android resetta le impostazioni delle notifiche per l'app
  static const String _channelId = 'mydiet_channel_v3';
  static const String _channelName = 'Promemoria Pasti';
  static const String _channelDesc = 'Notifiche per colazione, pranzo e cena';

  Future<void> init() async {
    if (_isInitialized) return;

    // FIX: Evita crash su Windows/Linux
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      debugPrint("⚠️ Notifiche disabilitate su Desktop (Windows/Linux).");
      return;
    }

    try {
      // 1. Inizializza Timezone
      tz.initializeTimeZones();
      try {
        final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));
        debugPrint("🌍 Timezone rilevato: ${timeZoneInfo.identifier}");
      } catch (e) {
        debugPrint("⚠️ Errore Timezone: $e. Uso UTC.");
        tz.setLocalLocation(tz.UTC);
      }

      // 2. Configurazione Icone e Permessi Base
      // Usa @mipmap/ic_launcher per garantire la compatibilità con l'icona dell'app
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
            macOS: initializationSettingsDarwin,
          );

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint("🔔 Notifica cliccata: ${details.payload}");
        },
      );

      // 3. Configurazione Canale Android (Specifico per Oppo/Realme/Xiaomi)
      if (Platform.isAndroid) {
        final androidImplementation = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        if (androidImplementation != null) {
          // Richiesta permessi specifica per Android 13+ tramite il plugin
          await androidImplementation.requestNotificationsPermission();

          // Creazione Canale ad Alta Priorità
          const AndroidNotificationChannel channel = AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.max, // Fondamentale per il banner
            playSound: true,
            enableVibration: true,
          );

          await androidImplementation.createNotificationChannel(channel);
        }
      }

      _isInitialized = true;
      debugPrint("✅ NotificationService pronto.");
    } catch (e) {
      debugPrint("❌ Errore Init Notifiche: $e");
    }
  }

  /// Controlla e richiede i permessi di sistema (Settings Android)
  Future<bool> checkPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    if (Platform.isAndroid) {
      // 1. Notifiche (Android 13+)
      final statusNotif = await Permission.notification.status;
      if (statusNotif.isDenied || statusNotif.isPermanentlyDenied) {
        debugPrint("Richiesta permesso NOTIFICHE al sistema...");
        final res = await Permission.notification.request();
        if (!res.isGranted) {
          debugPrint("❌ Permesso Notifiche NEGATO.");
          return false;
        }
      }

      // 2. Sveglie Esatte (Android 12+) - Necessario per schedule esatto
      final statusAlarm = await Permission.scheduleExactAlarm.status;
      if (statusAlarm.isDenied) {
        debugPrint("Richiesta permesso SVEGLIE ESATTE...");
        final res = await Permission.scheduleExactAlarm.request();
        if (!res.isGranted) {
          debugPrint(
            "⚠️ Permesso Sveglie Esatte negato (le notifiche potrebbero ritardare).",
          );
          // Non blocchiamo l'app, ma avvisiamo
        }
      }
      return true;
    }
    return true;
  }

  /// Pianifica una notifica di test tra 15 secondi
  Future<void> scheduleTestNotification() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    await init();
    bool hasPerms = await checkPermissions();
    if (!hasPerms) {
      debugPrint("❌ Impossibile inviare test: permessi mancanti.");
      return;
    }

    // Calcola orario: Adesso + 15 secondi
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    final tz.TZDateTime scheduledDate = now.add(const Duration(seconds: 15));

    debugPrint("⏳ Scheduling Test su canale $_channelId per: $scheduledDate");

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        999, // ID univoco per il test
        'Funziona! 🚀',
        'Se leggi questo, il sistema è operativo al 100%.',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            enableVibration: true,
            playSound: true,
            // fullScreenIntent: true, // Decommentare se serve popup a schermo intero
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode
            .exactAllowWhileIdle, // Più aggressivo per superare Doze mode
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint("✅ Comando inviato correttamente.");
    } catch (e) {
      debugPrint("❌ Errore ZonedSchedule: $e");
    }
  }

  /// Pianifica le notifiche giornaliere dei pasti
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

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

    // Se l'orario è già passato oggi, pianifica per domani
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
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents:
            DateTimeComponents.time, // Ripeti ogni giorno alla stessa ora
      );
      debugPrint("📅 Notifica $id programmata per: $scheduledDate");
    } catch (e) {
      debugPrint("❌ Errore Daily Schedule: $e");
    }
  }

  Future<void> cancelNotification(int id) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<void> cancelAll() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}
