import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';

class StorageService {
  // [FIX] Use Secure Storage instead of Shared Preferences
  final _storage = const FlutterSecureStorage();

  static const String _dietKey = 'dietData';
  static const String _pantryKey = 'pantryItems';
  static const String _swapsKey = 'activeSwaps';
  static const String _mealTimesKey = 'mealTimes';

  Future<Map<String, dynamic>?> loadDiet() async {
    final String? jsonStr = await _storage.read(key: _dietKey);
    return jsonStr != null ? json.decode(jsonStr) : null;
  }

  Future<void> saveDiet(Map<String, dynamic> dietData) async {
    await _storage.write(key: _dietKey, value: json.encode(dietData));
  }

  Future<List<PantryItem>> loadPantry() async {
    final String? jsonStr = await _storage.read(key: _pantryKey);
    if (jsonStr == null) return [];

    final List<dynamic> decoded = json.decode(jsonStr);
    return decoded.map((e) => PantryItem.fromJson(e)).toList();
  }

  Future<void> savePantry(List<PantryItem> items) async {
    await _storage.write(
      key: _pantryKey,
      value: json.encode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<Map<String, ActiveSwap>> loadSwaps() async {
    final String? jsonStr = await _storage.read(key: _swapsKey);
    if (jsonStr == null) return {};

    final Map<String, dynamic> decoded = json.decode(jsonStr);
    return decoded.map((k, v) => MapEntry(k, ActiveSwap.fromJson(v)));
  }

  Future<void> saveSwaps(Map<String, ActiveSwap> swaps) async {
    await _storage.write(
      key: _swapsKey,
      value: json.encode(swaps.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<Map<String, String>> loadMealTimes() async {
    final String? jsonStr = await _storage.read(key: _mealTimesKey);
    if (jsonStr != null) {
      return Map<String, String>.from(json.decode(jsonStr));
    }
    return {"colazione": "08:00", "pranzo": "13:00", "cena": "20:00"};
  }

  Future<void> saveMealTimes(Map<String, String> times) async {
    await _storage.write(key: _mealTimesKey, value: json.encode(times));
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
