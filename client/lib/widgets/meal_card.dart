import 'package:flutter/material.dart';
import '../models/active_swap.dart';

class MealCard extends StatelessWidget {
  final String day;
  final String mealName;
  final List<dynamic> foods;
  final Map<String, ActiveSwap> activeSwaps;
  final Map<String, bool> availabilityMap;
  final bool isTranquilMode;
  final Function(String key, int currentCad) onSwap;
  final Function(int index, String name, String qty)? onEdit;
  final Function(int index) onEat;

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
    'mirtilli',
    'lamponi',
    'more',
    'cachi',
    'fico',
    'fichi',
    'melograno',
    'avocado',
    'mango',
    'papaya',
    'zucchina',
    'zucchine',
    'melanzana',
    'melanzane',
    'peperone',
    'peperoni',
    'pomodoro',
    'pomodori',
    'insalata',
    'lattuga',
    'rucola',
    'spinaci',
    'spinacio',
    'bieta',
    'bietola',
    'cicoria',
    'cavolo',
    'cavoli',
    'verza',
    'cappuccio',
    'broccoli',
    'broccolo',
    'cavolfiore',
    'fagiolino',
    'fagiolini',
    'asparago',
    'asparagi',
    'carciofo',
    'carciofi',
    'finocchio',
    'finocchi',
    'sedano',
    'carota',
    'carote',
    'cetriolo',
    'cetrioli',
    'zucca',
    'patata',
    'patate',
    'cipolla',
    'cipolle',
    'aglio',
    'scalogno',
    'porro',
    'porri',
    'ravanello',
    'ravanelli',
    'rapa',
    'cime di rapa',
    'radicchio',
    'valeriana',
    'indivia',
    'fungo',
    'funghi',
    'oliva',
    'olive',
    'mais',
    'fagioli',
    'ceci',
    'lenticchie',
    'piselli',
    'fave',
    'soia',
    'edamame',
    'olio',
    'aceto',
    'sale',
    'pepe',
    'spezie',
    'verdura',
    'verdure',
    'frutta',
    'frutto',
    'ortaggi',
    'minestrone',
    'passato di verdure',
    'vellutata',
    'contorno',
  };

  const MealCard({
    super.key,
    required this.day,
    required this.mealName,
    required this.foods,
    required this.activeSwaps,
    required this.availabilityMap,
    required this.isTranquilMode,
    required this.onSwap,
    required this.onEat,
    this.onEdit,
  });

  String _formatDisplayQty(String rawQty) {
    if (rawQty.isEmpty || rawQty == "N/A") return "";
    final numRegExp = RegExp(r'(\d+[.,]?\d*)');
    final match = numRegExp.firstMatch(rawQty);
    String number = match?.group(1) ?? "";

    String unit = "";
    String lower = rawQty.toLowerCase();

    if (lower.contains('kg')) {
      unit = "kg";
    } else if (lower.contains('mg')) {
      unit = "mg";
    } else if (lower.contains('ml')) {
      unit = "ml";
    } else if (lower.contains('l') && !lower.contains('ml')) {
      unit = "L";
    } else if (RegExp(r'\b(gr|g|grammi)\b').hasMatch(lower)) {
      unit = "g";
    } else if (lower.contains('vasett')) {
      unit = "vasetto";
    } else if (lower.contains('cucchiain')) {
      unit = "cucchiaino";
    } else if (lower.contains('cucchiai')) {
      unit = "cucchiaio";
    } else if (lower.contains('fett')) {
      unit = "fette";
    } else if (lower.contains('pz')) {
      unit = "pz";
    }

    if (number.isNotEmpty && unit.isNotEmpty) {
      return "$number $unit";
    }
    return rawQty;
  }

  @override
  Widget build(BuildContext context) {
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
    bool isToday = false;
    if (todayIndex >= 0 && todayIndex < italianDays.length) {
      isToday = day.toLowerCase() == italianDays[todayIndex].toLowerCase();
    }

    List<List<dynamic>> groupedFoods = [];
    List<dynamic> currentGroup = [];
    for (var food in foods) {
      String qty = food['qty']?.toString() ?? "";
      bool isHeader = qty == "N/A";
      if (isHeader) {
        if (currentGroup.isNotEmpty) groupedFoods.add(List.from(currentGroup));
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

    int globalIndex = 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                color: Colors.grey[700],
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ...groupedFoods.asMap().entries.map((entry) {
              int groupIndex = entry.key;
              List<dynamic> group = entry.value;
              int currentGroupStart = globalIndex;
              globalIndex += group.length;

              if (group.isEmpty) return const SizedBox.shrink();

              var header = group[0];
              bool isConsumed = header['consumed'] == true;

              final String availabilityKey =
                  "${day}_${mealName}_$currentGroupStart";
              final isAvailable =
                  !isConsumed && (availabilityMap[availabilityKey] ?? false);

              int cadCode =
                  int.tryParse(header['cad_code']?.toString() ?? "0") ?? 0;
              String swapKey = "${day}_${mealName}_group_$groupIndex";
              bool isSwapped = activeSwaps.containsKey(swapKey);

              Color bgColor = Colors.grey.withValues(alpha: 0.05);
              Color? borderColor;

              if (!isConsumed) {
                borderColor = isAvailable
                    ? Colors.green.withValues(alpha: 0.5)
                    : Colors.transparent;
              }

              List<dynamic> itemsToShow;
              if (isSwapped) {
                final swap = activeSwaps[swapKey]!;
                if (swap.swappedIngredients != null &&
                    swap.swappedIngredients!.isNotEmpty) {
                  itemsToShow = swap.swappedIngredients!;
                } else {
                  String q = swap.qty;
                  if (swap.unit.isNotEmpty) q += " ${swap.unit}";
                  itemsToShow = [
                    {'name': swap.name, 'qty': q},
                  ];
                }
              } else {
                itemsToShow = [];
                for (var item in group) {
                  itemsToShow.add(item);
                  if (item['ingredients'] != null &&
                      (item['ingredients'] as List).isNotEmpty) {
                    itemsToShow.addAll(item['ingredients']);
                  }
                }
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: borderColor != null
                      ? Border.all(color: borderColor, width: 1.5)
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isConsumed)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 12),
                        child: Icon(
                          isAvailable
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                          color: isAvailable ? Colors.green : Colors.grey[400],
                          size: 20,
                        ),
                      ),
                    if (isConsumed)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 12),
                        child: Icon(
                          Icons.check,
                          color: Colors.grey[300],
                          size: 20,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: itemsToShow.asMap().entries.map((itemEntry) {
                          var item = itemEntry.value;
                          String name = item['name']?.toString() ?? "Piatto";
                          String rawQty = item['qty']?.toString() ?? "";

                          String displayQty = _formatDisplayQty(rawQty);

                          bool isHeaderItem =
                              (rawQty == "N/A" || rawQty.isEmpty);

                          bool shouldHideQty = false;
                          if (isTranquilMode) {
                            String cleanName = name.toLowerCase();
                            for (var w in _relaxableFoods) {
                              if (cleanName.contains(w)) {
                                shouldHideQty = true;
                                break;
                              }
                            }
                          }

                          String textDisplay;
                          if (shouldHideQty) {
                            textDisplay = name;
                          } else {
                            textDisplay = (isHeaderItem || displayQty.isEmpty)
                                ? name
                                : "$name ($displayQty)";
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              textDisplay,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.3,
                                color: isConsumed
                                    ? Colors.grey[400]
                                    : (isSwapped
                                          ? Colors.blueGrey[700]
                                          : Colors.black87),
                                decoration: isConsumed
                                    ? TextDecoration.lineThrough
                                    : null,
                                fontWeight: (isHeaderItem && !isSwapped)
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (cadCode > 0 && !isConsumed)
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              icon: const Icon(Icons.swap_horiz, size: 22),
                              color: Colors.blueGrey,
                              onPressed: () => onSwap(swapKey, cadCode),
                            ),
                          ),
                        if (isToday && !isConsumed)
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              icon: const Icon(Icons.check, size: 22),
                              color: Colors.green,
                              onPressed: () => onEat(currentGroupStart),
                            ),
                          ),
                      ],
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
