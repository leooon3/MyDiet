import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/diet_repository.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';

class DietProvider extends ChangeNotifier {
  final DietRepository _repository;

  Map<String, dynamic>? _dietData;
  Map<String, dynamic>? _substitutions;
  List<PantryItem> _pantryItems = [];
  Map<String, ActiveSwap> _activeSwaps = {};
  // [FIX] Removed 'final' to allow updates
  List<String> _shoppingList = [];

  bool _isLoading = false;
  bool _isTranquilMode = false;

  DietProvider(this._repository) {
    _loadLocalData();
  }

  // Getters
  Map<String, dynamic>? get dietData => _dietData;
  Map<String, dynamic>? get substitutions => _substitutions;
  List<PantryItem> get pantryItems => _pantryItems;
  Map<String, ActiveSwap> get activeSwaps => _activeSwaps;
  List<String> get shoppingList => _shoppingList;
  bool get isLoading => _isLoading;
  bool get isTranquilMode => _isTranquilMode;

  // Persistence
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();

    String? dietJson = prefs.getString('dietData');
    if (dietJson != null) {
      final data = json.decode(dietJson);
      _dietData = data['plan'];
      _substitutions = data['substitutions'];
    }

    String? pantryJson = prefs.getString('pantryItems');
    if (pantryJson != null) {
      List<dynamic> decoded = json.decode(pantryJson);
      _pantryItems = decoded.map((item) => PantryItem.fromJson(item)).toList();
    }

    String? swapsJson = prefs.getString('activeSwaps');
    if (swapsJson != null) {
      Map<String, dynamic> decoded = json.decode(swapsJson);
      _activeSwaps = decoded.map(
        (key, value) => MapEntry(key, ActiveSwap.fromJson(value)),
      );
    }

    // [FIX] Load shopping list if needed (optional, assuming persistence isn't required for list strictly)
    notifyListeners();
  }

  Future<void> _saveLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    if (_dietData != null) {
      prefs.setString(
        'dietData',
        json.encode({'plan': _dietData, 'substitutions': _substitutions}),
      );
    }
    prefs.setString(
      'pantryItems',
      json.encode(_pantryItems.map((e) => e.toJson()).toList()),
    );
    prefs.setString(
      'activeSwaps',
      json.encode(
        _activeSwaps.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
  }

  // Actions
  void toggleTranquilMode() {
    _isTranquilMode = !_isTranquilMode;
    notifyListeners();
  }

  // [FIX] Added method to update shopping list
  void updateShoppingList(List<String> newList) {
    _shoppingList = newList;
    notifyListeners();
  }

  Future<void> uploadDiet(String path) async {
    _isLoading = true;
    notifyListeners();
    try {
      final result = await _repository.uploadDiet(path);
      _dietData = result.plan;
      _substitutions = result.substitutions;
      await _saveLocalData();
    } catch (e) {
      debugPrint("Error uploading: $e");
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int> scanReceipt(String path) async {
    _isLoading = true;
    notifyListeners();
    int count = 0;
    try {
      final items = await _repository.scanReceipt(path);
      for (var item in items) {
        addPantryItem(
          item['name'],
          1.0,
          'pz',
        ); // Defaulting, you might want dialogs in UI
        count++;
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return count;
  }

  void addPantryItem(String name, double qty, String unit) {
    int existingIndex = _pantryItems.indexWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase() && p.unit == unit,
    );
    if (existingIndex != -1) {
      _pantryItems[existingIndex].quantity += qty;
    } else {
      _pantryItems.add(PantryItem(name: name, quantity: qty, unit: unit));
    }
    _saveLocalData();
    notifyListeners();
  }

  void removePantryItem(int index) {
    _pantryItems.removeAt(index);
    _saveLocalData();
    notifyListeners();
  }

  void swapMeal(String key, ActiveSwap swap) {
    _activeSwaps[key] = swap;
    _saveLocalData();
    notifyListeners();
  }

  // Method to clear data
  Future<void> clearData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _dietData = null;
    _substitutions = null;
    _pantryItems = [];
    _activeSwaps = {};
    _shoppingList.clear(); // [FIX] Clear shopping list too
    notifyListeners();
  }

  void consumeItem(String name, double qtyToEat, String unit) {
    int index = _pantryItems.indexWhere(
      (p) =>
          p.name.toLowerCase().contains(name.toLowerCase()) && p.unit == unit,
    );

    if (index != -1) {
      _pantryItems[index].quantity -= qtyToEat;
      if (_pantryItems[index].quantity <= 0.1) {
        _pantryItems.removeAt(index);
      }
      _saveLocalData();
      notifyListeners();
    }
  }

  // [NEW] Logic to edit a meal manually
  void updateDietMeal(
    String day,
    String mealName,
    int index,
    String newName,
    String newQty,
  ) {
    if (_dietData != null &&
        _dietData![day] != null &&
        _dietData![day][mealName] != null) {
      _dietData![day][mealName][index]['name'] = newName;
      _dietData![day][mealName][index]['qty'] = newQty;
      _saveLocalData();
      notifyListeners();
    }
  }
}
