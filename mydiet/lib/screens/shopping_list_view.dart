import 'package:flutter/material.dart';
import '../models/active_swap.dart';
import '../models/pantry_item.dart';

class ShoppingListView extends StatefulWidget {
  final List<String> shoppingList;
  final Map<String, dynamic>? dietData;
  final Map<String, ActiveSwap> activeSwaps;
  final List<PantryItem> pantryItems;
  final Function(List<String>) onUpdateList;
  final Function(String name, double qty, String unit) onAddToPantry;

  const ShoppingListView({
    super.key,
    required this.shoppingList,
    required this.dietData,
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

  List<String> _getOrderedDays() {
    int todayIndex = DateTime.now().weekday - 1;
    if (todayIndex < 0 || todayIndex > 6) todayIndex = 0;
    return [
      ..._allDays.sublist(todayIndex),
      ..._allDays.sublist(0, todayIndex),
    ];
  }

  void _showImportDialog() {
    if (widget.dietData == null) {
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
                    final dayPlan =
                        widget.dietData![day] as Map<String, dynamic>?;

                    if (dayPlan == null) return const SizedBox.shrink();

                    final mealNames = dayPlan.keys.where((k) {
                      var foods = dayPlan[k];
                      return foods is List && foods.isNotEmpty;
                    }).toList();

                    if (mealNames.isEmpty) return const SizedBox.shrink();

                    final allDayKeys = mealNames
                        .map((m) => "${day}_$m")
                        .toList();
                    bool areAllSelected = allDayKeys.every(
                      (k) => _selectedMealKeys.contains(k),
                    );

                    return ExpansionTile(
                      leading: Checkbox(
                        value: areAllSelected,
                        activeColor: Theme.of(context).colorScheme.primary,
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
                          fontWeight: i == 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: i == 0 ? Colors.green[800] : Colors.black87,
                        ),
                      ),
                      children: mealNames.map((meal) {
                        final key = "${day}_$meal";
                        final isSelected = _selectedMealKeys.contains(key);
                        return CheckboxListTile(
                          title: Text(meal),
                          value: isSelected,
                          dense: true,
                          activeColor: Theme.of(context).colorScheme.primary,
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
                  onPressed: () {
                    _generateListFromSelection();
                    Navigator.pop(context);
                  },
                  // Secondary (Orange) for Import Action inside Dialog?
                  // Or Primary? Usually Dialog actions are Primary.
                  // Let's keep it Green (Primary) here as it's a "Confirm" action.
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  child: const Text("Importa Selezionati"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _generateListFromSelection() {
    if (_selectedMealKeys.isEmpty) return;

    Map<String, Map<String, dynamic>> neededItems = {};

    try {
      for (String key in _selectedMealKeys) {
        var parts = key.split('_');
        var day = parts[0];
        var meal = parts.sublist(1).join('_');

        List<dynamic>? foods = widget.dietData![day]?[meal];
        if (foods == null) continue;

        List<List<dynamic>> groupedFoods = [];
        List<dynamic> currentGroup = [];

        for (var food in foods) {
          String qty = food['qty']?.toString() ?? "";
          bool isHeader = qty == "N/A";
          if (isHeader) {
            if (currentGroup.isNotEmpty) {
              groupedFoods.add(List.from(currentGroup));
            }
            currentGroup = [food];
          } else {
            if (currentGroup.isNotEmpty) {
              currentGroup.add(food);
            } else {
              groupedFoods.add([food]);
            }
          }
        }
        if (currentGroup.isNotEmpty) groupedFoods.add(List.from(currentGroup));

        for (int i = 0; i < groupedFoods.length; i++) {
          var group = groupedFoods[i];
          String swapKey = "${day}_${meal}_group_$i";
          List<dynamic> itemsToAdd = group;

          if (widget.activeSwaps.containsKey(swapKey)) {
            final swap = widget.activeSwaps[swapKey]!;
            if (swap.swappedIngredients != null &&
                swap.swappedIngredients!.isNotEmpty) {
              itemsToAdd = swap.swappedIngredients!;
            } else {
              itemsToAdd = [
                {'name': swap.name, 'qty': swap.qty, 'unit': swap.unit},
              ];
            }
          }

          for (var food in itemsToAdd) {
            String qtyStr = food['qty']?.toString() ?? "";
            if (qtyStr == "N/A" && itemsToAdd.length > 1) continue;
            _addToAggregator(neededItems, food['name'], qtyStr);
          }
        }
      }
    } catch (e) {
      debugPrint("Error generating list: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Errore interno nella generazione dati.")),
      );
      return;
    }

    List<String> newList = List.from(widget.shoppingList);
    int addedCount = 0;

    neededItems.forEach((name, data) {
      double neededQty = data['qty'];
      String unit = data['unit'];
      String cleanNameLower = name.trim().toLowerCase();

      var pantryMatch = widget.pantryItems.where((p) {
        String pName = p.name.trim().toLowerCase();
        if (pName == cleanNameLower) return true;
        if (cleanNameLower.contains(pName)) return true;
        if (pName.contains(cleanNameLower)) return true;
        return false;
      }).firstOrNull;

      double existingQty = pantryMatch?.quantity ?? 0.0;
      double finalQty = neededQty - existingQty;

      if (finalQty > 0) {
        String displayQty = finalQty % 1 == 0
            ? finalQty.toInt().toString()
            : finalQty.toStringAsFixed(1);

        String entry = (finalQty == 0 || unit.isEmpty)
            ? name
            : "$name ($displayQty $unit)";

        if (!newList.any((e) => e.startsWith(name) || e == entry)) {
          newList.add(entry);
          addedCount++;
        }
      }
    });

    setState(() => _selectedMealKeys.clear());
    widget.onUpdateList(newList);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Aggiunti $addedCount prodotti (sottratto dispensa)!"),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  void _addToAggregator(
    Map<String, Map<String, dynamic>> agg,
    String name,
    String qtyStr,
  ) {
    final regExp = RegExp(r'(\d+(?:[.,]\d+)?)');
    final match = regExp.firstMatch(qtyStr);

    double qty = 0.0;
    String unit = "";

    if (match != null) {
      String numPart = match.group(1)!.replaceAll(',', '.');
      qty = double.tryParse(numPart) ?? 0.0;
      unit = qtyStr.replaceAll(match.group(0)!, '').trim();
      if (name.toLowerCase().contains(unit.toLowerCase()) && unit.length > 2) {
        unit = "";
      }
    } else {
      unit = qtyStr;
    }

    String cleanName = name.trim();
    if (agg.containsKey(cleanName)) {
      agg[cleanName]!['qty'] += qty;
      if (agg[cleanName]!['unit'] == "" && unit.isNotEmpty) {
        agg[cleanName]!['unit'] = unit;
      }
    } else {
      agg[cleanName] = {'qty': qty, 'unit': unit};
    }
  }

  // --- NEW: Move to Fridge Logic ---
  void _moveCheckedToPantry() {
    int count = 0;
    List<String> newList = [];

    for (String item in widget.shoppingList) {
      if (item.startsWith("OK_")) {
        String content = item.substring(3); // Remove "OK_"

        // Regex to parse "Name (100.0 g)"
        // Group 1: Name, Group 2: Qty, Group 3: Unit
        final RegExp regExp = RegExp(r'^(.*?) \((\d+(?:[.,]\d+)?)\s*(.*)\)$');
        final match = regExp.firstMatch(content);

        String name = content;
        double qty = 1.0;
        String unit = "pz";

        if (match != null) {
          name = match.group(1)!.trim();
          String qtyStr = match.group(2)!.replaceAll(',', '.');
          qty = double.tryParse(qtyStr) ?? 1.0;
          unit = match.group(3)!.trim();
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
        SnackBar(content: Text("Spostati $count prodotti nel frigo! 🏠")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Seleziona prima i prodotti comprati!")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasCheckedItems = widget.shoppingList.any((i) => i.startsWith("OK_"));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasCheckedItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: FloatingActionButton.extended(
                heroTag: "moveToPantry",
                onPressed: _moveCheckedToPantry,
                // PRIMARY (Green) for Completion Action
                backgroundColor: Theme.of(context).colorScheme.primary,
                icon: const Icon(Icons.kitchen, color: Colors.white),
                label: const Text(
                  "Sposta nel Frigo",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          FloatingActionButton.extended(
            heroTag: "importDiet",
            onPressed: _showImportDialog,
            // SECONDARY (Orange) for Setup/Add Action
            backgroundColor: Theme.of(context).colorScheme.secondary,
            icon: const Icon(Icons.auto_awesome, color: Colors.white),
            label: const Text(
              "Importa da Dieta",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: widget.shoppingList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Lista Vuota",
                    style: TextStyle(color: Colors.grey[400], fontSize: 18),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: widget.shoppingList.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = widget.shoppingList[index];
                bool isChecked = item.startsWith("OK_");
                String display = isChecked ? item.substring(3) : item;

                return Dismissible(
                  key: Key(item + index.toString()),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    var list = List<String>.from(widget.shoppingList);
                    list.removeAt(index);
                    widget.onUpdateList(list);
                  },
                  child: Card(
                    // Shape automatically inherited from main.dart
                    child: CheckboxListTile(
                      value: isChecked,
                      // Consistent Primary Green
                      activeColor: Theme.of(context).colorScheme.primary,
                      title: Text(
                        display,
                        style: TextStyle(
                          decoration: isChecked
                              ? TextDecoration.lineThrough
                              : null,
                          color: isChecked ? Colors.grey : Colors.black87,
                        ),
                      ),
                      onChanged: (val) {
                        var list = List<String>.from(widget.shoppingList);
                        if (val == true) {
                          list[index] = "OK_$display";
                        } else {
                          list[index] = display;
                        }
                        widget.onUpdateList(list);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
