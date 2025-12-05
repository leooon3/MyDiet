import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Inizializza il database dei fusi orari
    tz.initializeTimeZones();

    // 2. OTTIENI IL FUSO ORARIO REALE DEL TELEFONO (Es. "Europe/Rome")
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();

    // 3. Imposta la location locale corretta
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    // Configurazione notifiche (il resto del tuo codice era ok)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('icon'); // Assicurati che l'icona esista!

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  } // --- PROGRAMMA LA SVEGLIA ---

  Future<void> scheduleMealReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      _nextInstanceOfTime(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'meal_channel_id', // ID Canale
          'Promemoria Pasti', // Nome Canale visibile all'utente
          channelDescription: 'Ti ricorda quando mangiare',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Ripeti ogni giorno
    );
    debugPrint("✅ Notifica impostata: $title alle $hour:$minute");
  }

  // Cancella una notifica specifica
  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    debugPrint("🗑️ Notifica $id cancellata");
  }

  // Calcola la prossima occorrenza dell'orario
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

    // Se l'orario è già passato oggi, pianificalo per domani
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
  // ... il resto del codice ...

  // --- NUOVA FUNZIONE DI TEST ---
  Future<void> showInstantNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'test_channel_id',
          'Canale di Test',
          channelDescription: 'Serve per testare se le notifiche funzionano',
          importance: Importance.max,
          priority: Priority.high,
          icon:
              'icon', // Assicurati che corrisponda al nome file in res/drawable
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      888, // ID univoco per il test
      'Test Notifica 🔔',
      'Se leggi questo, il sistema funziona!',
      platformChannelSpecifics,
    );
  }

  Future<bool> checkAndRequestPermissions() async {
    // 1. Controlla lo stato attuale delle notifiche
    var status = await Permission.notification.status;

    // 2. Se non è ancora stato chiesto, chiedilo ora
    if (status.isDenied) {
      status = await Permission.notification.request();
    }

    // 3. Su Android 12+, serve anche il permesso per le sveglie esatte
    if (status.isGranted) {
      var alarmStatus = await Permission.scheduleExactAlarm.status;
      if (alarmStatus.isDenied) {
        // Proviamo a chiederlo (su alcuni Android porta alle impostazioni)
        await Permission.scheduleExactAlarm.request();
      }
    }

    // 4. Se è bloccato permanentemente (l'utente ha fatto "Non chiedere più")
    if (status.isPermanentlyDenied) {
      return false; // Ritorna falso per far scattare il pop-up manuale
    }

    return status.isGranted;
  }
}
