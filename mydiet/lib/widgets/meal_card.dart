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

  const MealCard({
    super.key,
    required this.day,
    required this.mealName,
    required this.foods,
    required this.activeSwaps,
    required this.isTranquilMode,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    // --- LOGICA DI RAGGRUPPAMENTO (Ibrida: Header vs Singoli) ---
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
    if (currentGroup.isNotEmpty) {
      groupedFoods.add(List.from(currentGroup));
    }
    // -----------------------------------------------------------

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

              if (group.isEmpty) return const SizedBox.shrink();

              var header = group[0];
              int cadCode =
                  int.tryParse(header['cad_code']?.toString() ?? "0") ?? 0;

              String swapKey = "${day}_${mealName}_group_$groupIndex";
              bool isSwapped = activeSwaps.containsKey(swapKey);

              List<dynamic> itemsToShow = isSwapped
                  ? activeSwaps[swapKey]!.swappedIngredients ?? []
                  : group;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: itemsToShow.map((item) {
                          bool isHeaderItem = (item['qty'] == "N/A");
                          bool isBold =
                              (isHeaderItem && !isSwapped) ||
                              (isSwapped && group.length > 1);
                          bool showBullet = !isHeaderItem && group.length > 1;

                          String name = item['name'];
                          String qty = item['qty']?.toString() ?? "";

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

                          return Padding(
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
                                          ? Colors.blue[800]
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Mostra SOLO l'icona di scambio se disponibile
                    if (cadCode > 0)
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, color: Colors.green),
                        onPressed: () => onSwap(swapKey, cadCode),
                        tooltip: isSwapped
                            ? "Cambia alternativa"
                            : "Sostituisci",
                      ),

                    // RIMOSSO IL TASTO UNDO (FRECCIA INDIETRO) QUI
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
