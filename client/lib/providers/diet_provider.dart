import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kybo/logic/diet_logic.dart';
import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../core/error_handler.dart';
import '../logic/diet_calculator.dart';
import 'package:permission_handler/permission_handler.dart'; // <--- NUOVO
import '../services/notification_service.dart'; // <--- NUOVO (se non c'è già)
import '../models/diet_models.dart';

class DietProvider extends ChangeNotifier {
  final DietRepository _repository;
  final StorageService _storage = StorageService();
  final FirestoreService _firestore = FirestoreService();
  final AuthService _auth = AuthService();

  DietPlan?
      _dietPlan; // Oggetto unico che contiene sia il piano che le sostituzioni
  List<PantryItem> _pantryItems = [];
  Map<String, ActiveSwap> _activeSwaps = {};
  List<String> _shoppingList = [];
  Map<String, bool> _availabilityMap = {};
  Map<String, double> _conversions = {};
  bool _isCalculating = false;

  // Campi per il Sync Intelligente
  DateTime _lastCloudSave = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, dynamic>? _lastSyncedDiet;
  Map<String, dynamic>? _lastSyncedSubstitutions;
  static const Duration _cloudSaveInterval = Duration(hours: 3);

  bool _isLoading = false;
  bool _isTranquilMode = false;
  String? _error;
  double _uploadProgress = 0.0;
  final NotificationService _notificationService =
      NotificationService(); // Servizio notifiche

  bool _needsNotificationPermissions = false;
  bool get needsNotificationPermissions => _needsNotificationPermissions;

  void resetPermissionFlag() {
    _needsNotificationPermissions = false;
    // Non chiamiamo notifyListeners() qui per evitare loop di rebuild
  }

  // [NUOVO] Logica di Sync Intelligente
  Future<String> runSmartSyncCheck({bool forceSync = false}) async {
    final user = _auth.currentUser;
    if (user == null || _dietPlan == null) return "Errore: Dati mancanti.";

    // Serializziamo per il confronto
    final currentPlanJson = _dietPlan!.toJson()['plan'];
    final currentSubsJson = _dietPlan!.toJson()['substitutions'];

    bool hasSwapsChanged = _activeSwaps.isNotEmpty;
    // Confrontiamo il JSON corrente con l'ultimo syncato
    bool hasStructuralChanges =
        _hasStructuralChanges(currentPlanJson, _lastSyncedDiet) ||
            hasSwapsChanged;

    if (!hasStructuralChanges && !forceSync) return "✅ Nessuna modifica.";

    final now = DateTime.now();

    // Preparazione Swap
    final Map<String, dynamic> swapsToSave = {};
    _activeSwaps.forEach((k, v) => swapsToSave[k] = v.toMap());

    // Sync Veloce (se < 3 ore)
    if (!forceSync && now.difference(_lastCloudSave).inHours < 3) {
      await _firestore.saveCurrentDiet(
          _sanitize(currentPlanJson), _sanitize(currentSubsJson), swapsToSave);
      return "☁️ Modifiche sincronizzate.";
    }

    // Backup Storico (> 3 ore o force)
    try {
      // 1. Aggiorna Current
      await _firestore.saveCurrentDiet(
          _sanitize(currentPlanJson), _sanitize(currentSubsJson), swapsToSave);

      // 2. Crea voce Storico
      if (_currentFirestoreId == null) {
        String newId = await _firestore.saveDietToHistory(
          _sanitize(currentPlanJson),
          _sanitize(currentSubsJson),
          swapsToSave,
        );
        _currentFirestoreId = newId;
      } else {
        await _firestore.updateDietHistory(
          _currentFirestoreId!,
          _sanitize(currentPlanJson),
          _sanitize(currentSubsJson),
          swapsToSave,
        );
      }

      _lastCloudSave = now;
      _lastSyncedDiet = _deepCopy(currentPlanJson); // Aggiorniamo baseline
      return "✅ Backup Storico e Sync completati.";
    } catch (e) {
      return "❌ Errore Sync: $e";
    }
  }

  // Helper privato per triggerare il sync dopo update manuali
  void _triggerSmartSyncCheck() {
    if (_auth.currentUser != null) {
      bool timePassed =
          DateTime.now().difference(_lastCloudSave) > _cloudSaveInterval;

      final currentPlanJson = _dietPlan!.toJson()['plan'];
      final currentSubsJson = _dietPlan!.toJson()['substitutions'];

      bool isStructurallyDifferent = _hasStructuralChanges(
              currentPlanJson, _lastSyncedDiet) ||
          jsonEncode(currentSubsJson) != jsonEncode(_lastSyncedSubstitutions);

      if (timePassed && isStructurallyDifferent) {
        runSmartSyncCheck(
            forceSync: true); // Riutilizziamo la logica principale
        debugPrint("☁️ Auto-Sync attivato da modifica manuale");
      }
    }
  }

  // Getters
// Espone direttamente l'oggetto strutturato
  DietPlan? get dietPlan => _dietPlan;
  String? _currentFirestoreId;
  List<PantryItem> get pantryItems => _pantryItems;
  Map<String, ActiveSwap> get activeSwaps => _activeSwaps;
  List<String> get shoppingList => _shoppingList;
  Map<String, bool> get availabilityMap => _availabilityMap;
  bool get isLoading => _isLoading;
  bool get isTranquilMode => _isTranquilMode;
  String? get error => _error;
  double get uploadProgress => _uploadProgress;
  bool get hasError => _error != null;

  DietProvider(this._repository);

  // --- INIT & SYNC ---

  Future<bool> loadFromCache() async {
    bool hasData = false;
    try {
      _setLoading(true);
      final savedDiet = await _storage.loadDiet();
      _pantryItems = await _storage.loadPantry();
      _activeSwaps = await _storage.loadSwaps();
      _conversions = await _storage.loadConversions();

      if (savedDiet != null && savedDiet['plan'] != null) {
        // Conversione da JSON cache a Oggetto Dart
        _dietPlan = DietPlan.fromJson(savedDiet);

        // Setup Sync
        _lastSyncedDiet = _deepCopy(savedDiet['plan']);
        _lastSyncedSubstitutions = _deepCopy(savedDiet['substitutions']);

        _recalcAvailability();
        hasData = true;
      }
    } catch (e) {
      debugPrint("⚠️ Errore Cache: $e");
    } finally {
      _setLoading(false);
    }
    notifyListeners();
    return hasData;
  }

  Future<void> syncFromFirebase(String uid) async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('diets')
          .doc('current')
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null && data['plan'] != null) {
          // [FIX] Conversione diretta da Mappa Firestore a Oggetto DietPlan
          _dietPlan = DietPlan.fromJson(data);

          // Salvataggio cache locale
          await _storage.saveDiet(_dietPlan!.toJson());

          // Aggiorna baseline sync
          // Nota: toJson() ci dà la mappa completa {'plan': ..., 'substitutions': ...}
          final jsonMap = _dietPlan!.toJson();
          _lastSyncedDiet = _deepCopy(jsonMap['plan']);
          _lastSyncedSubstitutions = _deepCopy(jsonMap['substitutions']);
          _lastCloudSave = DateTime.now();

          _recalcAvailability();
          await scheduleMealNotifications();
          notifyListeners();
          debugPrint("☁️ Sync Cloud completato (da 'current')");
        }
      }
    } catch (e) {
      debugPrint("⚠️ Sync Cloud fallito: $e");
    }
  }

  void loadHistoricalDiet(Map<String, dynamic> dietData, String docId) {
    debugPrint("📂 Caricamento dieta ID: $docId");

    // [FIX] Ricostruiamo l'oggetto dai dati passati
    _dietPlan = DietPlan.fromJson(dietData);
    _currentFirestoreId = docId;

    _activeSwaps = {};

    if (dietData['activeSwaps'] != null) {
      try {
        final rawSwaps = dietData['activeSwaps'] as Map;
        rawSwaps.forEach((key, value) {
          if (value is Map) {
            final swapObj =
                ActiveSwap.fromMap(Map<String, dynamic>.from(value));
            _activeSwaps[key.toString()] = swapObj;
          }
        });
        debugPrint("✅ Ripristinati ${_activeSwaps.length} scambi attivi.");
      } catch (e) {
        debugPrint("⚠️ Errore critico ripristino swap: $e");
      }
    }

    // Persistenza
    _storage.saveDiet(_dietPlan!.toJson());
    _storage.saveSwaps(_activeSwaps);

    final jsonMap = _dietPlan!.toJson();
    _lastSyncedDiet = _deepCopy(jsonMap['plan']);

    _recalcAvailability();
    notifyListeners();
  }

  Future<void> refreshAvailability() async {
    await _recalcAvailability();
  }

  // --- LOGICA CONSUMO & AGGIORNAMENTO ---

  void updateDietMeal(
    String day,
    String meal,
    int unsafeIndex,
    String name,
    String qty, {
    String? instanceId,
    int? cadCode,
  }) async {
    // Check di sicurezza sui dati
    if (_dietPlan == null ||
        !_dietPlan!.plan.containsKey(day) ||
        !_dietPlan!.plan[day]!.containsKey(meal)) {
      return;
    }

    final List<Dish> currentMeals = _dietPlan!.plan[day]![meal]!;

    // 1. Trova l'indice reale (usando instanceId per precisione)
    int realIndex = unsafeIndex;
    if (instanceId != null || cadCode != null) {
      final foundIndex = currentMeals.indexWhere((d) {
        if (instanceId != null && d.instanceId == instanceId) return true;
        if (cadCode != null && d.cadCode == cadCode) return true;
        return false;
      });

      if (foundIndex != -1) {
        realIndex = foundIndex;
      } else {
        debugPrint("⚠️ Update annullato: Piatto non trovato.");
        return;
      }
    }

    if (realIndex >= 0 && realIndex < currentMeals.length) {
      // 2. Crea un NUOVO oggetto Dish con i dati aggiornati (Dish è immutabile)
      final oldDish = currentMeals[realIndex];

      final newDish = Dish(
        instanceId: oldDish.instanceId,
        name: name, // Aggiornato
        qty: qty, // Aggiornato
        cadCode: oldDish.cadCode,
        isComposed: oldDish.isComposed,
        ingredients: oldDish.ingredients,
        isConsumed: oldDish.isConsumed,
      );

      // 3. Sostituisci nella lista
      currentMeals[realIndex] = newDish;

      // 4. Salva (Serializzando l'oggetto)
      await _storage.saveDiet(_dietPlan!.toJson());

      // 5. Trigger Sync Intelligente
      _triggerSmartSyncCheck();

      _recalcAvailability();
      notifyListeners();
    }
  }
  // [REFACTORING 4.1] Logica delegata a DietLogic

  Future<void> consumeMeal(
    String day,
    String mealType,
    int unsafeIndex, {
    bool force = false,
    String? instanceId,
    int? cadCode,
  }) async {
    if (_dietPlan == null) return;

    final mealsMap = _dietPlan!.plan[day];
    if (mealsMap == null || !mealsMap.containsKey(mealType)) return;

    final List<Dish> meals = mealsMap[mealType]!;

    // 1. Risoluzione Indice
    int realIndex = unsafeIndex;
    if (instanceId != null || cadCode != null) {
      final foundIndex = meals.indexWhere((d) {
        if (instanceId != null && d.instanceId == instanceId) return true;
        if (cadCode != null && d.cadCode == cadCode) return true;
        return false;
      });
      if (foundIndex != -1) realIndex = foundIndex;
    }

    if (realIndex >= meals.length) return;

    // 2. Identificazione Gruppo
    // [IMPORTANTE] Convertiamo in JSON per DietCalculator.buildGroups che si aspetta Maps
    final mealsAsMaps = meals.map((e) => e.toJson()).toList();
    List<List<int>> groups = DietCalculator.buildGroups(mealsAsMaps);

    List<int> targetGroupIndices = [];
    for (int g = 0; g < groups.length; g++) {
      if (groups[g].contains(realIndex)) {
        targetGroupIndices = groups[g];
        break;
      }
    }
    if (targetGroupIndices.isEmpty) targetGroupIndices = [realIndex];

    // 3. Preparazione Ingredienti (Usa il nuovo DietLogic che accetta Dish)
    List<Map<String, String>> allIngredientsToProcess = [];
    for (int i in targetGroupIndices) {
      var dish = meals[i];
      var ingredients = DietLogic.resolveIngredients(
        dish: dish, // Passiamo l'oggetto Dish
        day: day,
        mealType: mealType,
        activeSwaps: _activeSwaps,
      );
      allIngredientsToProcess.addAll(ingredients);
    }

    // 4. Validazione e Consumo Dispensa (Logica invariata)
    if (!force) {
      for (var ing in allIngredientsToProcess) {
        DietLogic.validateItem(
          name: ing['name']!,
          rawQtyString: ing['qty']!,
          pantryItems: _pantryItems,
          conversions: _conversions,
        );
      }
    }

    bool pantryModified = false;
    for (var ing in allIngredientsToProcess) {
      bool changed = DietLogic.consumeItem(
        name: ing['name']!,
        rawQtyString: ing['qty']!,
        pantryItems: _pantryItems,
        conversions: _conversions,
      );
      if (changed) pantryModified = true;
    }

    if (pantryModified) {
      _storage.savePantry(_pantryItems);
    }

    // 5. MARCATURA CONSUMATO (Aggiorniamo la proprietà isConsumed)
    for (int i in targetGroupIndices) {
      if (i < meals.length) {
        final old = meals[i];
        // Creiamo nuova istanza con isConsumed = true
        meals[i] = Dish(
          instanceId: old.instanceId,
          name: old.name,
          qty: old.qty,
          cadCode: old.cadCode,
          isComposed: old.isComposed,
          ingredients: old.ingredients,
          isConsumed: true, // <--- ECCO LA MODIFICA
        );
      }
    }

    // 6. Salvataggio e Aggiornamento
    await _storage.saveDiet(_dietPlan!.toJson());

    await _recalcAvailability();
    // Non serve notifyListeners() perché _recalcAvailability lo fa già
  }

  // Anche consumeSmart diventa un wrapper one-line
  void consumeSmart(String name, String qty) {
    try {
      DietLogic.validateItem(
        name: name,
        rawQtyString: qty,
        pantryItems: _pantryItems,
        conversions: _conversions,
      );

      bool changed = DietLogic.consumeItem(
        name: name,
        rawQtyString: qty,
        pantryItems: _pantryItems,
        conversions: _conversions,
      );

      if (changed) {
        _storage.savePantry(_pantryItems);
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  // --- HELPER METODS ---
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

  Future<void> uploadDiet(String path) async {
    _setLoading(true);
    _uploadProgress = 0.0; // ✅ Reset
    clearError();

    try {
      String? token;
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}

      // ✅ Upload con progress callback REALE
      final result = await _repository.uploadDiet(
        path,
        fcmToken: token,
        onProgress: (progress) {
          _uploadProgress = progress;
          notifyListeners(); // ✅ Aggiorna UI in tempo reale
        },
      );

      _uploadProgress = 1.0; // ✅ Completo

      _dietPlan = result;

      // Salvataggio Locale (Serializziamo l'oggetto in JSON)
      await _storage.saveDiet(_dietPlan!.toJson());

      // Reset Stato Locale
      _activeSwaps = {};
      await _storage.saveSwaps({});

      if (_auth.currentUser != null) {
        _lastCloudSave = DateTime.now();
        // Usiamo il toJson() per creare le copie di backup
        final jsonPlan = _dietPlan!.toJson();
        _lastSyncedDiet = _deepCopy(jsonPlan['plan']);
        _lastSyncedSubstitutions = _deepCopy(jsonPlan['substitutions']);
      }

      _recalcAvailability();
    } catch (e) {
      _error = ErrorMapper.toUserMessage(e);
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
      final items = await _repository.scanReceipt(path, _extractAllowedFoods());
      for (var item in items) {
        if (item is Map && item.containsKey('name')) {
          String rawQty = item['quantity']?.toString() ?? "1";
          double qty = DietCalculator.parseQty(rawQty);
          String unit = DietCalculator.parseUnit(rawQty, item['name']);
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

  Future<void> _recalcAvailability() async {
    // ✅ PROTEZIONE: Se c'è già un calcolo in corso, ignora questa chiamata
    if (_isCalculating) {
      debugPrint("⏭️ Calcolo availability già in corso, skip");
      return;
    }

    if (_dietPlan == null) return;

    _isCalculating = true; // ✅ LOCK attivato

    // Serializziamo il piano perchè l'Isolate lavora con dati puri
    final planJson = _dietPlan!.toJson()['plan'];

    final payload = {
      'dietData': planJson,
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
      final newMap = await compute(
        DietCalculator.calculateAvailabilityIsolate,
        payload,
      );
      _availabilityMap = newMap;
      notifyListeners();
    } catch (e) {
      debugPrint("Isolate Calc Error: $e");
    } finally {
      _isCalculating =
          false; // ✅ LOCK rilasciato (sempre, anche in caso di errore)
    }
  }

  // --- UTILS & HELPERS ---
  List<String> _extractAllowedFoods() {
    final Set<String> foods = {};
    if (_dietPlan != null) {
      // Iterazione Piano
      _dietPlan!.plan.forEach((day, meals) {
        meals.forEach((mealType, dishes) {
          for (var d in dishes) {
            foods.add(d.name);
          }
        });
      });

      // Iterazione Sostituzioni
      _dietPlan!.substitutions.forEach((key, group) {
        for (var opt in group.options) {
          foods.add(opt.name);
        }
      });
    }
    return foods.toList();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void toggleTranquilMode() {
    _isTranquilMode = !_isTranquilMode;
    notifyListeners();
  }

  void updateShoppingList(List<String> list) {
    _shoppingList = list;
    notifyListeners();
  }

  void swapMeal(String key, ActiveSwap swap) {
    _activeSwaps[key] = swap;
    _storage.saveSwaps(_activeSwaps);
    _recalcAvailability();
    notifyListeners();
  }

  Future<void> clearData() async {
    await _storage.clearAll();
    _dietPlan = null; // [FIX] Nullifichiamo l'oggetto
    _pantryItems = [];
    _activeSwaps = {};
    _shoppingList = [];
    _conversions = {};
    notifyListeners();
  }

  // Deep copy e Helpers per il Sync differenziale
// Deep copy tramite serializzazione/deserializzazione JSON
  Map<String, dynamic>? _deepCopy(Map<String, dynamic>? input) {
    if (input == null) return null;
    return jsonDecode(jsonEncode(input));
  }

  // Sanitize: Rimuove 'consumed' e stati UI per confrontare la struttura pura
  dynamic _sanitize(dynamic input) {
    if (input is Map) {
      final newMap = <String, dynamic>{};
      input.forEach((key, value) {
        // Rimuoviamo il flag locale 'consumed' per i confronti di sync
        if (key != 'consumed') {
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

  Future<void> scheduleMealNotifications() async {
    if (_dietPlan == null) return;

    var status = await Permission.notification.status;

    if (status.isGranted) {
      // [FIX] Passiamo la mappa 'plan' al servizio notifiche
      // Assumendo che il tuo NotificationService si aspetti Map<String, dynamic>
      await _notificationService.scheduleDietNotifications(_dietPlan!.plan);
      debugPrint("🔔 Notifiche pianificate con successo");
    } else {
      _needsNotificationPermissions = true;
      notifyListeners();
    }
  }

  // Fix #8-9: Dispose di risorse per evitare memory leak
  @override
  void dispose() {
    _repository.dispose();
    _notificationService.dispose();
    debugPrint("🧹 DietProvider disposed");
    super.dispose();
  }
}
