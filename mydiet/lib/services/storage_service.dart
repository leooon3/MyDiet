import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';

class StorageService {
  final _storage = const FlutterSecureStorage();

  // --- EXISTING METHODS ---

  Future<Map<String, dynamic>?> loadDiet() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('diet_plan');
    if (jsonString == null) return null;
    return jsonDecode(jsonString);
  }

  Future<void> saveDiet(Map<String, dynamic> dietData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('diet_plan', jsonEncode(dietData));
  }

  Future<List<PantryItem>> loadPantry() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('pantry');
    if (jsonString == null) return [];
    List<dynamic> list = jsonDecode(jsonString);
    return list.map((e) => PantryItem.fromJson(e)).toList();
  }

  Future<void> savePantry(List<PantryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pantry',
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<Map<String, ActiveSwap>> loadSwaps() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('active_swaps');
    if (jsonString == null) return {};
    Map<String, dynamic> map = jsonDecode(jsonString);
    return map.map((k, v) => MapEntry(k, ActiveSwap.fromJson(v)));
  }

  Future<void> saveSwaps(Map<String, ActiveSwap> swaps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'active_swaps',
      jsonEncode(swaps.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  // --- [FIXED] GESTIONE ALLARMI DINAMICI ---

  /// Carica la lista degli allarmi. Restituisce i default se null o VUOTA.
  Future<List<Map<String, dynamic>>> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    String? raw = prefs.getString('custom_alarms');

    // Lista di default definita qui per riutilizzo
    final defaultAlarms = [
      {
        'id': 10,
        'label': 'Colazione ☕',
        'time': '08:00',
        'body': 'È ora di fare il pieno di energia!',
      },
      {
        'id': 11,
        'label': 'Pranzo 🥗',
        'time': '13:00',
        'body': 'Buon appetito! Segui il piano.',
      },
      {
        'id': 12,
        'label': 'Cena 🍽️',
        'time': '20:00',
        'body': 'Chiudi la giornata con gusto.',
      },
    ];

    if (raw == null) {
      return defaultAlarms;
    }

    try {
      List<dynamic> decoded = jsonDecode(raw);
      // [FIX CRITICO] Se la lista salvata è vuota, ricarica i default
      if (decoded.isEmpty) {
        return defaultAlarms;
      }
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      return defaultAlarms;
    }
  }

  Future<void> saveAlarms(List<Map<String, dynamic>> alarms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_alarms', jsonEncode(alarms));
  }

  // Retro-compatibilità (opzionale)
  Future<Map<String, String>> loadMealTimes() async {
    final prefs = await SharedPreferences.getInstance();
    String? raw = prefs.getString('meal_times');
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw));
  }

  Future<void> saveMealTimes(Map<String, String> times) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('meal_times', jsonEncode(times));
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _storage.deleteAll();
  }

  // --- UNIT CONVERSIONS ---

  Future<Map<String, double>> loadConversions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('custom_conversions');
    if (raw == null) return {};
    try {
      Map<String, dynamic> jsonMap = jsonDecode(raw);
      return jsonMap.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (e) {
      return {};
    }
  }

  Future<void> saveConversions(Map<String, double> conversions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_conversions', jsonEncode(conversions));
  }
}
