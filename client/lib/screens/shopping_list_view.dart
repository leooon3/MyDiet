import 'package:flutter/material.dart';
import 'package:kybo/models/diet_models.dart';
import '../models/active_swap.dart';
import '../models/pantry_item.dart';
import '../constants.dart';
import '../logic/diet_calculator.dart';

class ShoppingListView extends StatefulWidget {
  final List<String> shoppingList;
  final DietPlan? dietPlan; // <--- CAMBIATO: da Map a DietPlan
  final Map<String, ActiveSwap> activeSwaps;
  final List<PantryItem> pantryItems;
  final Function(List<String>) onUpdateList;
  final Function(String name, double qty, String unit) onAddToPantry;

  const ShoppingListView({
    super.key,
    required this.shoppingList,
    required this.dietPlan, // <--- Aggiornato
    required this.activeSwaps,
    required this.pantryItems,
    required this.onUpdateList,
    required this.onAddToPantry,
  });

  @override
  State<ShoppingListView> createState() => _ShoppingListViewState();
}

class _ShoppingListViewState extends State<ShoppingListView> {
  final Set<String> _selectedMealKeys = {};
  final List<String> _allDays = [
    "Lunedì",
    "Martedì",
    "Mercoledì",
    "Giovedì",
    "Venerdì",
    "Sabato",
    "Domenica",
  ];
  final List<String> _orderedMealTypes = [
    "Colazione",
    "Seconda Colazione",
    "Spuntino",
    "Pranzo",
    "Merenda",
    "Cena",
    "Spuntino Serale",
    "Nell'Arco Della Giornata",
  ];

  List<String> _getOrderedDays() {
    int todayIndex = DateTime.now().weekday - 1;
    if (todayIndex < 0 || todayIndex > 6) todayIndex = 0;
    return [
      ..._allDays.sublist(todayIndex),
      ..._allDays.sublist(0, todayIndex),
    ];
  }

  void _showImportDialog() {
    if (widget.dietPlan == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Carica prima una dieta!")));
      return;
    }

    final orderedDays = _getOrderedDays();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Genera Lista Spesa"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: orderedDays.length,
                  itemBuilder: (context, i) {
                    final day = orderedDays[i];
                    final dayPlan = widget.dietPlan!.plan[day];
                    if (dayPlan == null) return const SizedBox.shrink();

                    List<String> mealNames = dayPlan.keys.where((k) {
                      var foods = dayPlan[k];
                      return foods != null && foods.isNotEmpty;
                    }).toList();

                    mealNames.sort((a, b) {
                      int idxA = _orderedMealTypes.indexOf(a);
                      int idxB = _orderedMealTypes.indexOf(b);
                      if (idxA == -1) idxA = 999;
                      if (idxB == -1) idxB = 999;
                      return idxA.compareTo(idxB);
                    });

                    if (mealNames.isEmpty) return const SizedBox.shrink();

                    final allDayKeys =
                        mealNames.map((m) => "$day::$m").toList();
                    bool areAllSelected = allDayKeys.every(
                      (k) => _selectedMealKeys.contains(k),
                    );

                    return ExpansionTile(
                      leading: Checkbox(
                        value: areAllSelected,
                        activeColor: AppColors.primary,
                        onChanged: (bool? value) {
                          setStateDialog(() {
                            if (value == true) {
                              _selectedMealKeys.addAll(allDayKeys);
                            } else {
                              _selectedMealKeys.removeAll(allDayKeys);
                            }
                          });
                        },
                      ),
                      title: Text(
                        i == 0 ? "$day (Oggi)" : day,
                        style: TextStyle(
                          fontWeight:
                              i == 0 ? FontWeight.bold : FontWeight.normal,
                          color: i == 0 ? AppColors.primary : Colors.black87,
                        ),
                      ),
                      children: mealNames.map((meal) {
                        final key = "$day::$meal";
                        final isSelected = _selectedMealKeys.contains(key);
                        return CheckboxListTile(
                          title: Text(meal),
                          value: isSelected,
                          dense: true,
                          activeColor: AppColors.primary,
                          contentPadding: const EdgeInsets.only(
                            left: 60,
                            right: 20,
                          ),
                          onChanged: (val) {
                            setStateDialog(() {
                              if (val == true) {
                                _selectedMealKeys.add(key);
                              } else {
                                _selectedMealKeys.remove(key);
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Annulla"),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () {
                    _generateListFromSelection();
                    Navigator.pop(context);
                  },
                  child: const Text("Importa"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Inserisci questo dentro _ShoppingListViewState

  void _generateListFromSelection() {
    if (widget.dietPlan == null) return;

    // [FIX] Usiamo la struttura complessa richiesta da _addToAggregator
    // Struttura: {'Nome Ingrediente': {'qty': 100.0, 'unit': 'g'}}
    final Map<String, Map<String, dynamic>> neededItems = {};

    try {
      for (String key in _selectedMealKeys) {
        var parts = key.split('::');
        if (parts.length < 2) continue;

        var day = parts[0];
        var meal = parts[1];

        List<Dish>? foods = widget.dietPlan!.plan[day]?[meal];
        if (foods == null) continue;

        for (var dish in foods) {
          if (dish.isConsumed) continue;

          String swapKey = (dish.instanceId.isNotEmpty)
              ? "$day::$meal::${dish.instanceId}"
              : "$day::$meal::${dish.cadCode}";

          if (widget.activeSwaps.containsKey(swapKey)) {
            // --- LOGICA SWAP ---
            final swap = widget.activeSwaps[swapKey]!;
            if (swap.swappedIngredients != null &&
                swap.swappedIngredients!.isNotEmpty) {
              for (var ing in swap.swappedIngredients!) {
                String name = "";
                String qtyStr = "";

                if (ing is Map) {
                  name = ing['name']?.toString() ?? "";
                  qtyStr = ing['qty']?.toString() ?? "";
                } else {
                  name = ing.toString();
                }

                if (name.isNotEmpty) {
                  // Passiamo qtyStr, l'aggregator si occuperà del parsing
                  _addToAggregator(neededItems, name, qtyStr);
                }
              }
            } else {
              // Swap semplice
              _addToAggregator(
                  neededItems, swap.name, "${swap.qty} ${swap.unit}");
            }
          } else {
            // --- LOGICA PIATTO ORIGINALE ---
            if (dish.qty == "N/A") continue;

            if (dish.isComposed) {
              for (var ing in dish.ingredients) {
                _addToAggregator(neededItems, ing.name, ing.qty);
              }
            } else {
              _addToAggregator(neededItems, dish.name, dish.qty);
            }
          }
        }
      }

      // Conversione finale per la lista (UI)
      List<String> result = neededItems.entries.map((e) {
        String name = e.key;
        double qty = e.value['qty'] ?? 0.0;
        String unit = e.value['unit'] ?? '';

        // Formattazione pulita (100.0 -> 100)
        String qtyDisplay = qty.toStringAsFixed(1);
        if (qtyDisplay.endsWith(".0")) {
          qtyDisplay = qtyDisplay.substring(0, qtyDisplay.length - 2);
        }

        return "$name ($qtyDisplay $unit)".trim();
      }).toList();

      result.sort();
      widget.onUpdateList(result);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Aggiunti ${result.length} elementi!")),
      );

      setState(() {
        _selectedMealKeys.clear();
      });
    } catch (e, stack) {
      debugPrint("Errore ShoppingList: $e $stack");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Errore creazione lista.")),
      );
    }
  }

  void _addToAggregator(
    Map<String, Map<String, dynamic>> agg,
    String name,
    String qtyStr,
  ) {
    // MODIFICA: Uso DietCalculator per parsing sicuro e standardizzato
    // Gestisce virgole, punti, "q.b." e normalizza le unità (es. "gr" -> "g")
    double qty = DietCalculator.parseQty(qtyStr);
    String unit = DietCalculator.parseUnit(qtyStr, name);

    String cleanName = name.trim();
    if (cleanName.isNotEmpty) {
      cleanName = "${cleanName[0].toUpperCase()}${cleanName.substring(1)}";
    }

    if (agg.containsKey(cleanName)) {
      agg[cleanName]!['qty'] += qty;

      // Aggiorna l'unità se quella salvata è generica o vuota
      // (Migliora l'aggregazione se prima avevo solo "pz" e ora ho "g")
      String currentUnit = agg[cleanName]!['unit'];
      if ((currentUnit.isEmpty || currentUnit == 'pz') && unit.isNotEmpty) {
        agg[cleanName]!['unit'] = unit;
      }
    } else {
      agg[cleanName] = {'qty': qty, 'unit': unit};
    }
  }

  void _moveCheckedToPantry() {
    int count = 0;
    List<String> newList = [];
    for (String item in widget.shoppingList) {
      if (item.startsWith("OK_")) {
        String content = item.substring(3);
        final RegExp regExp = RegExp(
          r'^(.*?)(?:\s*\((\d+(?:[.,]\d+)?)\s*(.*)\))?$',
        );
        final match = regExp.firstMatch(content);
        String name = content;
        double qty = 1.0;
        String unit = "pz";

        if (match != null) {
          name = match.group(1)?.trim() ?? content;
          String? qtyStr = match.group(2);
          String? unitStr = match.group(3);
          if (qtyStr != null) {
            qty = double.tryParse(qtyStr.replaceAll(',', '.')) ?? 1.0;
          }
          if (unitStr != null && unitStr.isNotEmpty) {
            unit = unitStr.trim();
            if (unit.endsWith(')')) unit = unit.substring(0, unit.length - 1);
          }
        }
        widget.onAddToPantry(name, qty, unit);
        count++;
      } else {
        newList.add(item);
      }
    }

    if (count > 0) {
      widget.onUpdateList(newList);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$count prodotti nel frigo!"),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasCheckedItems = widget.shoppingList.any((i) => i.startsWith("OK_"));

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.shopping_cart, size: 28, color: AppColors.primary),
                  SizedBox(width: 10),
                  Text(
                    "Lista della Spesa",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // LISTA (Design Coerente con MealCard)
            Expanded(
              child: widget.shoppingList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.list_alt,
                            size: 60,
                            color: Colors.grey[300],
                          ),
                          const Text("Lista Vuota"),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: widget.shoppingList.length,
                      itemBuilder: (context, index) {
                        String raw = widget.shoppingList[index];
                        bool isChecked = raw.startsWith("OK_");
                        String display = isChecked ? raw.substring(3) : raw;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Dismissible(
                            key: Key(raw + index.toString()),
                            onDismissed: (_) {
                              var list = List<String>.from(widget.shoppingList);
                              list.removeAt(index);
                              widget.onUpdateList(list);
                            },
                            background: Container(
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: Icon(Icons.delete, color: Colors.red[800]),
                            ),
                            child: CheckboxListTile(
                              value: isChecked,
                              activeColor: AppColors.primary,
                              checkColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                              title: Text(
                                display,
                                style: TextStyle(
                                  decoration: isChecked
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: isChecked
                                      ? Colors.grey
                                      : const Color(0xFF2D3436),
                                  fontWeight: isChecked
                                      ? FontWeight.normal
                                      : FontWeight.w500,
                                ),
                              ),
                              onChanged: (val) {
                                var list = List<String>.from(
                                  widget.shoppingList,
                                );
                                list[index] =
                                    val == true ? "OK_$display" : display;
                                widget.onUpdateList(list);
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // FOOTER CON BOTTONI
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            hasCheckedItems ? AppColors.primary : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: hasCheckedItems ? _moveCheckedToPantry : null,
                      icon: const Icon(Icons.kitchen, color: Colors.white),
                      label: const Text(
                        "Sposta nel Frigo",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: AppColors.accent),
                      ),
                      onPressed: _showImportDialog,
                      icon: const Icon(Icons.download, color: AppColors.accent),
                      label: const Text(
                        "Importa da Dieta",
                        style: TextStyle(color: AppColors.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
