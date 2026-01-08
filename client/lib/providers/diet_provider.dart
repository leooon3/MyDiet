import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../core/error_handler.dart';

class UnitMismatchException implements Exception {
  final PantryItem item;
  final String requiredUnit;
  UnitMismatchException({required this.item, required this.requiredUnit});
  @override
  String toString() => "Unità diverse: ${item.unit} vs $requiredUnit";
}

class IngredientException implements Exception {
  final String message;
  IngredientException(this.message);
  @override
  String toString() => message;
}

Map<String, bool> _calculateAvailabilityIsolate(Map<String, dynamic> payload) {
  final dietData = payload['dietData'] as Map<String, dynamic>;
  final pantryItemsRaw = payload['pantryItems'] as List<dynamic>;
  final activeSwapsRaw = payload['activeSwaps'] as Map<String, dynamic>;

  Map<String, double> simulatedFridge = {};
  for (var item in pantryItemsRaw) {
    String iName = item['name'].toString().trim().toLowerCase();
    double iQty = double.tryParse(item['quantity'].toString()) ?? 0.0;
    String iUnit = item['unit'].toString().toLowerCase();

    if (iUnit == 'kg' || iUnit == 'l') iQty *= 1000;
    if (iUnit == 'gr') iUnit = 'g';
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
      "Spuntino",
      "Pranzo",
      "Merenda",
      "Cena",
      "Spuntino Serale",
      "Nell'Arco Della Giornata",
    ];

    for (var mType in mealTypes) {
      if (!mealsOfDay.containsKey(mType)) continue;
      List<dynamic> dishes = List.from(mealsOfDay[mType]);
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

        final firstDish = dishes[indices[0]];
        final String? instanceId = firstDish['instance_id']?.toString();
        final int cadCode = firstDish['cad_code'] ?? 0;

        String swapKey;
        if (instanceId != null && instanceId.isNotEmpty) {
          // Chiave univoca robusta (Nuovo Backend)
          swapKey = "${day}_${mType}_$instanceId";
        } else {
          // Fallback legacy (Vecchio Backend / Cache vecchia)
          swapKey = "${day}_${mType}_$cadCode";
        }

        bool isSwapped = activeSwapsRaw.containsKey(swapKey);

        if (isSwapped) {
          final swapData = activeSwapsRaw[swapKey];
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
            if (!_checkAndConsumeSimulatedStatic(item, simulatedFridge)) {
              groupCovered = false;
            }
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

List<List<int>> _buildGroupsStatic(List<dynamic> dishes) {
  List<List<int>> groups = [];
  List<int> currentGroupIndices = [];
  for (int i = 0; i < dishes.length; i++) {
    final d = dishes[i];
    String qty = d['qty']?.toString() ?? "";
    bool isHeader = (qty == "N/A");
    if (isHeader) {
      if (currentGroupIndices.isNotEmpty) {
        groups.add(List.from(currentGroupIndices));
      }
      currentGroupIndices = [i];
    } else {
      if (currentGroupIndices.isNotEmpty) {
        currentGroupIndices.add(i);
      } else {
        groups.add([i]);
      }
    }
  }
  if (currentGroupIndices.isNotEmpty) {
    groups.add(List.from(currentGroupIndices));
  }
  return groups;
}

bool _checkAndConsumeSimulatedStatic(
  Map<String, dynamic> item,
  Map<String, double> fridge,
) {
  String iName = item['name'].toString().trim().toLowerCase();
  String iRawQty = item['qty'].toString().toLowerCase();
  final regExp = RegExp(r'(\d+[.,]?\d*)');
  final match = regExp.firstMatch(iRawQty);
  double iQty = match != null
      ? (double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0)
      : 1.0;
  if (iRawQty.contains('kg') ||
      iRawQty.contains('l') && !iRawQty.contains('ml')) {
    iQty *= 1000;
  }
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
      return false;
    }
  }
  return false;
}

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
  Map<String, double> _conversions = {};

  DateTime _lastCloudSave = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, dynamic>? _lastSyncedDiet;
  Map<String, dynamic>? _lastSyncedSubstitutions;
  static const Duration _cloudSaveInterval = Duration(hours: 3);

  bool _isLoading = false;
  bool _isTranquilMode = false;
  String? _error;

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

  DietProvider(this._repository);

  Future<bool> loadFromCache() async {
    bool hasData = false;
    try {
      _setLoading(true);

      final savedDiet = await _storage.loadDiet();
      _pantryItems = await _storage.loadPantry();
      _activeSwaps = await _storage.loadSwaps();
      _conversions = await _storage.loadConversions();

      if (savedDiet != null && savedDiet['plan'] != null) {
        _dietData = savedDiet['plan'];
        _substitutions = savedDiet['substitutions'];

        _lastSyncedDiet = _deepCopy(_dietData);
        _lastSyncedSubstitutions = _deepCopy(_substitutions);

        _recalcAvailability();
        hasData = true;
        debugPrint("📦 Dati caricati dalla Cache Locale");
      }
    } catch (e) {
      debugPrint("⚠️ Errore Cache (Non bloccante): $e");
    } finally {
      _setLoading(false);
    }
    notifyListeners();
    return hasData;
  }

  Future<void> syncFromFirebase(String uid) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('history')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();

        if (data['dietData'] != null) {
          _dietData = data['dietData'];
          _substitutions = data['substitutions'];

          await _storage.saveDiet({
            'plan': _dietData,
            'substitutions': _substitutions,
          });

          _lastSyncedDiet = _deepCopy(_dietData);
          _lastSyncedSubstitutions = _deepCopy(_substitutions);
          _lastCloudSave = DateTime.now();

          _recalcAvailability();
          notifyListeners();
          debugPrint("☁️ Dati sincronizzati da Firebase");
        }
      }
    } catch (e) {
      debugPrint("⚠️ Sync Cloud fallito (possibile offline): $e");
    }
  }

  double _normalizeToGrams(double qty, String unit) {
    final u = unit.trim().toLowerCase();
    if (u == 'kg' || u == 'l') return qty * 1000;
    if (u == 'g' || u == 'ml' || u == 'mg' || u == 'gr' || u == 'grammi') {
      return qty;
    }
    if (u.contains('vasetto')) return qty * 125;
    if (u.contains('cucchiain')) return qty * 5;
    if (u.contains('cucchiaio')) return qty * 15;
    return -1.0;
  }

  Future<void> resolveUnitMismatch(
    String itemName,
    String fromUnit,
    String toUnit,
    double factor,
  ) async {
    final key =
        "${itemName.trim().toLowerCase()}_${fromUnit.trim().toLowerCase()}_to_${toUnit.trim().toLowerCase()}";
    _conversions[key] = factor;
    await _storage.saveConversions(_conversions);
    notifyListeners();
  }

  // --- MODIFICATO PER GESTIRE I NULL ---
  Future<void> consumeMeal(
    String day,
    String mealType,
    int dishIndex, {
    bool force = false,
  }) async {
    if (_dietData == null || _dietData![day] == null) return;
    final meals = _dietData![day][mealType];
    if (meals == null || meals is! List || dishIndex >= meals.length) return;

    List<List<int>> groups = _getGroups(meals);
    List<int> targetGroupIndices = [];

    for (int g = 0; g < groups.length; g++) {
      if (groups[g].contains(dishIndex)) {
        targetGroupIndices = groups[g];
        break;
      }
    }
    if (targetGroupIndices.isEmpty) return;

    // FASE 1: Validazione (Controlla se c'è abbastanza cibo)
    if (!force) {
      for (int i in targetGroupIndices) {
        final dish = meals[i];
        final String? instanceId = dish['instance_id']?.toString();
        final int cadCode = dish['cad_code'] ?? 0;

        String swapKey;
        if (instanceId != null && instanceId.isNotEmpty) {
          swapKey = "${day}_${mealType}_$instanceId";
        } else {
          swapKey = "${day}_${mealType}_$cadCode";
        }

        // VERIFICA SWAP
        if (_activeSwaps.containsKey(swapKey)) {
          final activeSwap = _activeSwaps[swapKey]!;
          // FIX: Gestione nullable list
          final List<dynamic> swapIngs = activeSwap.swappedIngredients ?? [];

          if (swapIngs.isNotEmpty) {
            for (var ing in swapIngs) {
              _validateItem(ing['name'].toString(), ing['qty'].toString());
            }
          } else {
            // Sostituzione semplice
            _validateItem(
              activeSwap.name,
              "${activeSwap.qty} ${activeSwap.unit}",
            );
          }
        } else {
          // COMPORTAMENTO ORIGINALE
          List<dynamic> itemsToCheck = [];
          if ((dish['qty']?.toString() ?? "") == "N/A") {
            if (dish['ingredients'] != null) itemsToCheck = dish['ingredients'];
          } else if (dish['ingredients'] != null &&
              (dish['ingredients'] as List).isNotEmpty) {
            itemsToCheck = dish['ingredients'];
          } else {
            itemsToCheck = [
              {'name': dish['name'], 'qty': dish['qty'] ?? '1'},
            ];
          }
          for (var itemData in itemsToCheck) {
            _validateItem(
              itemData['name'].toString(),
              itemData['qty'].toString(),
            );
          }
        }
      }
    }

    // FASE 2: Esecuzione (Rimuovi cibo dalla dispensa)
    for (int i in targetGroupIndices) {
      final dish = meals[i];
      final String? instanceId = dish['instance_id']?.toString();
      final int cadCode = dish['cad_code'] ?? 0;

      String swapKey;
      if (instanceId != null && instanceId.isNotEmpty) {
        swapKey = "${day}_${mealType}_$instanceId";
      } else {
        swapKey = "${day}_${mealType}_$cadCode";
      }

      if (_activeSwaps.containsKey(swapKey)) {
        // CONSUMA ALIMENTO SOSTITUITO
        final activeSwap = _activeSwaps[swapKey]!;
        // FIX: Gestione nullable list
        final List<dynamic> swapIngs = activeSwap.swappedIngredients ?? [];

        if (swapIngs.isNotEmpty) {
          for (var ing in swapIngs) {
            _consumeExecute(
              ing['name'].toString(),
              ing['qty'].toString(),
              force: force,
            );
          }
        } else {
          _consumeExecute(
            activeSwap.name,
            "${activeSwap.qty} ${activeSwap.unit}",
            force: force,
          );
        }
      } else {
        // CONSUMA ALIMENTO ORIGINALE
        if ((dish['qty']?.toString() ?? "") == "N/A") {
          if (dish['ingredients'] != null) {
            for (var ing in dish['ingredients']) {
              _consumeExecute(
                ing['name'].toString(),
                ing['qty'].toString(),
                force: force,
              );
            }
          }
        } else if (dish['ingredients'] != null &&
            (dish['ingredients'] as List).isNotEmpty) {
          for (var ing in dish['ingredients']) {
            _consumeExecute(
              ing['name'].toString(),
              ing['qty'].toString(),
              force: force,
            );
          }
        } else {
          _consumeExecute(dish['name'], dish['qty'] ?? '1', force: force);
        }
      }
    }

    // FASE 3: Aggiorna UI (Barra l'originale in ogni caso)
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

  void _validateItem(String name, String rawQtyString) {
    if (rawQtyString == "N/A" || name.toLowerCase().contains("libero")) return;

    double reqQty = _parseQty(rawQtyString);
    String reqUnit = _parseUnit(rawQtyString, name);
    String normalizedName = name.trim().toLowerCase();

    int index = _pantryItems.indexWhere((p) {
      final pName = p.name.toLowerCase();
      return (pName == normalizedName ||
          pName.contains(normalizedName) ||
          normalizedName.contains(pName));
    });

    if (index == -1) {
      throw IngredientException("Prodotto non trovato in dispensa: $name");
    }

    PantryItem pItem = _pantryItems[index];

    if (pItem.unit.trim().toLowerCase() == reqUnit.trim().toLowerCase()) {
      if (pItem.quantity < reqQty) {
        throw IngredientException(
          "Quantità insufficiente di $name. Hai ${pItem.quantity} ${pItem.unit}, servono $reqQty.",
        );
      }
      return;
    }

    double conversionFactor = 1.0;
    String convKey =
        "${normalizedName}_${reqUnit.trim().toLowerCase()}_to_${pItem.unit.trim().toLowerCase()}";

    if (_conversions.containsKey(convKey)) {
      conversionFactor = _conversions[convKey]!;
    } else {
      double pVal = _normalizeToGrams(1, pItem.unit);
      double rVal = _normalizeToGrams(1, reqUnit);

      if (pVal > 0 && rVal > 0) {
        // Compatibili (kg/g)
      } else {
        throw UnitMismatchException(item: pItem, requiredUnit: reqUnit);
      }
    }

    double reqQtyInPantryUnit = reqQty;
    if (_conversions.containsKey(convKey)) {
      reqQtyInPantryUnit = reqQty * conversionFactor;
    } else {
      double rGrams = _normalizeToGrams(reqQty, reqUnit);
      double pGrams = _normalizeToGrams(1, pItem.unit);
      if (pGrams > 0) reqQtyInPantryUnit = rGrams / pGrams;
    }

    if (pItem.quantity < reqQtyInPantryUnit) {
      throw IngredientException("Quantità insufficiente di $name.");
    }
  }

  void _consumeExecute(String name, String rawQtyString, {bool force = false}) {
    if (rawQtyString == "N/A") return;

    double reqQty = _parseQty(rawQtyString);
    String reqUnit = _parseUnit(rawQtyString, name);
    String normalizedName = name.trim().toLowerCase();

    int index = _pantryItems.indexWhere((p) {
      final pName = p.name.toLowerCase();
      return (pName.contains(normalizedName) || normalizedName.contains(pName));
    });

    if (index != -1) {
      var item = _pantryItems[index];
      double qtyToSubtract = reqQty;

      if (item.unit.toLowerCase() != reqUnit.toLowerCase()) {
        String convKey =
            "${normalizedName}_${reqUnit.trim().toLowerCase()}_to_${item.unit.trim().toLowerCase()}";
        if (_conversions.containsKey(convKey)) {
          qtyToSubtract = reqQty * _conversions[convKey]!;
        } else {
          double rGrams = _normalizeToGrams(reqQty, reqUnit);
          double pGramsOne = _normalizeToGrams(1, item.unit);
          if (rGrams > 0 && pGramsOne > 0) {
            qtyToSubtract = rGrams / pGramsOne;
          }
        }
      }

      item.quantity -= qtyToSubtract;
      if (item.quantity <= 0.01) {
        _pantryItems.removeAt(index);
      }
      _storage.savePantry(_pantryItems);
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

  String _parseUnit(String raw, String name) {
    String lower = raw.toLowerCase().trim();
    if (lower.contains('kg')) return 'kg';
    if (lower.contains('mg')) return 'mg';
    if (lower.contains('ml')) return 'ml';
    if (lower.contains('l') && !lower.contains('ml')) return 'ml';
    if (RegExp(r'\b(gr|g|grammi)\b').hasMatch(lower)) return 'g';
    if (lower.contains('vasett')) return 'vasetto';
    if (lower.contains('cucchiain')) return 'cucchiaino';
    if (lower.contains('cucchiai')) return 'cucchiaio';
    if (lower.contains('fett')) return 'fette';
    if (lower.contains('tazza')) return 'tazza';
    if (lower.contains('bicchiere')) return 'bicchiere';
    if (lower.contains('pz')) return 'pz';
    return 'pz';
  }

  List<List<int>> _getGroups(List<dynamic> meals) {
    return _buildGroupsStatic(meals);
  }

  void updateDietMeal(
    String day,
    String meal,
    int idx,
    String name,
    String qty,
  ) async {
    if (_dietData != null &&
        _dietData![day] != null &&
        _dietData![day][meal] != null) {
      var currentMeals = List<dynamic>.from(_dietData![day][meal]);
      if (idx >= 0 && idx < currentMeals.length) {
        var oldItem = currentMeals[idx];
        currentMeals[idx] = {...oldItem, 'name': name, 'qty': qty};
        _dietData![day][meal] = currentMeals;

        _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});

        if (_auth.currentUser != null) {
          bool timePassed =
              DateTime.now().difference(_lastCloudSave) > _cloudSaveInterval;
          if (timePassed) {
            bool isStructurallyDifferent =
                _hasStructuralChanges(_dietData, _lastSyncedDiet) ||
                jsonEncode(_substitutions) !=
                    jsonEncode(_lastSyncedSubstitutions);

            if (isStructurallyDifferent) {
              await _firestore.saveDietToHistory(_dietData!, _substitutions!);
              _lastCloudSave = DateTime.now();
              _lastSyncedDiet = _deepCopy(_dietData);
              _lastSyncedSubstitutions = _deepCopy(_substitutions);
              debugPrint("☁️ Cloud Sync Eseguito (Differenze Rilevate)");
            } else {
              debugPrint("⏳ Cloud Sync Saltato (Nessuna modifica strutturale)");
            }
          } else {
            debugPrint("⏳ Cloud Sync Throttled (< 3h)");
          }
        }

        _recalcAvailability();
        notifyListeners();
      }
    }
  }

  dynamic _sanitize(dynamic input) {
    if (input is Map) {
      final newMap = <String, dynamic>{};
      input.forEach((key, value) {
        if (key != 'consumed' && key != 'cad_code') {
          newMap[key.toString()] = _sanitize(value);
        }
      });
      return newMap;
    } else if (input is List) {
      return input.map((e) => _sanitize(e)).toList();
    }
    return input;
  }

  bool _hasStructuralChanges(
    Map<String, dynamic>? current,
    Map<String, dynamic>? old,
  ) {
    if (current == null && old == null) return false;
    if (current == null || old == null) return true;
    String sCurrent = jsonEncode(_sanitize(current));
    String sOld = jsonEncode(_sanitize(old));
    return sCurrent != sOld;
  }

  Map<String, dynamic>? _deepCopy(Map<String, dynamic>? input) {
    if (input == null) return null;
    return jsonDecode(jsonEncode(input));
  }

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
        _lastCloudSave = DateTime.now();
        _lastSyncedDiet = _deepCopy(_dietData);
        _lastSyncedSubstitutions = _deepCopy(_substitutions);
      }
      _activeSwaps = {};
      await _storage.saveSwaps({});
      _recalcAvailability();
    } catch (e) {
      _error = ErrorMapper.toUserMessage(e);
      debugPrint("❌ Errore Upload: $e");
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
          String unit = _parseUnit(rawQty, item['name']);
          if (rawQty.toLowerCase().contains('l') &&
              !rawQty.toLowerCase().contains('ml')) {
            qty *= 1000;
          }
          if (rawQty.toLowerCase().contains('kg')) qty *= 1000;
          addPantryItem(item['name'], qty, unit);
          count++;
        }
      }
    } catch (e) {
      _error = ErrorMapper.toUserMessage(e);
      debugPrint("❌ Errore Scan: $e");
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

  void removePantryItem(int index) {
    if (index >= 0 && index < _pantryItems.length) {
      _pantryItems.removeAt(index);
      _storage.savePantry(_pantryItems);
      _recalcAvailability();
      notifyListeners();
    }
  }

  Future<void> refreshAvailability() async {
    await _recalcAvailability();
  }

  Future<void> _recalcAvailability() async {
    if (_dietData == null) return;
    final payload = {
      'dietData': _dietData,
      'pantryItems': _pantryItems
          .map((p) => {'name': p.name, 'quantity': p.quantity, 'unit': p.unit})
          .toList(),
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
    _conversions = {};
    notifyListeners();
  }

  void toggleTranquilMode() {
    _isTranquilMode = !_isTranquilMode;
    notifyListeners();
  }

  void swapMeal(String key, ActiveSwap swap) {
    _activeSwaps[key] = swap;
    _storage.saveSwaps(_activeSwaps);
    _recalcAvailability();
    notifyListeners();
  }

  void consumeSmart(String name, String qty) {
    try {
      _validateItem(name, qty);
      _consumeExecute(name, qty);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }
}
