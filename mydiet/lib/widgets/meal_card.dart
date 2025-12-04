import 'package:flutter/material.dart';
import '../models/active_swap.dart';
import '../models/pantry_item.dart';
import '../constants.dart';

class MealCard extends StatelessWidget {
  final String day;
  final String mealName;
  final List<dynamic> foods;
  final Map<String, ActiveSwap> activeSwaps;
  final Map<String, dynamic>? substitutions;
  final List<PantryItem> pantryItems;
  final bool isTranquilMode;

  final Function(String name, String qty) onConsume;
  final Function(String day, String meal, int idx, String name, String qty)
  onEdit;
  final Function(
    String day,
    String meal,
    int idx,
    String currentName,
    String cadCode,
  )
  onSwap;

  const MealCard({
    super.key,
    required this.day,
    required this.mealName,
    required this.foods,
    required this.activeSwaps,
    required this.substitutions,
    required this.pantryItems,
    required this.isTranquilMode,
    required this.onConsume,
    required this.onEdit,
    required this.onSwap,
  });

  bool _isFruit(String name) {
    String lower = name.toLowerCase();
    if (lower.contains("melanzan")) return false; // Eccezione nota
    for (var k in fruitKeywords) {
      if (lower.contains(k)) return true;
    }
    return false;
  }

  bool _isVeggie(String name) {
    String lower = name.toLowerCase();
    for (var k in veggieKeywords) {
      if (lower.contains(k)) return true;
    }
    return false;
  }

  String _getDisplayQuantity(String name, String originalQty) {
    if (isTranquilMode) {
      if (_isFruit(name)) return "1 frutto";
      if (_isVeggie(name)) return "A volontà";
    }
    return originalQty;
  }

  bool _isInPantry(String name) {
    if (pantryItems.isEmpty) return false;
    final nameLower = name.toLowerCase();

    for (var item in pantryItems) {
      // Ottimizzazione: salta stringhe vuote per evitare falsi positivi
      if (item.name.isEmpty) continue;

      final itemLower = item.name.toLowerCase();
      if (nameLower.contains(itemLower) || itemLower.contains(nameLower)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Intestazione del pasto (COLAZIONE, PRANZO...)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 6),
            child: Text(
              mealName.toUpperCase(),
              style: TextStyle(
                color: Colors.green[900],
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // La Card Bianca
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              // OTTIMIZZAZIONE: Ombra molto più leggera per evitare scatti
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: 0.05,
                  ), // Molto più performante
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                children: foods.asMap().entries.map((e) {
                  return _buildFoodRow(
                    e.key,
                    e.value,
                    e.key == foods.length - 1,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodRow(int index, dynamic food, bool isLast) {
    // Recupero dati e sostituzioni
    String swapKey = "${day}_${mealName}_$index";
    final activeSwap = activeSwaps[swapKey];

    String currentName = activeSwap?.name ?? food['name'];
    String currentQty = activeSwap?.qty ?? food['qty'];
    String? cad = food['cad_code'];

    bool hasSubstitutions =
        cad != null && substitutions != null && substitutions!.containsKey(cad);

    bool inFrigo = _isInPantry(currentName);
    String displayQty = _getDisplayQuantity(currentName, currentQty);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Se è nel frigo, tap consuma. Altrimenti null (così non fa l'effetto onda inutile)
        onTap: inFrigo ? () => onConsume(currentName, currentQty) : null,
        onLongPress: () =>
            onEdit(day, mealName, index, currentName, currentQty),
        child: Container(
          decoration: BoxDecoration(
            border: !isLast
                ? Border(
                    bottom: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.1),
                    ),
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // 1. Checkbox/Indicatore Frigo
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: inFrigo ? Colors.green[600] : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: inFrigo ? Colors.green[600]! : Colors.grey[300]!,
                    width: 2,
                  ),
                ),
                child: inFrigo
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),

              const SizedBox(width: 16),

              // 2. Testi (Nome cibo e quantità)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: inFrigo ? Colors.grey[400] : Colors.black87,
                        decoration: inFrigo ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.grey[400],
                      ),
                    ),
                    if (displayQty.isNotEmpty && displayQty != "N/A")
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          displayQty,
                          style: TextStyle(
                            color: inFrigo
                                ? Colors.grey[300]
                                : Colors.green[700],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 3. Pulsante Sostituzione (Swap)
              if (hasSubstitutions && !inFrigo)
                IconButton(
                  icon: Icon(
                    Icons.swap_horiz_rounded,
                    color: activeSwaps.containsKey(swapKey)
                        ? Colors.purple
                        : Colors.orange[300],
                  ),
                  tooltip: "Sostituisci",
                  constraints:
                      const BoxConstraints(), // Riduce area click vuota
                  padding: const EdgeInsets.all(8),
                  onPressed: () =>
                      onSwap(day, mealName, index, currentName, cad),
                ),

              // 4. Pulsante Modifica (Matita) - visibile solo se non consumato
              if (!inFrigo)
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: Colors.grey[400],
                  ),
                  tooltip: "Modifica Manuale",
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                  onPressed: () =>
                      onEdit(day, mealName, index, currentName, currentQty),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
