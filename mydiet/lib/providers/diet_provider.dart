import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';

class DietProvider extends ChangeNotifier {
  final DietRepository _repository;
  final StorageService _storage = StorageService();

  Map<String, dynamic>? _dietData;
  Map<String, dynamic>? _substitutions;
  List<PantryItem> _pantryItems = [];
  Map<String, ActiveSwap> _activeSwaps = {};
  List<String> _shoppingList = [];

  bool _isLoading = false;
  bool _isTranquilMode = false;

  Map<String, dynamic>? get dietData => _dietData;
  Map<String, dynamic>? get substitutions => _substitutions;
  List<PantryItem> get pantryItems => _pantryItems;
  Map<String, ActiveSwap> get activeSwaps => _activeSwaps;
  List<String> get shoppingList => _shoppingList;
  bool get isLoading => _isLoading;
  bool get isTranquilMode => _isTranquilMode;

  DietProvider(this._repository) {
    _init();
  }

  Future<void> _init() async {
    final savedDiet = await _storage.loadDiet();
    if (savedDiet != null) {
      _dietData = savedDiet['plan'];
      _substitutions = savedDiet['substitutions'];
    }
    _pantryItems = await _storage.loadPantry();
    _activeSwaps = await _storage.loadSwaps();
    notifyListeners();
  }

  Future<void> uploadDiet(String path) async {
    _setLoading(true);
    try {
      String? token;
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint("FCM Error: $e");
      }

      final result = await _repository.uploadDiet(path, fcmToken: token);

      _dietData = result.plan;
      _substitutions = result.substitutions;
      await _storage.saveDiet({
        'plan': _dietData,
        'substitutions': _substitutions,
      });
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<int> scanReceipt(String path) async {
    _setLoading(true);
    int count = 0;
    try {
      // 1. Gather all allowed foods from local state
      List<String> allowedFoods = _extractAllowedFoods();

      // 2. Send Image + List to server
      final items = await _repository.scanReceipt(path, allowedFoods);

      for (var item in items) {
        addPantryItem(item['name'], 1.0, 'pz');
        count++;
      }
    } catch (e) {
      rethrow;
    } finally {
      _setLoading(false);
    }
    return count;
  }

  List<String> _extractAllowedFoods() {
    final Set<String> foods = {};

    // From Plan
    if (_dietData != null) {
      _dietData!.forEach((day, meals) {
        if (meals is Map) {
          meals.forEach((mealType, dishes) {
            if (dishes is List) {
              for (var d in dishes) {
                foods.add(d['name']);
              }
            }
          });
        }
      });
    }

    // From Substitutions
    if (_substitutions != null) {
      _substitutions!.forEach((key, group) {
        if (group['options'] is List) {
          for (var opt in group['options']) {
            foods.add(opt['name']);
          }
        }
      });
    }

    return foods.toList();
  }

  void addPantryItem(String name, double qty, String unit) {
    int index = _pantryItems.indexWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase() && p.unit == unit,
    );
    if (index != -1) {
      _pantryItems[index].quantity += qty;
    } else {
      _pantryItems.add(PantryItem(name: name, quantity: qty, unit: unit));
    }
    _storage.savePantry(_pantryItems);
    notifyListeners();
  }

  void removePantryItem(int index) {
    _pantryItems.removeAt(index);
    _storage.savePantry(_pantryItems);
    notifyListeners();
  }

  void consumeSmart(String name, String rawQtyString) {
    // Robust parser
    double qtyToEat = 1.0;

    // Attempt to find the first numeric sequence
    final regExp = RegExp(r'(\d+[.,]?\d*)');
    final match = regExp.firstMatch(rawQtyString);

    if (match != null) {
      qtyToEat = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
    }

    String unit = rawQtyString.toLowerCase().contains('g') ? 'g' : 'pz';
    consumeItem(name, qtyToEat, unit);
  }

  void consumeItem(String name, double qty, String unit) {
    int index = _pantryItems.indexWhere(
      (p) =>
          p.name.toLowerCase().contains(name.toLowerCase()) && p.unit == unit,
    );
    if (index != -1) {
      _pantryItems[index].quantity -= qty;
      if (_pantryItems[index].quantity <= 0.01) {
        _pantryItems.removeAt(index);
      }
      _storage.savePantry(_pantryItems);
      notifyListeners();
    }
  }

  void updateShoppingList(List<String> list) {
    _shoppingList = list;
    notifyListeners();
  }

  Future<void> clearData() async {
    await _storage.clearAll();
    _dietData = null;
    _substitutions = null;
    _pantryItems = [];
    _activeSwaps = {};
    _shoppingList = [];
    notifyListeners();
  }

  void toggleTranquilMode() {
    _isTranquilMode = !_isTranquilMode;
    notifyListeners();
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  // Method stubs to satisfy existing calls if any
  void updateDietMeal(
    String day,
    String meal,
    int idx,
    String name,
    String qty,
  ) {}
  void swapMeal(String key, ActiveSwap swap) {}
}
