import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/diet_provider.dart';
import '../widgets/meal_card.dart';
import '../models/active_swap.dart';
import '../models/pantry_item.dart';

class DietView extends StatelessWidget {
  final TabController tabController;
  final List<String> days;
  final Map<String, dynamic>? dietData;
  final bool isLoading;
  final Map<String, ActiveSwap> activeSwaps;
  final Map<String, dynamic>? substitutions;
  final List<PantryItem> pantryItems;
  final bool isTranquilMode;
  final Function(String, String) onConsume;
  final Function(String, String, int, String, String) onEdit;
  final Function(String, int) onSwap;

  const DietView({
    super.key,
    required this.tabController,
    required this.days,
    required this.dietData,
    required this.isLoading,
    required this.activeSwaps,
    required this.substitutions,
    required this.pantryItems,
    required this.isTranquilMode,
    required this.onConsume,
    required this.onEdit,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (dietData == null || dietData!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.no_meals, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              "Nessuna dieta caricata.\nUsa il menu laterale per iniziare!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: tabController,
      children: days.map((day) {
        if (!dietData!.containsKey(day)) {
          return const Center(child: Text("Riposo o nessun dato."));
        }
        return _buildDayList(context, day);
      }).toList(),
    );
  }

  Widget _buildDayList(BuildContext context, String day) {
    final provider = context.read<DietProvider>();
    final dayPlan = dietData![day];

    if (dayPlan == null) return const Center(child: Text("Nessun piano."));

    const mealOrder = [
      "Colazione",
      "Seconda Colazione",
      "Spuntino",
      "Pranzo",
      "Merenda",
      "Cena",
      "Spuntino Serale",
      "Nell'Arco Della Giornata",
    ];

    final validMeals = mealOrder.where((mealName) {
      final foods = dayPlan[mealName];
      return foods != null && (foods as List).isNotEmpty;
    }).toList();

    final allKeys = (dayPlan as Map<String, dynamic>).keys.toList();
    for (var key in allKeys) {
      if (!mealOrder.contains(key) && !validMeals.contains(key)) {
        final foods = dayPlan[key];
        if (foods != null && (foods as List).isNotEmpty) {
          validMeals.add(key);
        }
      }
    }

    if (validMeals.isEmpty) {
      return const Center(
        child: Text(
          "Giorno Libero! 🎉",
          style: TextStyle(fontSize: 18, color: Colors.green),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.refreshAvailability();
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: validMeals.length,
        itemBuilder: (context, index) {
          final mealName = validMeals[index];
          final foods = dayPlan[mealName];

          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: MealCard(
              day: day,
              mealName: mealName,
              foods: foods,
              activeSwaps: activeSwaps,
              availabilityMap: provider.availabilityMap,
              isTranquilMode: isTranquilMode,
              onSwap: (String fullKey, int cad) => onSwap(fullKey, cad),
              onEdit: (int itemIndex, String name, String qty) =>
                  onEdit(day, mealName, itemIndex, name, qty),
              onEat: (dishIndex) async {
                final availabilityKey = "${day}_${mealName}_$dishIndex";
                final isAvailable =
                    provider.availabilityMap[availabilityKey] ?? false;

                if (!isAvailable) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Ingrediente Mancante"),
                      content: const Text(
                        "Questo piatto non risulta disponibile in frigo.\nVuoi segnarlo come mangiato lo stesso?",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            "Annulla",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _attemptConsume(
                              context,
                              provider,
                              day,
                              mealName,
                              dishIndex,
                            );
                          },
                          child: const Text("Sì, procedi"),
                        ),
                      ],
                    ),
                  );
                } else {
                  _attemptConsume(context, provider, day, mealName, dishIndex);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _attemptConsume(
    BuildContext context,
    DietProvider provider,
    String day,
    String mealName,
    int dishIndex,
  ) async {
    try {
      await provider.consumeMeal(day, mealName, dishIndex);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pasto consumato! 😋"),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } on UnitMismatchException catch (e) {
      if (context.mounted) {
        _showMismatchDialog(context, provider, e, day, mealName, dishIndex);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Errore: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showMismatchDialog(
    BuildContext context,
    DietProvider provider,
    UnitMismatchException e,
    String day,
    String mealType,
    int index,
  ) {
    final item = e.item;
    final reqQty = e.requiredQty;
    final reqUnit = e.requiredUnit;

    final TextEditingController ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Unità Diversa ⚖️"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Richiesto: $reqQty $reqUnit"),
            Text("Dispensa: ${item.quantity} ${item.unit} (${item.name})"),
            const SizedBox(height: 16),
            Text("Quanti '${item.unit}' hai consumato?"),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: "Es. ${item.quantity}",
                suffixText: item.unit,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            const Text(
              "Il sistema imparerà questa conversione per il futuro.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annulla"),
          ),
          FilledButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (val != null && val > 0) {
                // Gestione specifica per 'pz' (unità sconosciuta)
                if (reqUnit == 'pz') {
                  // Impariamo che 1 pz = X unità dispensa (val/reqQty)
                  double pzConversion = val / reqQty;
                  await provider.resolveUnitMismatch(
                    item.name,
                    'pz',
                    pzConversion,
                  );
                  // Impariamo anche che l'unità dispensa è la base (1.0)
                  await provider.resolveUnitMismatch(item.name, item.unit, 1.0);
                } else {
                  double gramsPerUnit = reqQty / val;
                  await provider.resolveUnitMismatch(
                    item.name,
                    item.unit,
                    gramsPerUnit,
                  );
                }
                if (!context.mounted) return;
                Navigator.pop(ctx);
                _attemptConsume(context, provider, day, mealType, index);
              }
            },
            child: const Text("Conferma"),
          ),
        ],
      ),
    );
  }
}
