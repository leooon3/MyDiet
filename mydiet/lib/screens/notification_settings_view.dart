import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key});

  @override
  State<NotificationSettingsView> createState() =>
      _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<NotificationSettingsView> {
  final List<Map<String, dynamic>> _meals = [
    {'id': 1, 'label': 'Colazione', 'defaultHour': 8, 'defaultMin': 0},
    {'id': 2, 'label': 'Spuntino Mattina', 'defaultHour': 10, 'defaultMin': 30},
    {'id': 3, 'label': 'Pranzo', 'defaultHour': 13, 'defaultMin': 0},
    {'id': 4, 'label': 'Merenda', 'defaultHour': 16, 'defaultMin': 30},
    {'id': 5, 'label': 'Cena', 'defaultHour': 20, 'defaultMin': 0},
  ];

  final Map<int, bool> _enabled = {};
  final Map<int, TimeOfDay> _times = {};

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (var meal in _meals) {
        int id = meal['id'];
        _enabled[id] = prefs.getBool('meal_enabled_$id') ?? false;

        int h = prefs.getInt('meal_hour_$id') ?? meal['defaultHour'];
        int m = prefs.getInt('meal_min_$id') ?? meal['defaultMin'];
        _times[id] = TimeOfDay(hour: h, minute: m);
      }
    });
  }

  Future<void> _toggleMeal(int id, bool value) async {
    // Se l'utente sta cercando di ATTIVARE
    if (value) {
      // 1. Controllo permessi base (Notifiche)
      bool hasPermission = await NotificationService()
          .checkAndRequestPermissions();
      if (!hasPermission) {
        if (mounted) _showPermissionDialog();
        return; // STOP! Non attivare lo switch graficamente
      }

      // 2. Controllo specifico per le SVEGLIE ESATTE (Android 12+)
      var exactStatus = await Permission.scheduleExactAlarm.status;
      if (exactStatus.isDenied) {
        // Apre le impostazioni di sistema
        await Permission.scheduleExactAlarm.request();

        // STOP! È fondamentale uscire qui.
        // L'utente deve andare nelle impostazioni, attivare la spunta, tornare indietro
        // e ri-cliccare lo switch nell'app. Non possiamo programmare ora.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Abilita 'Sveglie e promemoria' nelle impostazioni e riprova.",
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }

    // Se arriviamo qui, abbiamo TUTTI i permessi. Possiamo salvare e programmare.
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enabled[id] = value;
    });
    await prefs.setBool('meal_enabled_$id', value);

    if (value) {
      _scheduleNotification(id);
    } else {
      NotificationService().cancelNotification(id);
    }
  }

  // --- NUOVO POP-UP ---
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Permessi mancanti ⚠️"),
        content: const Text(
          "Per ricevere i promemoria dei pasti, devi consentire le notifiche nelle impostazioni del telefono.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annulla"),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings(); // <--- Magia: Apre le impostazioni dell'app
            },
            child: const Text("Apri Impostazioni"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(int id) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _times[id]!,
    );

    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _times[id] = picked;
      });
      await prefs.setInt('meal_hour_$id', picked.hour);
      await prefs.setInt('meal_min_$id', picked.minute);

      if (_enabled[id] == true) {
        _scheduleNotification(id);
      }
    }
  }

  void _scheduleNotification(int id) {
    final meal = _meals.firstWhere((m) => m['id'] == id);
    final time = _times[id]!;

    NotificationService().scheduleMealReminder(
      id: id,
      title: "È ora di ${meal['label']}! 🍽️",
      body: "Buon appetito! Ricordati di controllare la dieta.",
      hour: time.hour,
      minute: time.minute,
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Promemoria impostato per le ${time.format(context)}"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Orari Pasti"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _meals.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final meal = _meals[index];
                final int id = meal['id'];
                final bool isEnabled = _enabled[id] ?? false;
                final TimeOfDay time =
                    _times[id] ?? const TimeOfDay(hour: 0, minute: 0);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    meal['label'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    isEnabled
                        ? "Notifica alle ${time.format(context)}"
                        : "Notifiche disattivate",
                    style: TextStyle(
                      color: isEnabled ? Colors.green : Colors.grey,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isEnabled)
                        IconButton(
                          icon: const Icon(
                            Icons.access_time,
                            color: Colors.indigo,
                          ),
                          onPressed: () => _pickTime(id),
                        ),
                      Switch(
                        value: isEnabled,
                        activeTrackColor: Colors.green, // Correzione avviso
                        onChanged: (val) => _toggleMeal(id, val),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // --- TASTO TEST ---
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.grey[100],
            width: double.infinity,
            child: Column(
              children: [
                const Text(
                  "Problemi con le notifiche?",
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () async {
                    // 1. CHIEDI PERMESSO PRIMA DI INVIARE
                    bool hasPermission = await NotificationService()
                        .checkAndRequestPermissions();

                    if (hasPermission) {
                      await NotificationService().showInstantNotification();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Invio test in corso..."),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      }
                    } else {
                      // Se negato, mostra avviso
                      if (context.mounted) _showPermissionDialog();
                    }
                  },
                  icon: const Icon(Icons.notification_important),
                  label: const Text("Invia Notifica di Prova Adesso"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  "Se non la ricevi, controlla le impostazioni Android.",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
