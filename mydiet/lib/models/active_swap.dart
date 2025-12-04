class ActiveSwap {
  String name;
  String qty;
  ActiveSwap({required this.name, required this.qty});

  Map<String, dynamic> toJson() => {'name': name, 'qty': qty};
  factory ActiveSwap.fromJson(Map<String, dynamic> json) =>
      ActiveSwap(name: json['name'], qty: json['qty']);
}
