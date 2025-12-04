import 'package:flutter/material.dart';
import '../widgets/meal_card.dart';
import '../models/active_swap.dart';
import '../models/pantry_item.dart';

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
  final Function(String, String, int, String, String) onSwap;

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

    // Controllo sicurezza dati
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
      // physics: const NeverScrollableScrollPhysics(), // Decommenta se vuoi disabilitare lo swipe laterale tra i giorni
      children: days.map((day) => _buildDayList(day)).toList(),
    );
  }

  Widget _buildDayList(String day) {
    final dayPlan = dietData![day];

    if (dayPlan == null) {
      return const Center(child: Text("Nessun piano per questo giorno."));
    }

    // Lista standard dei pasti ordinati
    const mealOrder = [
      "Colazione",
      "Seconda Colazione",
      "Pranzo",
      "Merenda",
      "Cena",
      "Spuntino Serale",
      "Nell'Arco Della Giornata",
    ];

    // FILTRO PREVENTIVO:
    // Creiamo una lista solo dei pasti che esistono e non sono vuoti.
    // Questo evita di creare widget vuoti inutili che appesantiscono la memoria.
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

    // Usa ListView.builder per efficienza (renderizza solo ciò che vedi)
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        100,
      ), // Più spazio in fondo per non coprire l'ultimo pasto
      physics: const BouncingScrollPhysics(),
      itemCount: validMeals.length,
      itemBuilder: (context, index) {
        final mealName = validMeals[index];
        final foods = dayPlan[mealName];

        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0), // Spazio tra le card
          child: MealCard(
            day: day,
            mealName: mealName,
            foods: foods,
            activeSwaps: activeSwaps,
            substitutions: substitutions,
            pantryItems: pantryItems,
            isTranquilMode: isTranquilMode,
            onConsume: onConsume,
            onEdit: onEdit,
            onSwap: onSwap,
          ),
        );
      },
    );
  }
}
