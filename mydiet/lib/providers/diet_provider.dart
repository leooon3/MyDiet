import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../services/api_client.dart'; // [NEW] Needed for Exception types

class DietProvider extends ChangeNotifier {
  final DietRepository _repository;
  final StorageService _storage = StorageService();
  final FirestoreService _firestore = FirestoreService();
  final AuthService _auth = AuthService();

  // Data States
  Map<String, dynamic>? _dietData;
  Map<String, dynamic>? _substitutions;
  List<PantryItem> _pantryItems = [];
  Map<String, ActiveSwap> _activeSwaps = {};
  List<String> _shoppingList = [];

  // UI States
  bool _isLoading = false;
  bool _isTranquilMode = false;
  String? _error; // [NEW] Error tracking

  // Getters
  Map<String, dynamic>? get dietData => _dietData;
  Map<String, dynamic>? get substitutions => _substitutions;
  List<PantryItem> get pantryItems => _pantryItems;
  Map<String, ActiveSwap> get activeSwaps => _activeSwaps;
  List<String> get shoppingList => _shoppingList;
  bool get isLoading => _isLoading;
  bool get isTranquilMode => _isTranquilMode;
  String? get error => _error;
  bool get hasError => _error != null;

  DietProvider(this._repository) {
    _init();
  }

  Future<void> _init() async {
    try {
      final savedDiet = await _storage.loadDiet();
      if (savedDiet != null) {
        _dietData = savedDiet['plan'];
        _substitutions = savedDiet['substitutions'];
      }
      _pantryItems = await _storage.loadPantry();
      _activeSwaps = await _storage.loadSwaps();
    } catch (e) {
      debugPrint("Init Load Error: $e");
    }
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> uploadDiet(String path) async {
    _setLoading(true);
    clearError();

    try {
      String? token;
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint("FCM Warning: $e");
      }

      // Repository uses the improved ApiClient with retries
      final result = await _repository.uploadDiet(path, fcmToken: token);

      _dietData = result.plan;
      _substitutions = result.substitutions;

      // 1. Save Local
      await _storage.saveDiet({
        'plan': _dietData,
        'substitutions': _substitutions,
      });

      // 2. Save to Cloud History (if logged in)
      if (_auth.currentUser != null) {
        await _firestore.saveDietToHistory(_dietData!, _substitutions!);
      }

      // Reset swaps on new diet
      _activeSwaps = {};
      await _storage.saveSwaps({});
    } catch (e) {
      _error = _mapError(e);
      rethrow; // Pass to UI for SnackBar
    } finally {
      _setLoading(false);
    }
  }

  Future<int> scanReceipt(String path) async {
    _setLoading(true);
    clearError();
    int count = 0;
    try {
      List<String> allowedFoods = _extractAllowedFoods();

      // Pass list to repository (which now handles JSON encoding)
      final items = await _repository.scanReceipt(path, allowedFoods);

      for (var item in items) {
        // [FIX] Ensure item['name'] exists
        if (item is Map && item.containsKey('name')) {
          addPantryItem(item['name'], 1.0, 'pz');
          count++;
        }
      }
    } catch (e) {
      _error = _mapError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
    return count;
  }

  // --- Helper to map Exceptions to User Friendly messages ---
  String _mapError(Object e) {
    if (e is ApiException) return "Server Error: ${e.message}";
    if (e is NetworkException) return "Problema di connessione. Riprova.";
    return "Errore imprevisto: $e";
  }

  // --- EXISTING LOGIC PRESERVED BELOW ---

  void loadHistoricalDiet(Map<String, dynamic> dietData) {
    _dietData = dietData['plan'];
    _substitutions = dietData['substitutions'];
    _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});
    _activeSwaps = {};
    _storage.saveSwaps({});
    notifyListeners();
  }

  List<String> _extractAllowedFoods() {
    final Set<String> foods = {};
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
    if (index >= 0 && index < _pantryItems.length) {
      _pantryItems.removeAt(index);
      _storage.savePantry(_pantryItems);
      notifyListeners();
    }
  }

  void consumeSmart(String name, String rawQtyString) {
    double qtyToEat = 1.0;
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

  void updateDietMeal(
    String day,
    String meal,
    int idx,
    String name,
    String qty,
  ) {
    if (_dietData != null &&
        _dietData![day] != null &&
        _dietData![day][meal] != null) {
      var currentMeals = List<dynamic>.from(_dietData![day][meal]);
      if (idx >= 0 && idx < currentMeals.length) {
        var oldItem = currentMeals[idx];
        currentMeals[idx] = {...oldItem, 'name': name, 'qty': qty};
        _dietData![day][meal] = currentMeals;
        _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});
        notifyListeners();
      }
    }
  }

  void swapMeal(String key, ActiveSwap swap) {
    _activeSwaps[key] = swap;
    _storage.saveSwaps(_activeSwaps);
    notifyListeners();
  }
}
