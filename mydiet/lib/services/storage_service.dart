import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';

class StorageService {
  static const String _dietKey = 'dietData';
  static const String _pantryKey = 'pantryItems';
  static const String _swapsKey = 'activeSwaps';

  Future<Map<String, dynamic>?> loadDiet() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_dietKey);
    return jsonStr != null ? json.decode(jsonStr) : null;
  }

  Future<void> saveDiet(Map<String, dynamic> dietData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dietKey, json.encode(dietData));
  }

  Future<List<PantryItem>> loadPantry() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_pantryKey);
    if (jsonStr == null) return [];

    final List<dynamic> decoded = json.decode(jsonStr);
    return decoded.map((e) => PantryItem.fromJson(e)).toList();
  }

  Future<void> savePantry(List<PantryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pantryKey,
      json.encode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<Map<String, ActiveSwap>> loadSwaps() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_swapsKey);
    if (jsonStr == null) return {};

    final Map<String, dynamic> decoded = json.decode(jsonStr);
    return decoded.map((k, v) => MapEntry(k, ActiveSwap.fromJson(v)));
  }

  Future<void> saveSwaps(Map<String, ActiveSwap> swaps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _swapsKey,
      json.encode(swaps.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
