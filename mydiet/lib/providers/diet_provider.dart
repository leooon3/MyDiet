import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../services/api_client.dart';

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
  Map<String, bool> _availabilityMap = {};

  // UI States
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

          double qty = _parseQty(rawQty);
          String unit = 'pz';
          String lowerRaw = rawQty.toLowerCase();

          if (lowerRaw.contains('kg')) {
            qty *= 1000;
            unit = 'g';
          } else if (lowerRaw.contains('mg')) {
            unit = 'mg';
          } else if (lowerRaw.contains('g')) {
            unit = 'g';
          } else if (lowerRaw.contains('ml')) {
            unit = 'ml';
          } else if (lowerRaw.contains('l') && !lowerRaw.contains('ml')) {
            qty *= 1000;
            unit = 'ml';
          } else if (lowerRaw.contains('vasetto') ||
              lowerRaw.contains('vasetti')) {
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

    // 1. [FIX] Consistent Grouping Logic
    // We build the full list of groups first, then pick the one containing our dishIndex.
    // This prevents "loose items" from chaining together incorrectly.
    List<List<int>> groups = [];
    List<int> currentGroupIndices = [];

    for (int i = 0; i < meals.length; i++) {
      final d = meals[i];
      String qty = d['qty']?.toString() ?? "";
      bool isHeader = (qty == "N/A");

      if (isHeader) {
        if (currentGroupIndices.isNotEmpty) {
          groups.add(List.from(currentGroupIndices));
        }
        currentGroupIndices = [i];
      } else {
        if (currentGroupIndices.isNotEmpty) {
          // Add to existing header-based group
          currentGroupIndices.add(i);
        } else {
          // Standalone item -> Is its own group
          groups.add([i]);
        }
      }
    }
    // Add leftover
    if (currentGroupIndices.isNotEmpty) {
      groups.add(List.from(currentGroupIndices));
    }

    // 2. Find the target group
    int groupIndex = -1;
    List<int> targetGroupIndices = [];

    for (int g = 0; g < groups.length; g++) {
      if (groups[g].contains(dishIndex)) {
        groupIndex = g;
        targetGroupIndices = groups[g];
        break;
      }
    }

    if (targetGroupIndices.isEmpty) return; // Should not happen

    // 3. Consume Ingredients
    String swapKey = "${day}_${mealType}_group_$groupIndex";

    if (_activeSwaps.containsKey(swapKey)) {
      // Consume Swap
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
      // Consume Original Items in this specific group
      for (int i in targetGroupIndices) {
        final dish = meals[i];
        // Skip consuming the header title itself if it has no ingredients
        if ((dish['qty']?.toString() ?? "") == "N/A") {
          // If header has hidden ingredients (rare), consume them
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

    // 4. Mark items as Consumed
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
      unit = 'cucchiaini';
    } else if (lower.contains('vasett')) {
      unit = 'vasetto';
    } else if (lower.contains('fett')) {
      unit = 'fette';
    } else {
      try {
        final existing = _pantryItems.firstWhere(
          (p) => p.name.trim().toLowerCase() == name.trim().toLowerCase(),
        );
        if (['g', 'kg', 'ml', 'l'].contains(existing.unit.toLowerCase())) {
          unit = existing.unit;
        }
      } catch (_) {}
    }

    consumeItem(name, qtyToEat, unit);
  }

  void consumeItem(String name, double qty, String unit) {
    final searchName = name.trim().toLowerCase();
    final searchUnit = unit.trim().toLowerCase();

    int index = _pantryItems.indexWhere(
      (p) =>
          p.name.toLowerCase() == searchName &&
          p.unit.toLowerCase() == searchUnit,
    );

    if (index == -1) {
      index = _pantryItems.indexWhere((p) {
        final pName = p.name.toLowerCase();
        return (pName.contains(searchName) || searchName.contains(pName));
      });
    }

    if (index != -1) {
      var item = _pantryItems[index];
      final pUnit = item.unit.toLowerCase();

      double qtyToSubtract = qty;

      bool pIsWeight =
          (pUnit == 'g' || pUnit == 'kg' || pUnit == 'ml' || pUnit == 'l');
      bool sIsWeight =
          (searchUnit == 'g' ||
          searchUnit == 'kg' ||
          searchUnit == 'ml' ||
          searchUnit == 'l');

      if (pUnit == searchUnit) {
        qtyToSubtract = qty;
      } else if (pIsWeight && sIsWeight) {
        double searchQtyInBase = qty;
        if (searchUnit == 'kg' || searchUnit == 'l') searchQtyInBase *= 1000;

        if (pUnit == 'kg' || pUnit == 'l') {
          qtyToSubtract = searchQtyInBase / 1000.0;
        } else {
          qtyToSubtract = searchQtyInBase;
        }
      } else {
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

  void _recalcAvailability() {
    if (_dietData == null) return;

    Map<String, double> simulatedFridge = {};
    for (var item in _pantryItems) {
      String iName = item.name.trim().toLowerCase();
      double iQty = item.quantity;
      String iUnit = item.unit.toLowerCase();
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
      if (!_dietData!.containsKey(day)) continue;

      final mealsOfDay = _dietData![day] as Map<String, dynamic>;
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

        // [FIX] Consistent Grouping Logic (Mirrors consumeMeal and MealCard)
        List<List<int>> groups = [];
        List<int> currentGroupIndices = [];

        for (int i = 0; i < dishes.length; i++) {
          final d = dishes[i];
          String qty = d['qty']?.toString() ?? "";
          if (qty == "N/A") {
            if (currentGroupIndices.isNotEmpty)
              groups.add(List.from(currentGroupIndices));
            currentGroupIndices = [i];
          } else {
            if (currentGroupIndices.isNotEmpty) {
              currentGroupIndices.add(i);
            } else {
              // Standalone item -> Separate group
              groups.add([i]);
            }
          }
        }
        if (currentGroupIndices.isNotEmpty)
          groups.add(List.from(currentGroupIndices));

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
          bool isSwapped = _activeSwaps.containsKey(swapKey);

          if (isSwapped) {
            final swap = _activeSwaps[swapKey]!;
            List<dynamic> swapItems = [];
            if (swap.swappedIngredients != null &&
                swap.swappedIngredients!.isNotEmpty) {
              swapItems = swap.swappedIngredients!;
            } else {
              swapItems = [
                {'name': swap.name, 'qty': "${swap.qty} ${swap.unit}"},
              ];
            }

            bool groupCovered = true;
            for (var item in swapItems) {
              if (!_checkAndConsumeSimulated(item, simulatedFridge))
                groupCovered = false;
            }
            for (int originalIdx in indices) {
              newMap["${day}_${mType}_$originalIdx"] = groupCovered;
            }
          } else {
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
                  if (!_checkAndConsumeSimulated(item, simulatedFridge))
                    isCovered = false;
                }
              }
              newMap["${day}_${mType}_$i"] = isCovered;
            }
          }
        }
      }
    }
    _availabilityMap = newMap;
  }

  bool _checkAndConsumeSimulated(
    Map<String, dynamic> item,
    Map<String, double> fridge,
  ) {
    String iName = item['name'].toString().trim().toLowerCase();
    String iRawQty = item['qty'].toString().toLowerCase();
    double iQty = _parseQty(iRawQty);

    if (iRawQty.contains('kg') || iRawQty.contains('l')) iQty *= 1000;

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
        return false;
      }
    }
    return false;
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
