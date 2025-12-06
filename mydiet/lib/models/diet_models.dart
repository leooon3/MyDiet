class DietPlan {
  final Map<String, dynamic> plan;
  final Map<String, dynamic> substitutions;

  DietPlan({required this.plan, required this.substitutions});

  factory DietPlan.fromJson(Map<String, dynamic> json) {
    return DietPlan(
      plan: json['plan'] ?? {},
      substitutions: json['substitutions'] ?? {},
    );
  }
}
