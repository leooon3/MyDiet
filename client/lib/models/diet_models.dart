class Ingredient {
  final String name;
  final String qty;

  Ingredient({required this.name, required this.qty});

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name']?.toString() ?? '',
      qty: json['qty']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'qty': qty};
}

class Dish {
  final String instanceId; // Corrisponde al server uuid
  final String name;
  final String qty;
  final int cadCode;
  final bool isComposed;
  final List<Ingredient> ingredients;

  // Stato Locale (Non arriva dal server, serve per la UI)
  bool isConsumed;

  Dish({
    required this.instanceId,
    required this.name,
    required this.qty,
    required this.cadCode,
    required this.isComposed,
    required this.ingredients,
    this.isConsumed = false,
  });

  factory Dish.fromJson(Map<String, dynamic> json) {
    return Dish(
      instanceId: json['instance_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Sconosciuto',
      qty: json['qty']?.toString() ?? '',
      cadCode: (json['cad_code'] is int) ? json['cad_code'] : 0,
      isComposed: json['is_composed'] ?? false,
      ingredients: (json['ingredients'] as List<dynamic>?)
              ?.map((e) => Ingredient.fromJson(e))
              .toList() ??
          [],
      // Recuperiamo lo stato consumato se salvato in locale
      isConsumed: json['consumed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'instance_id': instanceId,
        'name': name,
        'qty': qty,
        'cad_code': cadCode,
        'is_composed': isComposed,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'consumed': isConsumed, // Salviamo lo stato locale
      };
}

class SubstitutionOption {
  final String name;
  final String qty;

  SubstitutionOption({required this.name, required this.qty});

  factory SubstitutionOption.fromJson(Map<String, dynamic> json) {
    return SubstitutionOption(
      name: json['name']?.toString() ?? '',
      qty: json['qty']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'qty': qty};
}

class SubstitutionGroup {
  final String name;
  final List<SubstitutionOption> options;

  SubstitutionGroup({required this.name, required this.options});

  factory SubstitutionGroup.fromJson(Map<String, dynamic> json) {
    return SubstitutionGroup(
      name: json['name']?.toString() ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((e) => SubstitutionOption.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() =>
      {'name': name, 'options': options.map((e) => e.toJson()).toList()};
}

class DietPlan {
  // Struttura rigida: Giorno -> Pasto -> Lista di Piatti
  final Map<String, Map<String, List<Dish>>> plan;
  final Map<String, SubstitutionGroup> substitutions;

  DietPlan({required this.plan, required this.substitutions});

  factory DietPlan.fromJson(Map<String, dynamic> json) {
    // Parsing Piano
    Map<String, Map<String, List<Dish>>> parsedPlan = {};
    if (json['plan'] != null) {
      (json['plan'] as Map<String, dynamic>).forEach((day, meals) {
        Map<String, List<Dish>> dayMeals = {};
        (meals as Map<String, dynamic>).forEach((mealType, dishes) {
          dayMeals[mealType] =
              (dishes as List<dynamic>).map((d) => Dish.fromJson(d)).toList();
        });
        parsedPlan[day] = dayMeals;
      });
    }

    // Parsing Sostituzioni
    Map<String, SubstitutionGroup> parsedSubs = {};
    if (json['substitutions'] != null) {
      (json['substitutions'] as Map<String, dynamic>).forEach((k, v) {
        parsedSubs[k] = SubstitutionGroup.fromJson(v);
      });
    }

    return DietPlan(plan: parsedPlan, substitutions: parsedSubs);
  }

  // Fondamentale per il salvataggio su Firestore/Locale
  Map<String, dynamic> toJson() {
    Map<String, dynamic> jsonPlan = {};
    plan.forEach((day, meals) {
      Map<String, dynamic> jsonMeals = {};
      meals.forEach((type, dishes) {
        jsonMeals[type] = dishes.map((d) => d.toJson()).toList();
      });
      jsonPlan[day] = jsonMeals;
    });

    Map<String, dynamic> jsonSubs = {};
    substitutions.forEach((k, v) {
      jsonSubs[k] = v.toJson();
    });

    return {'plan': jsonPlan, 'substitutions': jsonSubs};
  }
}
