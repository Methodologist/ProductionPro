class Component {
  final String id;
  final String name;
  int quantity;
  int minStock;
  double costPerUnit;
  String barcode;
  bool isActive;
  String? imageUrl;

  Component({
    required this.id,
    required this.name,
    this.quantity = 0,
    this.minStock = 10,
    this.costPerUnit = 0.0,
    this.barcode = '',
    this.isActive = true,
    this.imageUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'minStock': minStock,
      'costPerUnit': costPerUnit,
      'barcode': barcode,
      'isActive': isActive,
      'imageUrl': imageUrl,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory Component.fromMap(String id, Map<String, dynamic> data) {
    return Component(
      id: id,
      name: data['name'] ?? '',
      quantity: (data['quantity'] ?? 0).toInt(),
      minStock: (data['minStock'] ?? 10).toInt(),
      costPerUnit: (data['costPerUnit'] ?? 0.0).toDouble(),
      barcode: data['barcode'] ?? '',
      isActive: data['isActive'] ?? true,
      imageUrl: data['imageUrl'],
    );
  }
}