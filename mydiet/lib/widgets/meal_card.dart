import 'package:flutter/material.dart';
import '../models/active_swap.dart';

class MealCard extends StatelessWidget {
  final String mealName;
  final List<dynamic> foods;
  final Map<String, ActiveSwap> activeSwaps;
  final Function(String key, int currentCad) onSwap;

  const MealCard({
    super.key,
    required this.mealName,
    required this.foods,
    required this.activeSwaps,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    // 1. RAGGRUPPA I CIBI
    // Logica: Un elemento con qty "N/A" è un Header di un piatto composto.
    // Gli elementi successivi sono i suoi ingredienti.
    List<List<dynamic>> groupedFoods = [];
    List<dynamic> currentGroup = [];

    for (var food in foods) {
      String qty = food['qty']?.toString() ?? "";
      bool isHeader = qty == "N/A";

      if (isHeader) {
        // Se c'era un gruppo aperto, chiudilo
        if (currentGroup.isNotEmpty) groupedFoods.add(currentGroup);
        // Inizia nuovo gruppo
        currentGroup = [food];
      } else {
        // È un ingrediente o un piatto singolo
        if (currentGroup.isEmpty) {
          // Piatto singolo (nessun header prima)
          groupedFoods.add([food]);
        } else {
          // Ingrediente del piatto corrente
          currentGroup.add(food);
        }
      }
    }
    // Chiudi l'ultimo gruppo
    if (currentGroup.isNotEmpty) groupedFoods.add(currentGroup);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titolo del Pasto (es. PRANZO)
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

            // Lista dei Piatti
            ...groupedFoods.asMap().entries.map((entry) {
              int groupIndex = entry.key;
              List<dynamic> group = entry.value;

              // Il primo elemento comanda (per il nome e il CAD)
              var header = group[0];
              int cadCode =
                  int.tryParse(header['cad_code']?.toString() ?? "0") ?? 0;

              String swapKey = "${mealName}_group_$groupIndex";
              bool isSwapped = activeSwaps.containsKey(swapKey);

              // Cibi da mostrare (Originali o Sostituiti)
              List<dynamic> itemsToShow = isSwapped
                  ? activeSwaps[swapKey]!.swappedIngredients ?? []
                  : group;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Colonna Cibi
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: itemsToShow.map((item) {
                          bool isHeaderItem = (item['qty'] == "N/A");
                          // Se è stato sostituito, mostriamo tutto normale
                          // Se è originale, l'header è in grassetto
                          bool isBold =
                              (isHeaderItem && !isSwapped) || isSwapped;

                          // Mostra pallino se è un ingrediente di un gruppo (non header)
                          bool showBullet = !isHeaderItem && group.length > 1;

                          String text;
                          if (isHeaderItem) {
                            text = item['name'];
                          } else {
                            text = "${item['name']} ${item['qty']}";
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showBullet)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6, right: 6),
                                    child: Icon(
                                      Icons.circle,
                                      size: 5,
                                      color: Colors.green,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    text,
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

                    // Bottone Swap (Solo se non sostituito e ha un CAD valido)
                    if (cadCode > 0 && !isSwapped)
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, color: Colors.green),
                        onPressed: () => onSwap(swapKey, cadCode),
                        tooltip: "Sostituisci",
                      ),

                    // Bottone "Annulla Swap" (Se sostituito)
                    if (isSwapped)
                      IconButton(
                        icon: const Icon(Icons.undo, color: Colors.orange),
                        onPressed: () => onSwap(
                          swapKey,
                          -1,
                        ), // -1 codice speciale per reset? Gestiscilo in DietView
                        tooltip: "Ripristina",
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
