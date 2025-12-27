import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/meal_card.dart';
import '../models/active_swap.dart';
import '../models/pantry_item.dart';
import '../providers/diet_provider.dart';

class DietView extends StatelessWidget {
  final Map<String, dynamic>? dietData;
  final bool isLoading;
  final TabController tabController;
  final List<String> days;
  final Map<String, ActiveSwap> activeSwaps;
  final Map<String, dynamic>? substitutions;
  final List<PantryItem> pantryItems;
  final bool isTranquilMode;

  final Function(String, String) onConsume;
  final Function(String, String, int, String, String) onEdit;
  final Function(String swapKey, int cadCode) onSwap;

  const DietView({
    super.key,
    required this.dietData,
    required this.isLoading,
    required this.tabController,
    required this.days,
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
      children: days.map((day) => _buildDayList(context, day)).toList(),
    );
  }

  Widget _buildDayList(BuildContext context, String day) {
    final dayPlan = dietData![day];
    if (dayPlan == null) return const Center(child: Text("Nessun piano."));

    const mealOrder = [
      "Colazione",
      "Seconda Colazione",
      "Spuntino", // Aggiunto per robustezza
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

    if (validMeals.isEmpty) {
      return const Center(
        child: Text(
          "Giorno Libero! 🎉",
          style: TextStyle(fontSize: 18, color: Colors.green),
        ),
      );
    }

    // [FIX] Pull-to-refresh per aggiornare lo stato disponibilità (bordi verdi)
    return RefreshIndicator(
      onRefresh: () async {
        await Provider.of<DietProvider>(
          context,
          listen: false,
        ).refreshAvailability();
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
              isTranquilMode: isTranquilMode,
              mealName: mealName,
              foods: foods,
              activeSwaps: activeSwaps,
              onSwap: (String fullKey, int cad) {
                onSwap(fullKey, cad);
              },
              onEdit: (int itemIndex, String name, String qty) {
                onEdit(day, mealName, itemIndex, name, qty);
              },
            ),
          );
        },
      ),
    );
  }
}
