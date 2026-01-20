import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/diet_provider.dart';
import '../widgets/meal_card.dart';
import '../models/active_swap.dart';
import '../models/pantry_item.dart';
import '../models/diet_models.dart'; // Importa il modello
import '../core/error_handler.dart';
import '../logic/diet_calculator.dart';

class DietView extends StatelessWidget {
  final String day;
  final DietPlan? dietPlan; // [FIX] Accetta l'oggetto DietPlan
  final bool isLoading;
  final Map<String, ActiveSwap> activeSwaps;
  // substitutions rimosso perché incluso in dietPlan
  final List<PantryItem> pantryItems;
  final bool isTranquilMode;

  const DietView({
    super.key,
    required this.day,
    required this.dietPlan, // [FIX] Aggiornato
    required this.isLoading,
    required this.activeSwaps,
    // substitutions rimosso
    required this.pantryItems,
    required this.isTranquilMode,
  });

  bool _isToday(String dayName) {
    final now = DateTime.now();
    final italianDays = [
      "Lunedì",
      "Martedì",
      "Mercoledì",
      "Giovedì",
      "Venerdì",
      "Sabato",
      "Domenica"
    ];
    int index = now.weekday - 1;
    if (index >= 0 && index < italianDays.length) {
      return italianDays[index].toLowerCase() == dayName.toLowerCase();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // [FIX] Controllo sull'oggetto e sulla mappa interna
    if (dietPlan == null || dietPlan!.plan.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            const Text(
              "Nessuna dieta caricata.",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // [FIX] Accesso tipizzato alla mappa plan
    final mealsOfDay = dietPlan!.plan[day];

    if (mealsOfDay == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bed_outlined, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text(
              "Riposo (nessun piano per $day)",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final mealTypes = [
      "Colazione",
      "Seconda Colazione",
      "Spuntino",
      "Pranzo",
      "Merenda",
      "Cena",
      "Spuntino Serale",
      "Nell'Arco Della Giornata",
    ];

    final bool isCurrentDay = _isToday(day);

    return Container(
      color: const Color(0xFFF5F5F5),
      child: RefreshIndicator(
        onRefresh: () async =>
            context.read<DietProvider>().refreshAvailability(),
        child: ListView(
          padding: const EdgeInsets.only(top: 10, bottom: 80),
          children: mealTypes.map((mealType) {
            if (!mealsOfDay.containsKey(mealType)) {
              return const SizedBox.shrink();
            }

            return MealCard(
              day: day,
              mealName: mealType,
              foods: mealsOfDay[mealType]!, // [FIX] Passa List<Dish>
              activeSwaps: activeSwaps,
              availabilityMap: context.watch<DietProvider>().availabilityMap,
              isTranquilMode: isTranquilMode,
              isToday: isCurrentDay,
              onEat: (index) => _handleConsume(context, day, mealType, index),
              onSwap: (key, cadCode) => _showSwapDialog(context, key, cadCode),
              onEdit: (index, name, qty) => context
                  .read<DietProvider>()
                  .updateDietMeal(day, mealType, index, name, qty),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _handleConsume(
    BuildContext context,
    String day,
    String mealType,
    int index,
  ) async {
    final provider = context.read<DietProvider>();
    try {
      await provider.consumeMeal(day, mealType, index);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Pasto consumato!"),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;

      if (e is UnitMismatchException) {
        _showConversionDialog(context, provider, e);
      } else if (e is IngredientException) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Ingrediente Mancante"),
            content: Text(
              "${e.message}\n\nVuoi segnarlo come consumato ugualmente?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("No"),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  provider.consumeMeal(day, mealType, index, force: true);
                },
                child: const Text("Sì, consuma"),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMapper.toUserMessage(e))));
      }
    }
  }

  void _showConversionDialog(
    BuildContext context,
    DietProvider provider,
    UnitMismatchException e,
  ) {
    // ... (Logica invariata, ma usa e.item che ora è typed se DietLogic è aggiornato)
    // Per sicurezza, assumiamo che DietLogic lanci l'eccezione corretta
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Conversione Unità"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "La dieta usa '${e.requiredUnit}' ma in dispensa hai '${e.item.unit}'.",
            ),
            const SizedBox(height: 10),
            Text(
              "A quanti ${e.item.unit} corrisponde 1 ${e.requiredUnit}?",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                suffixText: e.item.unit,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annulla"),
          ),
          FilledButton(
            onPressed: () {
              double? val = double.tryParse(
                controller.text.replaceAll(',', '.'),
              );
              if (val != null && val > 0) {
                provider.resolveUnitMismatch(
                  e.item.name,
                  e.requiredUnit,
                  e.item.unit,
                  val,
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Conversione salvata. Riprova a consumare."),
                  ),
                );
              }
            },
            child: const Text("Salva"),
          ),
        ],
      ),
    );
  }

  // [FIX] Logica Swap aggiornata per usare DietPlan (Oggetti) invece di Map
  void _showSwapDialog(BuildContext context, String swapKey, int cadCode) {
    // Accesso sicuro tramite dietPlan
    final subs = dietPlan?.substitutions;
    final String lookupCode = cadCode.toString();

    // Controllo esistenza sostituzioni
    if (subs == null ||
        !subs.containsKey(lookupCode) ||
        subs[lookupCode]!.options.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Nessuna Sostituzione"),
          content: const Text(
            "Il nutrizionista non ha indicato alternative per questo alimento.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    // [FIX] Estrazione dati tipizzati
    final substitutionGroup = subs[lookupCode]!;
    final List<SubstitutionOption> options = substitutionGroup.options;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return ListView.builder(
          itemCount: options.length,
          itemBuilder: (ctx, idx) {
            final opt = options[idx]; // SubstitutionOption object
            return ListTile(
              title: Text(opt.name), // .name
              subtitle: Text(opt.qty), // .qty
              onTap: () {
                final newSwap = ActiveSwap(
                  name: opt.name,
                  qty: opt.qty,
                  unit: "",
                  swappedIngredients: [],
                );
                context.read<DietProvider>().swapMeal(swapKey, newSwap);
                Navigator.pop(ctx);
              },
            );
          },
        );
      },
    );
  }
}
