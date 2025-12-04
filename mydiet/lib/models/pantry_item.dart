class PantryItem {
  String name;
  double quantity;
  String unit; // "g" o "pz"

  PantryItem({required this.name, required this.quantity, required this.unit});

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'unit': unit,
  };
  factory PantryItem.fromJson(Map<String, dynamic> json) => PantryItem(
    name: json['name'],
    quantity: json['quantity'],
    unit: json['unit'],
  );
}
