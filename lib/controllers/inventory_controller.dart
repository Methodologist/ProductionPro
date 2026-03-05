import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'dart:io';

import '../models/models.dart';

// --- FIRESTORE INVENTORY MANAGER ---
class InventoryManager extends ChangeNotifier {
  UserProfile user;
  bool isCurrentCompanyPro = false;
  String? stripeCustomerId;

  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'east-5',
  );

  List<Component> components = [];
  List<Product> products = [];

  StreamSubscription? _compSub;
  StreamSubscription? _prodSub;
  StreamSubscription? _companySub;

  VoidCallback? _onUpdate;

  // --- CONSTRUCTOR ---
  InventoryManager({required this.user}) {
    // Automatically initialize RevenueCat for the current organization
    initPlatformState();
  }

  void activateProAccess() {
    isCurrentCompanyPro = true;
    notifyListeners();
  }

  // --- REVENUECAT HANDSHAKE (Safe for Windows) ---
  Future<void> initPlatformState() async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      print("⚠️ RevenueCat is NOT supported on Desktop/Web. Skipping init.");
      return;
    }

    try {
      await Purchases.setLogLevel(LogLevel.debug);

      String apiKey;
      if (Platform.isAndroid) {
        apiKey = const String.fromEnvironment('RC_ANDROID_KEY', defaultValue: '');
      } else if (Platform.isIOS) {
        apiKey = const String.fromEnvironment('RC_IOS_KEY', defaultValue: '');
      } else {
        return;
      }

      final configuration = PurchasesConfiguration(apiKey);
      await Purchases.configure(configuration);

      print("✅ RevenueCat Configured on Mobile!");
      try {
        Offerings offerings = await Purchases.getOfferings();
        if (offerings.current != null) {
          print("📦 Found Offering: ${offerings.current!.identifier}");
          print("📦 Packages available: ${offerings.current!.availablePackages.length}");
        } else {
          print("⚠️ No offerings found (Normal if Store is pending)");
        }
      } catch (e) {
        print("❌ Error fetching offerings: $e");
      }

      Purchases.addCustomerInfoUpdateListener((info) {
        if (info.entitlements.all["pro"]?.isActive == true) {
          isCurrentCompanyPro = true;
          notifyListeners();
        }
      });
    } catch (e) {
      print("RevenueCat Init Error: $e");
    }
  }

  // Dynamic getters ensure we always point to the CURRENT companyId
  CollectionReference get _compsRef =>
      _db.collection('companies').doc(user.companyId).collection('components');

  CollectionReference get _prodsRef =>
      _db.collection('companies').doc(user.companyId).collection('products');

  CollectionReference get _logsRef =>
      _db.collection('companies').doc(user.companyId).collection('logs');

  // --- STARTUP LOGIC ---

  void listen(VoidCallback onDataChanged) {
    _onUpdate = onDataChanged;

    _compSub = _compsRef
        .orderBy('name')
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      components = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Component.fromMap(doc.id, data);
      }).toList();

      components.sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        int comparison = a.quantity.compareTo(b.quantity);
        if (comparison != 0) return comparison;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      onDataChanged();
    });

    _prodSub = _prodsRef
        .orderBy('name')
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      products = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return Product.fromJson(data);
      }).toList();

      products.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      onDataChanged();
    });

    _companySub = _db
        .collection('companies')
        .doc(user.companyId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data() as Map<String, dynamic>;
            isCurrentCompanyPro = data['isPro'] ?? false;
            stripeCustomerId = data['stripeCustomerId'];
            notifyListeners();
          }
        });
  }

  @override
  void dispose() {
    _compSub?.cancel();
    _prodSub?.cancel();
    _companySub?.cancel();
    super.dispose();
  }

  // --- TEAM & MEMBERS LOGIC ---

  Future<int> getTeamMemberCount() async {
    final userSnap = await _db.collection('users')
        .where('connectedCompanyIds', arrayContains: user.companyId)
        .count()
        .get();

    final inviteSnap = await _db.collection('invitations')
        .where('companyId', isEqualTo: user.companyId)
        .where('status', isEqualTo: 'pending')
        .count()
        .get();

    return (userSnap.count ?? 1) + (inviteSnap.count ?? 0);
  }

  // --- MULTI-ORG FEATURES ---

  Future<void> switchOrganization(CompanyMembership target) async {
    _compSub?.cancel();
    _prodSub?.cancel();
    _companySub?.cancel();

    await _db.collection('users').doc(user.uid).update({
      'companyId': target.companyId,
      'role': target.role,
    });
  }

  Future<void> joinOrganization(String code) async {
    final cleanCode = code.trim().toUpperCase();
    final snapshot = await _db.collection('companies').where('joinCode', isEqualTo: cleanCode).limit(1).get();

    if (snapshot.docs.isEmpty) throw Exception("Invalid Join Code");

    final companyDoc = snapshot.docs.first;
    final String targetId = companyDoc.id;
    final String targetName = companyDoc.data()['name'] ?? "Unknown Org";

    if (user.memberships.any((m) => m.companyId == targetId)) {
      throw Exception("You are already a member of $targetName");
    }

    final newMembership = {
      'companyId': targetId,
      'companyName': targetName,
      'role': 'user',
    };

    final batch = _db.batch();
    final userRef = _db.collection('users').doc(user.uid);

    batch.update(userRef, {
      'memberships': FieldValue.arrayUnion([newMembership]),
      'connectedCompanyIds': FieldValue.arrayUnion([targetId]),
      'companyId': targetId,
      'role': 'user',
    });

    await batch.commit();
    user = user.copyWith(companyId: targetId, role: 'user');
    _compSub?.cancel(); _prodSub?.cancel();
    if (_onUpdate != null) listen(_onUpdate!);
    await logActivity("Joined Org", "Joined organization: $targetName");
  }

  Future<void> createNewOrganization(String orgName) async {
    final batch = _db.batch();
    final newCompRef = _db.collection('companies').doc();
    final newCode = _generateCode();

    batch.set(newCompRef, {
      'name': orgName,
      'created_at': FieldValue.serverTimestamp(),
      'joinCode': newCode,
      'ownerId': user.uid,
    });

    final newMembership = { 'companyId': newCompRef.id, 'companyName': orgName, 'role': 'owner' };
    final userRef = _db.collection('users').doc(user.uid);
    batch.update(userRef, {
      'memberships': FieldValue.arrayUnion([newMembership]),
      'connectedCompanyIds': FieldValue.arrayUnion([newCompRef.id]),
      'companyId': newCompRef.id,
      'role': 'owner',
    });

    await batch.commit();
    user = user.copyWith(companyId: newCompRef.id, role: 'owner');
    _compSub?.cancel(); _prodSub?.cancel();
    if (_onUpdate != null) listen(_onUpdate!);
    await logActivity("Created Org", "Created new organization: $orgName");
  }

  Future<void> renameOrganization(String newName) async {
    if (!user.isOwner && !user.isBusinessAdmin) throw Exception("Access Denied");
    final companyRef = _db.collection('companies').doc(user.companyId);
    await companyRef.update({'name': newName});
    await logActivity("Renamed Org", "Renamed organization to '$newName'");
  }

  // --- ACTION METHODS ---

  Future<void> updateComponentStatus(String id, bool status) async {
    await _compsRef.doc(id).update({ 'isActive': status });
    await logActivity(status ? "Item Restored" : "Item Archived", "Changed status of item ID: $id");
  }

  Future<void> updateProductStatus(String id, bool status) async {
    await _prodsRef.doc(id).update({'isActive': status});
    await logActivity(status ? "Product Restored" : "Product Archived", "Changed status of product ID: $id");
  }

  Future<void> updateComponentQuantity(String componentId, int delta) async {
    if (!user.canManageStock) return;
    final docRef = _compsRef.doc(componentId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      final currentQty = (snapshot.data() as Map<String, dynamic>)['quantity'] ?? 0;
      int newQty = currentQty + delta;
      if (newQty < 0) newQty = 0;
      transaction.update(docRef, {'quantity': newQty});
    });
    await logActivity(delta > 0 ? "Stock Added" : "Stock Removed", "Adjusted Qty by $delta");
  }

  Future<void> addComponent(String name, int initialQuantity, int minStock, double cost, {String barcode = ''}) async {
    if (!user.canManageStock) throw Exception("Access Denied");
    final docRef = _compsRef.doc();
    final newComp = Component(id: docRef.id, name: name, quantity: initialQuantity, minStock: minStock, costPerUnit: cost, barcode: barcode);
    await docRef.set(newComp.toJson());

    final statsRef = _db.collection('companies').doc(user.companyId).collection('stats').doc('inventory');
    await statsRef.set({
       'totalItems': FieldValue.increment(1),
       'totalValue': FieldValue.increment(cost * initialQuantity)
    }, SetOptions(merge: true));

    await logActivity("Created Item", "Created '$name'");
  }

  Future<void> removeComponent(String componentId) async {
    if (!user.canManageStock) throw Exception("Access Denied");
    await _compsRef.doc(componentId).delete();
    await logActivity("Deleted Item", "Deleted component ID: $componentId");
  }

  Future<void> addProduct(String name, Map<String, int> bom, double price) async {
    if (!user.canManageStock) throw Exception("Access Denied");
    final docRef = _prodsRef.doc();
    final newProd = Product(id: docRef.id, name: name, componentsNeeded: bom, sellingPrice: price);
    await docRef.set(newProd.toJson());
    await logActivity("Created Product", "Defined '$name'");
  }

  Future<void> removeProduct(String productId) async {
    if (!user.canManageStock) throw Exception("Access Denied");
    await _prodsRef.doc(productId).delete();
    await logActivity("Deleted Product", "Deleted definition ID: $productId");
  }

  Future<void> updateProductPrice(String productId, double newPrice) async {
    if (!user.canManageStock) return;
    await _prodsRef.doc(productId).update({'sellingPrice': newPrice});
  }

  Future<void> updateComponentThreshold(String componentId, int newMin) async {
    if (!user.canManageStock) return;
    await _compsRef.doc(componentId).update({'minStock': newMin});
  }

  Future<void> updateComponentCost(String componentId, double newCost) async {
    if (!user.canManageStock) return;
    await _compsRef.doc(componentId).update({'costPerUnit': newCost});
  }

  Future<bool> batchProduce(String productId, int totalRun, int scrapCount) async {
    int goodCount = totalRun - scrapCount;
    if (goodCount < 0) goodCount = 0;

    try {
      final product = products.firstWhere((p) => p.id == productId);

      for (var entry in product.componentsNeeded.entries) {
        final comp = getComponent(entry.key);
        if (comp == null || comp.quantity < (entry.value * totalRun)) {
          return false;
        }
      }

      final batch = _db.batch();

      for (var entry in product.componentsNeeded.entries) {
        final compRef = _compsRef.doc(entry.key);
        batch.update(compRef, {'quantity': FieldValue.increment(-(entry.value * totalRun))});
      }

      final productRef = _prodsRef.doc(productId);
      batch.update(productRef, {
        'producedCount': FieldValue.increment(goodCount),
        'lastBatchAmount': goodCount
      });

      final existingStockMatch = components.where(
        (c) => c.name.toLowerCase() == product.name.toLowerCase()
      );

      if (existingStockMatch.isNotEmpty) {
        final stockRef = _compsRef.doc(existingStockMatch.first.id);
        batch.update(stockRef, {'quantity': FieldValue.increment(goodCount)});
      } else {
        final newStockRef = _compsRef.doc();
        batch.set(newStockRef, {
          'name': product.name,
          'quantity': goodCount,
          'minStock': 10,
          'costPerUnit': product.getProductionCost(components),
          'isActive': true,
          'barcode': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      await logActivity("Production Run", "Produced $goodCount ${product.name} (Scrapped $scrapCount)");

      return true;
    } catch (e) {
      print("Production Error: $e");
      return false;
    }
  }

  Future<void> batchAdjustDown(String productId, int amount) async {
    if (!user.canManageStock) return;

    try {
      final product = products.firstWhere((p) => p.id == productId);

      final matchingStock = components.firstWhere(
        (c) => c.name.toLowerCase() == product.name.toLowerCase(),
        orElse: () => throw Exception("Product not found in Stock list"),
      );

      final batch = _db.batch();
      final companyRef = _db.collection('companies').doc(user.companyId);

      final stockRef = _compsRef.doc(matchingStock.id);
      batch.update(stockRef, {'quantity': FieldValue.increment(-amount)});

      final salesRef = companyRef.collection('sales').doc();
      batch.set(salesRef, {
        'date': FieldValue.serverTimestamp(),
        'productName': product.name,
        'quantity': amount,
        'unitPrice': product.sellingPrice,
        'unitCost': matchingStock.costPerUnit,
        'totalRevenue': product.sellingPrice * amount,
        'totalProfit': (product.sellingPrice - matchingStock.costPerUnit) * amount,
        'soldBy': user.email,
      });

      await batch.commit();
      await logActivity("Sale Recorded", "Shipped $amount ${product.name}");
    } catch (e) {
      print("Shipping Error: $e");
    }
  }

  Future<bool> undoProduce(String productId) async {
    try {
      final product = products.firstWhere((p) => p.id == productId);

      final productSnap = await _prodsRef.doc(productId).get();
      final data = productSnap.data() as Map<String, dynamic>;
      final int amountToUndo = data['lastBatchAmount'] ?? 0;

      if (amountToUndo <= 0) return false;

      final batch = _db.batch();

      for (final entry in product.componentsNeeded.entries) {
        final compRef = _compsRef.doc(entry.key);
        batch.update(compRef, {'quantity': FieldValue.increment(entry.value * amountToUndo)});
      }

      batch.update(_prodsRef.doc(productId), {
        'producedCount': FieldValue.increment(-amountToUndo),
        'lastBatchAmount': 0
      });

      final existingStockMatch = components.where(
        (c) => c.name.toLowerCase() == product.name.toLowerCase()
      );

      if (existingStockMatch.isNotEmpty) {
        final stockRef = _compsRef.doc(existingStockMatch.first.id);
        batch.update(stockRef, {'quantity': FieldValue.increment(-amountToUndo)});
      }

      await batch.commit();
      await logActivity("Undo Production", "Reversed production of $amountToUndo ${product.name}");

      return true;
    } catch (e) {
      print("Undo Error: $e");
      return false;
    }
  }

  // --- HELPERS ---

  Component? getComponent(String id) {
    try { return components.firstWhere((c) => c.id == id); } catch (_) { return null; }
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (index) => chars[Random().nextInt(chars.length)]).join();
  }

  Future<String> getJoinCode() async {
    var doc = await _db.collection('companies').doc(user.companyId).get();
    return doc.data()?['joinCode'] ?? "";
  }

  Future<String> resetJoinCode() async {
    String newCode = _generateCode();
    await _db.collection('companies').doc(user.companyId).update({'joinCode': newCode});
    return newCode;
  }

  Future<void> logActivity(String action, String details) async {
    String firstName = user.displayName.split(' ')[0];
    String actorDisplay = "$firstName (${user.uid.substring(0, 4)})";
    await _logsRef.add({
      'timestamp': FieldValue.serverTimestamp(),
      'actorEmail': actorDisplay,
      'action': action,
      'details': details,
    });
  }

  Future<void> createPurchaseOrder(String supplier, List<POItem> items) async {
    double totalCost = items.fold(0.0, (sum, i) => sum + (i.quantity * i.costPerUnit));
    await _db.collection('companies').doc(user.companyId).collection('purchase_orders').add({
      'supplierName': supplier,
      'items': items.map((i) => i.toMap()).toList(),
      'status': 'ordered',
      'orderDate': FieldValue.serverTimestamp(),
      'totalCost': totalCost,
    });
    await logActivity("Created PO", "Ordered from $supplier");
  }

  Future<void> receivePurchaseOrder(PurchaseOrder po) async {
    if (po.status == POStatus.received) return;
    await _db.runTransaction((transaction) async {
      for (var item in po.items) {
        transaction.update(_compsRef.doc(item.componentId), {'quantity': FieldValue.increment(item.quantity)});
      }
      transaction.update(_db.collection('companies').doc(user.companyId).collection('purchase_orders').doc(po.id), {'status': 'received'});
    });
    await logActivity("Received Stock", "Received shipment from ${po.supplierName}");
  }

  Future<void> debugTogglePro() async {
    await _db.collection('companies').doc(user.companyId).update({'isPro': !isCurrentCompanyPro});
  }

  // --- TASK DELEGATION LOGIC ---

  CollectionReference get _tasksRef =>
      _db.collection('companies').doc(user.companyId).collection('tasks');

  Future<List<Map<String, String>>> getAssignableUsers() async {
    try {
      print("DEBUG: Fetching users for company: ${user.companyId}");

      final snapshot = await _db.collection('users')
          .where('connectedCompanyIds', arrayContains: user.companyId)
          .get();

      print("DEBUG: Found ${snapshot.docs.length} user documents.");

      final users = snapshot.docs.map((doc) {
        final data = doc.data();
        String name = data['displayName']?.toString() ?? '';
        if (name.isEmpty) name = data['email']?.toString() ?? 'Unknown Staff';

        return {
          'uid': doc.id,
          'name': name,
        };
      }).toList();

      return users;
    } catch (e) {
      print("DEBUG: Error fetching team members: $e");
      return [];
    }
  }

  Future<void> addTask(String title, String desc, String targetUserId, String targetName, DateTime due, String priority) async {
    if (!user.canManageTeam) throw Exception("Only Managers can assign tasks.");

    await _tasksRef.add({
      'title': title,
      'description': desc,
      'assignedToId': targetUserId,
      'assignedToName': targetName,
      'createdBy': user.displayName,
      'dueDate': Timestamp.fromDate(due),
      'isCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'priority': priority,
    });

    await logActivity("Task Assigned", "Assigned '$title' ($priority) to $targetName");
  }

  Future<void> toggleTaskStatus(String taskId, bool currentStatus) async {
    await _tasksRef.doc(taskId).update({'isCompleted': !currentStatus});
  }

  Future<void> deleteTask(String taskId) async {
    if (!user.canManageTeam) return;
    await _tasksRef.doc(taskId).delete();
  }

  Future<void> updateTaskStatus(String taskId, bool isDone, String note) async {
    await _tasksRef.doc(taskId).update({
      'isCompleted': isDone,
      'completionNote': note,
      'completedBy': user.displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await logActivity(
      isDone ? "Task Completed" : "Task Re-opened",
      isDone ? "Completed by ${user.displayName}" : "Marked incomplete by ${user.displayName}"
    );
  }
}
