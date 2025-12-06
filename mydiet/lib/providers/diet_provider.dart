import 'package:flutter/material.dart';
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

  // Getters
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
      final result = await _repository.uploadDiet(path);
      _dietData = result.plan;
      _substitutions = result.substitutions;
      await _storage.saveDiet({
        'plan': _dietData,
        'substitutions': _substitutions,
      });
    } catch (e) {
      debugPrint("Error uploading: $e");
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<int> scanReceipt(String path) async {
    _setLoading(true);
    int count = 0;
    try {
      final items = await _repository.scanReceipt(path);
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

  // [RESTORED]
  void removePantryItem(int index) {
    _pantryItems.removeAt(index);
    _storage.savePantry(_pantryItems);
    notifyListeners();
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

  // [RESTORED]
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

      // Save updated structure
      _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});
      notifyListeners();
    }
  }

  void swapMeal(String key, ActiveSwap swap) {
    _activeSwaps[key] = swap;
    _storage.saveSwaps(_activeSwaps);
    notifyListeners();
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
}
