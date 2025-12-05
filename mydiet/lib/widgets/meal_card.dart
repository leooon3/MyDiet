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
    // Nuova Logica: Se un elemento ha quantità "N/A", è un'intestazione di un piatto composto.
    // Raggruppiamo gli elementi successivi sotto di esso finché non ne troviamo un altro con "N/A" o un piatto distinto.
    List<List<dynamic>> groupedFoods = [];

    if (foods.isNotEmpty) {
      List<dynamic> currentGroup = [];

      for (var food in foods) {
        // Corretto l'errore: si usa 'cad_code' invece di 'cad'
        String qty = food['qty']?.toString() ?? "";
        bool isHeader =
            qty == "N/A"; // I piatti principali hanno qty N/A nel tuo JSON

        if (isHeader) {
          // Se inizia un nuovo piatto composto e c'era già un gruppo aperto, chiudilo.
          if (currentGroup.isNotEmpty) {
            groupedFoods.add(currentGroup);
          }
          // Inizia nuovo gruppo con questo header
          currentGroup = [food];
        } else {
          // Se è un ingrediente
          if (currentGroup.isEmpty) {
            // Caso raro: ingrediente senza header prima (es. Colazione semplice)
            // Lo trattiamo come gruppo a sé stante o lo accodiamo se preferisci raggruppare tutto
            // Per sicurezza creiamo un nuovo gruppo per non mischiarlo erroneamente
            groupedFoods.add([food]);
            currentGroup = []; // Reset
          } else {
            // Aggiunge al gruppo corrente (es. Pasta di semola sotto Pasta con melanzane)
            currentGroup.add(food);
          }
        }
      }
      // Aggiungi l'ultimo gruppo rimasto aperto
      if (currentGroup.isNotEmpty) {
        groupedFoods.add(currentGroup);
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mealName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),

            ...groupedFoods.asMap().entries.map((entry) {
              int groupIndex = entry.key;
              List<dynamic> group = entry.value;

              // Recuperiamo il primo elemento (Header) per determinare il CAD
              var headerFood = group.isNotEmpty ? group[0] : null;

              // ERRORE TROVATO: Qui usavi 'cad' invece di 'cad_code'
              int originalCad = 0;
              if (headerFood != null && headerFood['cad_code'] != null) {
                originalCad =
                    int.tryParse(headerFood['cad_code'].toString()) ?? 0;
              }

              String swapKey = "${mealName}_group_$groupIndex";
              bool isSwapped = activeSwaps.containsKey(swapKey);

              // Se sostituito mostra i nuovi ingredienti, altrimenti il gruppo originale
              List<dynamic> displayFoods = isSwapped
                  ? activeSwaps[swapKey]!.swappedIngredients ?? group
                  : group;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: displayFoods.map((f) {
                            // Logica pallini: Se è il primo del gruppo ed è un header originale, lo mostriamo in grassetto
                            // Gli altri li mostriamo con il pallino se siamo in un gruppo > 1 elemento
                            bool isHeaderLine =
                                (group.indexOf(f) == 0 &&
                                !isSwapped &&
                                f['qty'] == 'N/A');
                            bool showBullet =
                                displayFoods.length > 1 && !isHeaderLine;

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2.0,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showBullet)
                                    const Padding(
                                      padding: EdgeInsets.only(
                                        top: 6,
                                        right: 6,
                                      ),
                                      child: Icon(
                                        Icons.circle,
                                        size: 6,
                                        color: Colors.green,
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      // Se qty è N/A non lo mostriamo o mostriamo solo il nome
                                      (f['qty'] == "N/A")
                                          ? f['name']
                                          : "${f['name']} (${f['qty']})",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isHeaderLine || isSwapped
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSwapped
                                            ? Colors.blue[800]
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      // Mostra il tasto swap solo se il "capogruppo" ha un CAD valido (diverso da 0)
                      if (originalCad != 0)
                        IconButton(
                          icon: Icon(
                            Icons.swap_horiz,
                            color: isSwapped ? Colors.blue : Colors.grey,
                          ),
                          onPressed: () => onSwap(swapKey, originalCad),
                        ),
                    ],
                  ),
                  const Divider(height: 8),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}
