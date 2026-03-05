import 'package:cloud_firestore/cloud_firestore.dart';

enum POStatus { draft, ordered, received }

class POItem {
  final String componentId;
  final String name;
  final int quantity;
  final double costPerUnit;

  POItem({
    required this.componentId,
    required this.name,
    required this.quantity,
    required this.costPerUnit,
  });

  Map<String, dynamic> toMap() => {
    'componentId': componentId,
    'name': name,
    'quantity': quantity,
    'costPerUnit': costPerUnit,
  };

  factory POItem.fromMap(Map<String, dynamic> map) {
    return POItem(
      componentId: map['componentId'] ?? '',
      name: map['name'] ?? '',
      quantity: map['quantity']?.toInt() ?? 0,
      costPerUnit: (map['costPerUnit'] ?? 0.0).toDouble(),
    );
  }
}

class PurchaseOrder {
  final String id;
  final String supplierName;
  final DateTime orderDate;
  final POStatus status;
  final List<POItem> items;
  final double totalCost;

  PurchaseOrder({
    required this.id,
    required this.supplierName,
    required this.orderDate,
    required this.status,
    required this.items,
  }) : totalCost = items.fold(0, (sum, item) => sum + (item.quantity * item.costPerUnit));

  Map<String, dynamic> toMap() {
    return {
      'supplierName': supplierName,
      'orderDate': Timestamp.fromDate(orderDate),
      'status': status.name,
      'items': items.map((x) => x.toMap()).toList(),
      'totalCost': totalCost,
    };
  }

  factory PurchaseOrder.fromMap(String id, Map<String, dynamic> map) {
    DateTime date;
    if (map['orderDate'] != null) {
      date = (map['orderDate'] as Timestamp).toDate();
    } else {
      date = DateTime.now();
    }

    return PurchaseOrder(
      id: id,
      supplierName: map['supplierName'] ?? 'Unknown',
      orderDate: date,
      status: POStatus.values.firstWhere(
          (e) => e.name == map['status'],
          orElse: () => POStatus.draft),
      items: List<POItem>.from(
          (map['items'] ?? []).map((x) => POItem.fromMap(x))),
    );
  }
}
