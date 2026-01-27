import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/active_swap.dart';
import '../models/diet_models.dart'; // [IMPORTANTE] Serve per capire cos'è un Dish

class MealCard extends StatelessWidget {
  final String day;
  final String mealName;
  final List<Dish> foods; // [FIX] Ora è tipizzato correttamente
  final Map<String, ActiveSwap> activeSwaps;
  final Map<String, bool> availabilityMap;
  final bool isTranquilMode;
  final bool isToday;
  final Function(int) onEat;
  final Function(String, int) onSwap;
  final Function(int, String, String) onEdit;

  const MealCard({
    super.key,
    required this.day,
    required this.mealName,
    required this.foods,
    required this.activeSwaps,
    required this.availabilityMap,
    required this.isTranquilMode,
    required this.isToday,
    required this.onEat,
    required this.onSwap,
    required this.onEdit,
  });

  // Lista di alimenti "rilassabili" (Frutta e Verdura)
  static const Set<String> _relaxableFoods = {
    'mela',
    'mele',
    'pera',
    'pere',
    'banana',
    'banane',
    'arancia',
    'arance',
    'mandarino',
    'mandarini',
    'kiwi',
    'ananas',
    'fragola',
    'fragole',
    'ciliegia',
    'ciliegie',
    'albicocca',
    'albicocche',
    'pesca',
    'pesche',
    'anguria',
    'melone',
    'uva',
    'prugna',
    'prugne',
    'limone',
    'pompelmo',
    'frutti di bosco',
    'insalata',
    'lattuga',
    'rucola',
    'spinaci',
    'bieta',
    'zucchina',
    'zucchine',
    'melanzana',
    'melanzane',
    'peperone',
    'peperoni',
    'pomodoro',
    'pomodori',
    'carota',
    'carote',
    'sedano',
    'finocchio',
    'finocchi',
    'cetriolo',
    'cetrioli',
    'cavolfiore',
    'broccolo',
    'broccoli',
    'verza',
    'cime di rapa',
    'fagiolini',
    'verdura',
    'verdure',
    'minestrone',
    'passato di verdura',
    'ortaggi',
  };

  @override
  Widget build(BuildContext context) {
    // [FIX] Usa .isConsumed invece di ['consumed']
    bool allConsumed = foods.isNotEmpty && foods.every((f) => f.isConsumed);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: 0.05), // Fix per versioni vecchie di Flutter
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barra Laterale Decorativa
              Container(
                width: 6,
                color: allConsumed ? Colors.grey[300] : AppColors.primary,
              ),

              // Contenuto Card
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Pasto
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            mealName.toUpperCase(),
                            style: TextStyle(
                              color:
                                  allConsumed ? Colors.grey : AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1.2,
                            ),
                          ),
                          if (allConsumed)
                            const Icon(
                              Icons.check_circle,
                              color: Colors.grey,
                              size: 20,
                            )
                          else
                            Icon(
                              Icons.restaurant,
                              color: Colors.grey[400],
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 0.5),

                    // Lista Piatti
                    Column(
                      children: List.generate(foods.length, (index) {
                        final originalFood =
                            foods[index]; // Ora è un oggetto Dish
                        final int cadCode = originalFood.cadCode;
                        final String instanceId = originalFood.instanceId;

                        // Generazione chiave robusta
                        final String swapKey = (instanceId.isNotEmpty)
                            ? "$day::$mealName::$instanceId"
                            : "$day::$mealName::$cadCode";

                        // --- LOGICA SWAP ---
                        final bool isSwapped = activeSwaps.containsKey(swapKey);
                        final activeSwap =
                            isSwapped ? activeSwaps[swapKey] : null;

                        // Dati da visualizzare (Swap o Originale)
                        // [FIX] Usa .name e .qty invece di ['name']
                        final String displayName =
                            isSwapped ? activeSwap!.name : originalFood.name;

                        final String displayQtyRaw = isSwapped
                            ? "${activeSwap!.qty} ${activeSwap.unit}"
                            : originalFood
                                .qty; // originalFood.qty include già l'unità nel nuovo modello

                        final bool isConsumed = originalFood.isConsumed;

                        assert(
                          [
                            'Colazione',
                            'Seconda Colazione',
                            'Spuntino',
                            'Pranzo',
                            'Merenda',
                            'Cena',
                            'Spuntino Serale',
                            "Nell'Arco Della Giornata"
                          ].contains(mealName),
                          '❌ BUG: Meal name "$mealName" non standardizzato! Controlla normalize_meal_name()',
                        );
                        String availKey = "${day}_${mealName}_$index";
                        bool isAvailable = availabilityMap[availKey] ?? false;

                        // Ingredienti
                        final List<Ingredient>? ingredients = isSwapped
                            ? null
                            : originalFood
                                .ingredients; // Ora è List<Ingredient>

                        final bool hasIngredients =
                            ingredients != null && ingredients.isNotEmpty;

                        // Logica Relax
                        final String nameLower = displayName.toLowerCase();
                        bool isRelaxableItem = _relaxableFoods.any(
                          (tag) => nameLower.contains(tag),
                        );

                        String qtyDisplay;
                        if (isTranquilMode && isRelaxableItem) {
                          qtyDisplay = "A piacere";
                        } else {
                          qtyDisplay = displayQtyRaw.trim();
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: isSwapped
                                ? Colors.orange.withValues(alpha: 0.05)
                                : null,
                            border: index != foods.length - 1
                                ? Border(
                                    bottom: BorderSide(
                                      color: Colors.grey[100]!,
                                    ),
                                  )
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Icona Stato
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    isConsumed
                                        ? Icons.check
                                        : (isAvailable
                                            ? Icons.check_circle
                                            : Icons.circle_outlined),
                                    color: isConsumed
                                        ? Colors.grey[300]
                                        : (isAvailable
                                            ? AppColors.primary
                                            : Colors.grey[400]),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Testi
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (isSwapped)
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                right: 6,
                                              ),
                                              child: Icon(
                                                Icons.swap_horiz,
                                                size: 16,
                                                color: Colors.orange,
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              displayName,
                                              style: TextStyle(
                                                decoration: isConsumed
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                                color: isConsumed
                                                    ? Colors.grey
                                                    : (isSwapped
                                                        ? Colors.deepOrange
                                                        : const Color(
                                                            0xFF2D3436,
                                                          )),
                                                fontWeight: isSwapped
                                                    ? FontWeight.bold
                                                    : FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      // [FIX] Loop sugli ingredienti oggetto
                                      if (hasIngredients)
                                        ...ingredients.map((ing) {
                                          String iName = ing.name;
                                          String iQty = ing.qty;
                                          bool iRelax = _relaxableFoods.any(
                                            (tag) => iName
                                                .toLowerCase()
                                                .contains(tag),
                                          );
                                          if (isTranquilMode && iRelax) {
                                            iQty = "";
                                          }
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 2,
                                            ),
                                            child: Text(
                                              "• $iName ${iQty.isNotEmpty ? '($iQty)' : ''}",
                                              style: TextStyle(
                                                color: isConsumed
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600],
                                                fontSize: 13,
                                              ),
                                            ),
                                          );
                                        })
                                      else
                                        Text(
                                          qtyDisplay,
                                          style: TextStyle(
                                            color: isConsumed
                                                ? Colors.grey[400]
                                                : (qtyDisplay == "A piacere"
                                                    ? AppColors.primary
                                                    : Colors.grey[600]),
                                            fontSize: 13,
                                            fontStyle: qtyDisplay == "A piacere"
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // Azioni
                                if (!isConsumed) ...[
                                  // Swap
                                  if (cadCode > 0)
                                    IconButton(
                                      icon: Icon(
                                        isSwapped
                                            ? Icons.swap_horiz
                                            : Icons.swap_horiz_outlined,
                                        color: isSwapped
                                            ? Colors.orange
                                            : Colors.grey[400],
                                      ),
                                      splashRadius: 20,
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      onPressed: () => onSwap(swapKey, cadCode),
                                    ),

                                  // Consuma
                                  if (isToday)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: InkWell(
                                        onTap: () => onEat(index),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check,
                                            size: 18,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
