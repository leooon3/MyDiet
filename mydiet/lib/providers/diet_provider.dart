import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // [FIX] Required for compute/Isolate
import 'package:firebase_messaging/firebase_messaging.dart';
import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../services/api_client.dart';

// --- ISOLATE LOGIC (Must be top-level) ---
Map<String, bool> _calculateAvailabilityIsolate(Map<String, dynamic> payload) {
  final dietData = payload['dietData'] as Map<String, dynamic>;
  final pantryItemsRaw = payload['pantryItems'] as List<dynamic>;
  final activeSwapsRaw = payload['activeSwaps'] as Map<String, dynamic>;

  // Convert raw pantry data back to simulation map
  Map<String, double> simulatedFridge = {};
  for (var item in pantryItemsRaw) {
    String iName = item['name'].toString().trim().toLowerCase();
    double iQty = double.tryParse(item['quantity'].toString()) ?? 0.0;
    String iUnit = item['unit'].toString().toLowerCase();

    // Normalize to base units for simulation
    if (iUnit == 'kg' || iUnit == 'l') iQty *= 1000;
    simulatedFridge[iName] = iQty;
  }

  Map<String, bool> newMap = {};
  final italianDays = [
    "Lunedì",
    "Martedì",
    "Mercoledì",
    "Giovedì",
    "Venerdì",
    "Sabato",
    "Domenica",
  ];
  final todayIndex = DateTime.now().weekday - 1;

  for (int d = 0; d < italianDays.length; d++) {
    if (d < todayIndex) continue;

    String day = italianDays[d];
    if (!dietData.containsKey(day)) continue;

    final mealsOfDay = dietData[day] as Map<String, dynamic>;
    final mealTypes = [
      "Colazione",
      "Seconda Colazione",
      "Pranzo",
      "Merenda",
      "Cena",
      "Spuntino Serale",
    ];

    for (var mType in mealTypes) {
      if (!mealsOfDay.containsKey(mType)) continue;
      List<dynamic> dishes = List.from(mealsOfDay[mType]);

      // [FIX] Consistent Grouping Logic (Mirrored in Helper)
      List<List<int>> groups = _buildGroupsStatic(dishes);

      for (int gIdx = 0; gIdx < groups.length; gIdx++) {
        List<int> indices = groups[gIdx];
        if (indices.isEmpty) continue;

        bool isConsumed = false;
        if (indices.isNotEmpty) {
          final firstDish = dishes[indices[0]];
          if (firstDish['consumed'] == true) isConsumed = true;
        }

        if (isConsumed) {
          for (int originalIdx in indices) {
            newMap["${day}_${mType}_$originalIdx"] = false;
          }
          continue;
        }

        String swapKey = "${day}_${mType}_group_$gIdx";
        bool isSwapped = activeSwapsRaw.containsKey(swapKey);

        if (isSwapped) {
          // Handle Swap Simulation
          final swapData = activeSwapsRaw[swapKey];
          // Note: swapData here is a Map from JSON, not ActiveSwap object
          List<dynamic> swapItems = [];

          if (swapData['swappedIngredients'] != null &&
              (swapData['swappedIngredients'] as List).isNotEmpty) {
            swapItems = swapData['swappedIngredients'];
          } else {
            swapItems = [
              {
                'name': swapData['name'],
                'qty': "${swapData['qty']} ${swapData['unit']}",
              },
            ];
          }

          bool groupCovered = true;
          for (var item in swapItems) {
            // Helper logic inlined or called if static
            if (!_checkAndConsumeSimulatedStatic(item, simulatedFridge)) {
              groupCovered = false;
            }
          }
          for (int originalIdx in indices) {
            newMap["${day}_${mType}_$originalIdx"] = groupCovered;
          }
        } else {
          // Normal Simulation
          for (int i in indices) {
            final dish = dishes[i];
            bool isCovered = true;

            if ((dish['qty']?.toString() ?? "") != "N/A") {
              List<dynamic> itemsToCheck = [];
              if (dish['ingredients'] != null &&
                  (dish['ingredients'] as List).isNotEmpty) {
                itemsToCheck = dish['ingredients'];
              } else {
                itemsToCheck = [
                  {'name': dish['name'], 'qty': dish['qty']},
                ];
              }

              for (var item in itemsToCheck) {
                if (!_checkAndConsumeSimulatedStatic(item, simulatedFridge)) {
                  isCovered = false;
                }
              }
            }
            newMap["${day}_${mType}_$i"] = isCovered;
          }
        }
      }
    }
  }
  return newMap;
}

// Helper for Isolate
List<List<int>> _buildGroupsStatic(List<dynamic> dishes) {
  List<List<int>> groups = [];
  List<int> currentGroupIndices = [];

  for (int i = 0; i < dishes.length; i++) {
    final d = dishes[i];
    String qty = d['qty']?.toString() ?? "";
    bool isHeader = (qty == "N/A");

    if (isHeader) {
      if (currentGroupIndices.isNotEmpty)
        groups.add(List.from(currentGroupIndices));
      currentGroupIndices = [i];
    } else {
      if (currentGroupIndices.isNotEmpty) {
        currentGroupIndices.add(i);
      } else {
        groups.add([i]);
      }
    }
  }
  if (currentGroupIndices.isNotEmpty)
    groups.add(List.from(currentGroupIndices));
  return groups;
}

// Helper for Isolate
bool _checkAndConsumeSimulatedStatic(
  Map<String, dynamic> item,
  Map<String, double> fridge,
) {
  String iName = item['name'].toString().trim().toLowerCase();
  String iRawQty = item['qty'].toString().toLowerCase();

  // Basic parsing logic duplicated for isolate independence
  final regExp = RegExp(r'(\d+[.,]?\d*)');
  final match = regExp.firstMatch(iRawQty);
  double iQty = match != null
      ? (double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0)
      : 1.0;

  if (iRawQty.contains('kg') ||
      iRawQty.contains('l') && !iRawQty.contains('ml'))
    iQty *= 1000;
  // [FIX] Handle vasetto/tablespoon in simulation too
  if (iRawQty.contains('vasetto')) iQty = 125.0;

  String? foundKey;
  for (var key in fridge.keys) {
    if (key.contains(iName) || iName.contains(key)) {
      foundKey = key;
      break;
    }
  }

  if (foundKey != null && fridge[foundKey]! > 0) {
    if (fridge[foundKey]! >= iQty) {
      fridge[foundKey] = fridge[foundKey]! - iQty;
      return true;
    } else {
      fridge[foundKey] = 0;
      return false; // Partially covered but technically missing full qty
    }
  }
  return false;
}
// ------------------------------------------

class DietProvider extends ChangeNotifier {
  final DietRepository _repository;
  final StorageService _storage = StorageService();
  final FirestoreService _firestore = FirestoreService();
  final AuthService _auth = AuthService();

  Map<String, dynamic>? _dietData;
  Map<String, dynamic>? _substitutions;
  List<PantryItem> _pantryItems = [];
  Map<String, ActiveSwap> _activeSwaps = {};
  List<String> _shoppingList = [];
  Map<String, bool> _availabilityMap = {};

  bool _isLoading = false;
  bool _isTranquilMode = false;
  String? _error;

  // Getters
  Map<String, dynamic>? get dietData => _dietData;
  Map<String, dynamic>? get substitutions => _substitutions;
  List<PantryItem> get pantryItems => _pantryItems;
  Map<String, ActiveSwap> get activeSwaps => _activeSwaps;
  List<String> get shoppingList => _shoppingList;
  Map<String, bool> get availabilityMap => _availabilityMap;
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
      _recalcAvailability();
    } catch (e) {
      debugPrint("Init Load Error: $e");
    }
    notifyListeners();
  }

  // --- [FIX] Centralized Grouping Helper ---
  List<List<int>> _getGroups(List<dynamic> meals) {
    return _buildGroupsStatic(meals);
  }

  // --- [FIX] Unit Normalization Helper ---
  double _normalizeToGrams(double qty, String unit) {
    final u = unit.trim().toLowerCase();
    if (u == 'kg' || u == 'l') return qty * 1000;
    if (u == 'g' || u == 'ml' || u == 'mg') return qty;

    // Abstract units conversion
    if (u.contains('vasetto')) return qty * 125; // Standard yogurt
    if (u.contains('cucchiain')) return qty * 5;
    if (u.contains('cucchiaio')) return qty * 15;

    return qty; // Fallback for 'pz', 'fette' etc.
  }

  // ... (Upload/Init methods unchanged) ...
  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  Future<void> uploadDiet(String path) async {
    _setLoading(true);
    clearError();
    try {
      String? token;
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
      final result = await _repository.uploadDiet(path, fcmToken: token);
      _dietData = result.plan;
      _substitutions = result.substitutions;
      await _storage.saveDiet({
        'plan': _dietData,
        'substitutions': _substitutions,
      });
      if (_auth.currentUser != null) {
        await _firestore.saveDietToHistory(_dietData!, _substitutions!);
      }
      _activeSwaps = {};
      await _storage.saveSwaps({});
      _recalcAvailability();
    } catch (e) {
      _error = _mapError(e);
      rethrow;
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
      final items = await _repository.scanReceipt(path, allowedFoods);

      for (var item in items) {
        if (item is Map && item.containsKey('name')) {
          String rawQty = item['quantity']?.toString() ?? "1";
          // Basic parse
          double qty = _parseQty(rawQty);
          String unit = 'pz';
          String lowerRaw = rawQty.toLowerCase();

          // [FIX] Enhanced parsing for common units
          if (lowerRaw.contains('kg')) {
            qty *= 1000;
            unit = 'g';
          } else if (lowerRaw.contains('mg')) {
            unit = 'mg';
          } else if (lowerRaw.contains('g')) {
            unit = 'g';
          } else if (lowerRaw.contains('ml')) {
            unit = 'ml';
          } else if (lowerRaw.contains('l')) {
            qty *= 1000;
            unit = 'ml';
          } else if (lowerRaw.contains('vasetto')) {
            unit = 'vasetto';
          }

          addPantryItem(item['name'], qty, unit);
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

  void addPantryItem(String name, double qty, String unit) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedUnit = unit.trim().toLowerCase();

    int index = _pantryItems.indexWhere(
      (p) =>
          p.name.trim().toLowerCase() == normalizedName &&
          p.unit.trim().toLowerCase() == normalizedUnit,
    );

    if (index != -1) {
      _pantryItems[index].quantity += qty;
    } else {
      String displayName = name.trim();
      if (displayName.isNotEmpty) {
        displayName =
            "${displayName[0].toUpperCase()}${displayName.substring(1)}";
      }
      _pantryItems.add(
        PantryItem(name: displayName, quantity: qty, unit: unit),
      );
    }
    _storage.savePantry(_pantryItems);
    _recalcAvailability();
    notifyListeners();
  }

  void consumeMeal(String day, String mealType, int dishIndex) {
    if (_dietData == null || _dietData![day] == null) return;
    final meals = _dietData![day][mealType];
    if (meals == null || meals is! List || dishIndex >= meals.length) return;

    // [FIX] Use shared grouping logic
    List<List<int>> groups = _getGroups(meals);

    // Find the target group
    int groupIndex = -1;
    List<int> targetGroupIndices = [];
    for (int g = 0; g < groups.length; g++) {
      if (groups[g].contains(dishIndex)) {
        groupIndex = g;
        targetGroupIndices = groups[g];
        break;
      }
    }

    if (targetGroupIndices.isEmpty) return;

    String swapKey = "${day}_${mealType}_group_$groupIndex";

    if (_activeSwaps.containsKey(swapKey)) {
      final swap = _activeSwaps[swapKey]!;
      if (swap.swappedIngredients != null &&
          swap.swappedIngredients!.isNotEmpty) {
        for (var ing in swap.swappedIngredients!) {
          consumeSmart(ing['name'].toString(), ing['qty'].toString());
        }
      } else {
        String fullQty = swap.qty;
        if (swap.unit.isNotEmpty) fullQty += " ${swap.unit}";
        consumeSmart(swap.name, fullQty);
      }
    } else {
      for (int i in targetGroupIndices) {
        final dish = meals[i];
        if ((dish['qty']?.toString() ?? "") == "N/A") {
          // If header has hidden ingredients
          if (dish['ingredients'] != null &&
              (dish['ingredients'] as List).isNotEmpty) {
            for (var ing in dish['ingredients']) {
              consumeSmart(ing['name'].toString(), ing['qty'].toString());
            }
          }
          continue;
        }

        if (dish['ingredients'] != null &&
            (dish['ingredients'] as List).isNotEmpty) {
          for (var ing in dish['ingredients']) {
            consumeSmart(ing['name'].toString(), ing['qty'].toString());
          }
        } else {
          consumeSmart(dish['name'], dish['qty'] ?? '1');
        }
      }
    }

    // Mark as Consumed
    var currentMealsList = List<dynamic>.from(_dietData![day][mealType]);
    for (int i in targetGroupIndices) {
      if (i < currentMealsList.length) {
        var item = Map<String, dynamic>.from(currentMealsList[i]);
        item['consumed'] = true;
        currentMealsList[i] = item;
      }
    }

    _dietData![day][mealType] = currentMealsList;
    _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});

    _recalcAvailability();
    notifyListeners();
  }

  void consumeSmart(String name, String rawQtyString) {
    double qtyToEat = _parseQty(rawQtyString);
    String unit = 'pz';
    String lower = rawQtyString.toLowerCase();

    // [FIX] Comprehensive Unit Parsing
    if (lower.contains('kg')) {
      qtyToEat *= 1000;
      unit = 'g';
    } else if (lower.contains('mg')) {
      unit = 'mg';
    } else if (lower.contains('g')) {
      unit = 'g';
    } else if (lower.contains('ml')) {
      unit = 'ml';
    } else if (lower.contains('l')) {
      qtyToEat *= 1000;
      unit = 'ml';
    } else if (lower.contains('cucchiain')) {
      unit = 'cucchiaino';
    } else if (lower.contains('cucchiai')) {
      unit = 'cucchiaio';
    } else if (lower.contains('vasett')) {
      unit = 'vasetto';
    } else if (lower.contains('fett')) {
      unit = 'fette';
    } else {
      // Try to infer unit from existing pantry item
      try {
        final existing = _pantryItems.firstWhere(
          (p) => p.name.trim().toLowerCase() == name.trim().toLowerCase(),
        );
        unit = existing.unit;
      } catch (_) {}
    }

    consumeItem(name, qtyToEat, unit);
  }

  void consumeItem(String name, double qty, String unit) {
    final searchName = name.trim().toLowerCase();
    final searchUnit = unit.trim().toLowerCase();

    // 1. Exact Match
    int index = _pantryItems.indexWhere(
      (p) =>
          p.name.toLowerCase() == searchName &&
          p.unit.toLowerCase() == searchUnit,
    );

    // 2. Fuzzy Match
    if (index == -1) {
      index = _pantryItems.indexWhere((p) {
        final pName = p.name.toLowerCase();
        return (pName.contains(searchName) || searchName.contains(pName));
      });
    }

    if (index != -1) {
      var item = _pantryItems[index];

      // [FIX] Smart Unit Conversion Deduction
      double qtyToSubtract = qty;

      double pantryVal = _normalizeToGrams(item.quantity, item.unit);
      double requiredVal = _normalizeToGrams(qty, unit);

      // If units are compatible (both weight/vol or both abstract), subtract safely
      if (pantryVal > 0 && requiredVal > 0 && item.unit != unit) {
        // Convert requiredVal back to Item's unit scale roughly
        // Actually, safer to convert Item to standardized, subtract, then convert back?
        // Simplest approach: Just subtract if Normalized values align.

        // E.g. Item: 1kg (1000g). Req: 500g (500g).
        // New Item Qty = (1000 - 500) = 500g -> 0.5kg

        // We need to update the item.quantity which is in item.unit.
        double conversionFactor = pantryVal / item.quantity; // grams per unit
        double qtyToSubtractInItemUnits = requiredVal / conversionFactor;
        qtyToSubtract = qtyToSubtractInItemUnits;
      } else if (item.unit == unit) {
        qtyToSubtract = qty;
      }

      item.quantity -= qtyToSubtract;

      if (item.quantity <= 0.01) {
        _pantryItems.removeAt(index);
      }

      _storage.savePantry(_pantryItems);
      _recalcAvailability();
      notifyListeners();
    }
  }

  void removePantryItem(int index) {
    if (index >= 0 && index < _pantryItems.length) {
      _pantryItems.removeAt(index);
      _storage.savePantry(_pantryItems);
      _recalcAvailability();
      notifyListeners();
    }
  }

  // [INSERISCI QUI IL NUOVO METODO]
  Future<void> refreshAvailability() async {
    await _recalcAvailability();
  }

  // --- [FIX] Offload Calculation to Isolate ---
  Future<void> _recalcAvailability() async {
    if (_dietData == null) return;

    // Serialize data for Isolate
    final payload = {
      'dietData': _dietData,
      'pantryItems': _pantryItems
          .map((p) => {'name': p.name, 'quantity': p.quantity, 'unit': p.unit})
          .toList(),
      // Convert ActiveSwap objects to basic Map
      'activeSwaps': _activeSwaps.map(
        (key, value) => MapEntry(key, {
          'name': value.name,
          'qty': value.qty,
          'unit': value.unit,
          'swappedIngredients': value.swappedIngredients,
        }),
      ),
    };

    try {
      final newMap = await compute(_calculateAvailabilityIsolate, payload);
      _availabilityMap = newMap;
      notifyListeners();
    } catch (e) {
      debugPrint("Isolate Calc Error: $e");
    }
  }

  double _parseQty(String raw) {
    final regExp = RegExp(r'(\d+[.,]?\d*)');
    final match = regExp.firstMatch(raw);
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
    }
    return 1.0;
  }

  String _mapError(Object e) {
    if (e is ApiException) return "Server Error: ${e.message}";
    if (e is NetworkException) return "Problema di connessione. Riprova.";
    return "Errore imprevisto: $e";
  }

  void loadHistoricalDiet(Map<String, dynamic> dietData) {
    _dietData = dietData['plan'];
    _substitutions = dietData['substitutions'];
    _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});
    _activeSwaps = {};
    _storage.saveSwaps({});
    _recalcAvailability();
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
        _recalcAvailability();
        notifyListeners();
      }
    }
  }

  void swapMeal(String key, ActiveSwap swap) {
    _activeSwaps[key] = swap;
    _storage.saveSwaps(_activeSwaps);
    _recalcAvailability();
    notifyListeners();
  }
}
