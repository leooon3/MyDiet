import 'package:flutter/material.dart';
import '../models/active_swap.dart';
import '../constants.dart';

class MealCard extends StatelessWidget {
  final String day;
  final String mealName;
  final List<dynamic> foods;
  final Map<String, ActiveSwap> activeSwaps;
  final bool isTranquilMode;
  final Function(String key, int currentCad) onSwap;
  final Function(int index, String name, String qty)? onEdit;

  const MealCard({
    super.key,
    required this.day,
    required this.mealName,
    required this.foods,
    required this.activeSwaps,
    required this.isTranquilMode,
    required this.onSwap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    List<List<dynamic>> groupedFoods = [];
    List<dynamic> currentGroup = [];

    // --- GROUPING LOGIC ---
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
    if (currentGroup.isNotEmpty) {
      groupedFoods.add(List.from(currentGroup));
    }
    // ---------------------

    int globalIndex = 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mealName.toUpperCase(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 1.2,
              ),
            ),
            const Divider(height: 20),

            ...groupedFoods.asMap().entries.map((entry) {
              int groupIndex = entry.key;
              List<dynamic> group = entry.value;

              int currentGroupStart = globalIndex;
              globalIndex += group.length;

              if (group.isEmpty) return const SizedBox.shrink();

              var header = group[0];
              int cadCode =
                  int.tryParse(header['cad_code']?.toString() ?? "0") ?? 0;

              String swapKey = "${day}_${mealName}_group_$groupIndex";
              bool isSwapped = activeSwaps.containsKey(swapKey);

              List<dynamic> itemsToShow;
              if (isSwapped) {
                final swap = activeSwaps[swapKey]!;
                if (swap.swappedIngredients != null &&
                    swap.swappedIngredients!.isNotEmpty) {
                  itemsToShow = swap.swappedIngredients!;
                } else {
                  String qtyDisplay = swap.qty;
                  if (swap.unit.isNotEmpty) {
                    qtyDisplay = "$qtyDisplay ${swap.unit}";
                  }
                  itemsToShow = [
                    {'name': swap.name, 'qty': qtyDisplay},
                  ];
                }
              } else {
                // EXPANSION LOGIC
                itemsToShow = [];
                for (var item in group) {
                  itemsToShow.add(item); // Add the main dish

                  // Add ingredients if they exist
                  if (item['ingredients'] != null &&
                      item['ingredients'] is List &&
                      (item['ingredients'] as List).isNotEmpty) {
                    itemsToShow.addAll(item['ingredients']);
                  }
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: itemsToShow.asMap().entries.map((itemEntry) {
                          var item = itemEntry.value;

                          // [FIX] CRASH PREVENTION
                          // Use ?.toString() ?? "" to handle nulls safely
                          String name = item['name']?.toString() ?? "Elemento";
                          String qty = item['qty']?.toString() ?? "";

                          // Heuristic: Headers usually have N/A or empty quantity
                          bool isHeaderItem = (qty == "N/A" || qty.isEmpty);

                          // Logic for bold text and bullets
                          bool isBold =
                              (isHeaderItem && !isSwapped) ||
                              (isSwapped && group.length > 1);
                          bool showBullet =
                              !isHeaderItem && itemsToShow.length > 1;

                          if (isTranquilMode) {
                            String lowerName = name.toLowerCase();
                            if (veggieKeywords.any(
                              (k) => lowerName.contains(k),
                            )) {
                              qty = "A volontà 🥗";
                            } else if (fruitKeywords.any(
                              (k) => lowerName.contains(k),
                            )) {
                              qty = "1 porzione 🍎";
                            }
                          }

                          String textDisplay = (isHeaderItem || qty.isEmpty)
                              ? name
                              : "$name ($qty)";

                          Widget content = Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                if (showBullet)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.circle,
                                      size: 5,
                                      color: Colors.green,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    textDisplay,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: isBold
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isSwapped
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.secondary
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );

                          // Only enable tap for the main group items (Dishes), not expanded ingredients
                          bool isMainItem = group.contains(item);
                          int originalIndex =
                              currentGroupStart; // Simplified mapping

                          if (!isSwapped && onEdit != null && isMainItem) {
                            return InkWell(
                              onTap: () => onEdit!(originalIndex, name, qty),
                              child: content,
                            );
                          } else {
                            return content;
                          }
                        }).toList(),
                      ),
                    ),

                    if (cadCode > 0)
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, color: Colors.green),
                        onPressed: () => onSwap(swapKey, cadCode),
                        tooltip: isSwapped
                            ? "Cambia alternativa"
                            : "Sostituisci",
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
