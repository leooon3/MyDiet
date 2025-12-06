import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

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
    for (var meal in _meals) {
      int id = meal['id'];
      _enabled[id] = false;
      _times[id] = TimeOfDay(
        hour: meal['defaultHour'],
        minute: meal['defaultMin'],
      );
    }
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
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
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      // Controllo esplicito permessi
      bool granted = await NotificationService().checkPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Permessi negati nelle impostazioni Android!"),
            ),
          );
        }
        return; // Non attivare lo switch
      }
    }

    setState(() => _enabled[id] = value);
    await prefs.setBool('meal_enabled_$id', value);

    if (value) {
      _scheduleNotification(id);
    } else {
      NotificationService().cancelNotification(id);
    }
  }

  Future<void> _pickTime(int id) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _times[id]!,
    );

    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      setState(() => _times[id] = picked);
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

    NotificationService().scheduleDailyNotification(
      id: id,
      title: "È ora di ${meal['label']}! 🍽️",
      body: "Buon appetito!",
      hour: time.hour,
      minute: time.minute,
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Impostato: ${time.format(context)}")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Promemoria Pasti")),
      body: Column(
        children: [
          Container(
            color: Colors.orange[50],
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            child: Column(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.timer_3),
                  label: const Text("TEST NOTIFICA (15s)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    NotificationService().scheduleTestNotification();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Chiudi l'app ora! Attendi 15s..."),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  "1. Premi il tasto\n2. Esci dall'app (Home)\n3. Spegni lo schermo\n4. Aspetta 15 secondi",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.separated(
              itemCount: _meals.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final meal = _meals[index];
                final int id = meal['id'];
                final bool isEnabled = _enabled[id] ?? false;
                final TimeOfDay time = _times[id]!;

                return ListTile(
                  title: Text(meal['label']),
                  subtitle: Text(isEnabled ? time.format(context) : "Off"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isEnabled)
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _pickTime(id),
                        ),
                      Switch(
                        value: isEnabled,
                        activeThumbColor: Colors.green,
                        onChanged: (val) => _toggleMeal(id, val),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
