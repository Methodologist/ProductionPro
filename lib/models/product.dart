import 'component.dart';

class Product {
  final String id;
  final String name;
  final Map<String, int> componentsNeeded;
  int producedCount;
  int lastBatchAmount;
  double sellingPrice;
  final bool isActive;

  Product({
    required this.id,
    required this.name,
    required this.componentsNeeded,
    this.producedCount = 0,
    this.lastBatchAmount = 0,
    this.sellingPrice = 0.0,
    this.isActive = true,
  });

  double getProductionCost(List<Component> allComponents) {
    double total = 0.0;
    componentsNeeded.forEach((compId, qty) {
      final comp = allComponents.firstWhere(
        (c) => c.id == compId,
        orElse: () => Component(id: '', name: '', quantity: 0, minStock: 0, costPerUnit: 0),
      );
      total += (comp.costPerUnit * qty);
    });
    return total;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'componentsNeeded': componentsNeeded,
        'producedCount': producedCount,
        'lastBatchAmount': lastBatchAmount,
        'sellingPrice': sellingPrice,
        'isActive': isActive,
      };

  factory Product.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic val) => (val is num) ? val.toInt() : 0;
    double toDouble(dynamic val) => (val is num) ? val.toDouble() : 0.0;

    return Product(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      componentsNeeded: Map<String, int>.from(json['componentsNeeded'] ?? {}),
      producedCount: toInt(json['producedCount']),
      lastBatchAmount: toInt(json['lastBatchAmount']),
      sellingPrice: toDouble(json['sellingPrice']),
      isActive: json['isActive'] ?? true,
    );
  }
}
