import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/active_swap.dart';
import '../constants.dart';
import '../providers/diet_provider.dart';

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
    // Check Day
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

    // Grouping Logic
    List<List<dynamic>> groupedFoods = [];
    List<dynamic> currentGroup = [];
    for (var food in foods) {
      String qty = food['qty']?.toString() ?? "";
      bool isHeader = qty == "N/A";
      if (isHeader) {
        if (currentGroup.isNotEmpty) groupedFoods.add(List.from(currentGroup));
        currentGroup = [food];
      } else {
        if (currentGroup.isNotEmpty)
          currentGroup.add(food);
        else
          groupedFoods.add([food]);
      }
    }
    if (currentGroup.isNotEmpty) groupedFoods.add(List.from(currentGroup));

    int globalIndex = 0;

    return Card(
      elevation: 2, // Slightly increased elevation
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ), // Rounder
      margin: const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: 12,
      ), // [FIX] Bigger margin
      child: Padding(
        padding: const EdgeInsets.all(16.0), // [FIX] Bigger padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              mealName.toUpperCase(),
              style: TextStyle(
                fontSize: 14, // [FIX] Larger Header
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

              // Logic
              final String availabilityKey =
                  "${day}_${mealName}_$currentGroupStart";
              final isAvailable =
                  Provider.of<DietProvider>(
                    context,
                  ).availabilityMap[availabilityKey] ??
                  false;

              var header = group[0];
              int cadCode =
                  int.tryParse(header['cad_code']?.toString() ?? "0") ?? 0;
              String swapKey = "${day}_${mealName}_group_$groupIndex";
              bool isSwapped = activeSwaps.containsKey(swapKey);

              // Decide colors based on Tranquil Mode
              Color bgColor = Colors.grey.withOpacity(0.05);
              Color? borderColor;
              if (!isTranquilMode) {
                borderColor = isAvailable
                    ? Colors.green.withOpacity(0.5)
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
                margin: const EdgeInsets.only(
                  bottom: 12,
                ), // [FIX] More spacing between dishes
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
                    // Status Icon (Hidden in Tranquil Mode)
                    if (!isTranquilMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 12),
                        child: Icon(
                          isAvailable
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                          color: isAvailable ? Colors.green : Colors.grey[400],
                          size: 20, // [FIX] Bigger icon
                        ),
                      ),

                    // Food Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: itemsToShow.asMap().entries.map((itemEntry) {
                          var item = itemEntry.value;
                          String name = item['name']?.toString() ?? "Piatto";
                          String qty = item['qty']?.toString() ?? "";
                          bool isHeaderItem = (qty == "N/A" || qty.isEmpty);

                          String textDisplay;

                          // [FIX] Tranquil Mode Logic restored
                          if (isTranquilMode) {
                            textDisplay = name; // Only show name, hide quantity
                          } else {
                            textDisplay = (isHeaderItem || qty.isEmpty)
                                ? name
                                : "$name ($qty)";
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              textDisplay,
                              style: TextStyle(
                                fontSize: 16, // [FIX] Bigger font
                                height: 1.3,
                                color: isSwapped
                                    ? Colors.blueGrey[700]
                                    : Colors.black87,
                                fontWeight: (isHeaderItem && !isSwapped)
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Actions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (cadCode > 0)
                          SizedBox(
                            width: 40, // [FIX] Bigger touch target
                            height: 40,
                            child: IconButton(
                              icon: const Icon(Icons.swap_horiz, size: 22),
                              color: Colors.blueGrey,
                              onPressed: () => onSwap(swapKey, cadCode),
                            ),
                          ),
                        if (isToday)
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton(
                              icon: const Icon(Icons.check, size: 22),
                              color: Colors.green,
                              onPressed: () {
                                Provider.of<DietProvider>(
                                  context,
                                  listen: false,
                                ).consumeMeal(day, mealName, currentGroupStart);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Rimosso dal frigo"),
                                    duration: Duration(milliseconds: 800),
                                  ),
                                );
                              },
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
