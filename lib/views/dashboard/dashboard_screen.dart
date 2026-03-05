import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../../constants.dart';
import '../../models/models.dart';
import '../../controllers/inventory_controller.dart';
import '../../services/pdf_service.dart';
import '../reports/reports_screen.dart';
import '../subscription/subscription_screen.dart';
import '../settings/user_options_screen.dart';
class InventoryDashboard extends StatefulWidget {
  const InventoryDashboard({super.key});

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard> {
  InventoryManager? manager;
  UserProfile? _latestProfile; // <--- ADD THIS LINE
  bool isLoading = true;
  int _selectedIndex = 0;

  // --- SEARCH & SORT STATE ---
  String _searchQuery = "";
  String _sortBy = "name"; // Options: name, quantity_asc, quantity_desc, value_high
  bool _showArchived = false; // Toggle to hide/show archived items

  bool get _isPro => manager?.user.isPro ?? false;

  final PageController _pageController = PageController();
  
  StreamSubscription? _userProfileSubscription; 

  @override
  void initState() {
    super.initState();
    _setupUserListener(); 
  }

  @override
  void dispose() {
    _userProfileSubscription?.cancel();
    manager?.dispose();
    super.dispose();
  }

  void _showEnterpriseContactDialog(String feature) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.business, color: kPrimaryColor), SizedBox(width: 8), Text("Enterprise Limit Reached")]),
        content: Text("Wow! You have reached the maximum $feature limit for the Pro Plan.\n\nTo manage this volume (10,000+ items), please contact our sales team for a dedicated Enterprise Server."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
          ElevatedButton(
            onPressed: () {
               // Launch email or web link here
               Navigator.pop(ctx);
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Support request sent!")));
            }, 
            child: const Text("Contact Sales")
          )
        ],
      )
    );
  }

  // --- TASK UI WIDGETS ---

  Widget _buildTaskList() {
    if (manager == null) return const SizedBox.shrink();
    
    // 1. Get current user status
    final bool isManager = manager!.user.canManageTeam;
    final String myId = manager!.user.uid;

    print("DEBUG: Building Task List. User ID: $myId, Is Manager? $isManager");

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5')
          .collection('companies')
          .doc(manager!.user.companyId)
          .collection('tasks')
          // ðŸ‘‡ TEMPORARILY REMOVED ORDERING TO RULE OUT INDEX ISSUES
           .orderBy('isCompleted', descending: false) 
           .orderBy('dueDate', descending: false)     
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
           print("DEBUG: Stream Error: ${snapshot.error}");
           return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        var docs = snapshot.data!.docs;
        print("DEBUG: Fetched ${docs.length} tasks from database.");

        // ðŸ‘‡ DEBUG: Print the first task to see who it is assigned to
        if (docs.isNotEmpty) {
           final firstData = docs.first.data() as Map<String, dynamic>;
           print("DEBUG: First Task Assigned To: ${firstData['assignedToId']}");
        }

        // ðŸ‘‡ TEMPORARILY DISABLED FILTER TO SHOW ALL TASKS
        // if (!isManager) {
        //   docs = docs.where((d) => d['assignedToId'] == myId).toList();
        //   print("DEBUG: Filtered down to ${docs.length} tasks for this user.");
        // }

        if (docs.isEmpty) {
          return _buildEmptyState(Icons.assignment_turned_in, "No tasks found (List is empty).");
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_,__) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final task = Task.fromMap(docs[index].id, data);
            
            final bool isOverdue = !task.isCompleted && DateTime.now().isAfter(task.dueDate);
            final bool isMine = task.assignedToId == myId;

            // 1. Determine Color
            Color priorityColor = Colors.grey;
            if (task.priority == 'High') priorityColor = Colors.deepOrange;
            else if (task.priority == 'Normal') priorityColor = const Color.fromARGB(255, 247, 210, 0);
            else if (task.priority == 'Low') priorityColor = Colors.blue;

            // ðŸ‘‡ THIS IS THE NEW CARD BLOCK ðŸ‘‡
            return Card(
              elevation: 2,
              clipBehavior: Clip.antiAlias, 
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isOverdue ? const BorderSide(color: Colors.red, width: 1) : BorderSide.none
              ),
              child: IntrinsicHeight( 
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // THE COLORED STRIP
                    Container(width: 6, color: priorityColor),
                    
                    // THE CONTENT
                    // ... inside the Row ...
                    Expanded(
                      child: InkWell(
                        onTap: () => _showTaskActionDialog(task, isManager || isMine),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Icon(
                                task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: task.isCompleted ? Colors.green : Colors.grey,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.title, 
                                      style: TextStyle(
                                        decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                                        fontWeight: FontWeight.bold,
                                        color: task.isCompleted ? Colors.grey : null
                                      )
                                    ),
                                    
                                    // 1. Description
                                    if(task.description.isNotEmpty)
                                      Text(task.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    
                                    // 2. Completion Note
                                    if (task.completionNote.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text("ðŸ“ ${task.completionNote}", style: TextStyle(fontSize: 12, color: Colors.blue[700], fontStyle: FontStyle.italic)),
                                      ),

                                    // ðŸ‘‡ UPDATED STATUS BOX
                                    if (task.completedBy.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          // Green background if done, Orange background if re-opened
                                          color: (task.isCompleted ? Colors.green : Colors.orange).withOpacity(0.1), 
                                          borderRadius: BorderRadius.circular(8)
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              task.isCompleted ? Icons.check_circle : Icons.warning_amber, 
                                              size: 16, 
                                              color: task.isCompleted ? Colors.green : Colors.orange[800]
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                task.isCompleted 
                                                  ? "Completed by: ${task.completedBy}" 
                                                  : "Marked incomplete by: ${task.completedBy}",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold, 
                                                  color: task.isCompleted ? Colors.green : Colors.orange[800]
                                                )
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    ],
                                    
                                    const Divider(height: 32),
                                  ],
                                ),
                              ),
                              // ... (Date Column remains here) ...
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  CircleAvatar(
                                    radius: 10, 
                                    backgroundColor: Colors.grey[200], 
                                    child: Text(task.assignedToName.isNotEmpty ? task.assignedToName[0].toUpperCase() : "?", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                                  ),
                                  const SizedBox(height: 4),
                                  Text("${task.dueDate.month}/${task.dueDate.day}", style: TextStyle(fontSize: 11, color: isOverdue ? Colors.red : Colors.grey)),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddTaskDialog() async {
    // 1. Check Permissions
    if (manager == null || !manager!.user.canManageTeam) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Only Managers can assign tasks.")));
      return;
    }

    // 2. Fetch Users
    List<Map<String, String>> teamMembers = [];
    try {
      teamMembers = await manager!.getAssignableUsers();
    } catch (e) {
      print(e);
    }

    if (teamMembers.isEmpty) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No team members found.")));
      return;
    }

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? selectedUserId;
    String selectedUserName = "";
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1)); // Default tomorrow
    String selectedPriority = 'Normal'; 

    // 3. Show Dialog
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Assign New Task"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: "Task Title", hintText: "e.g. Count Stock"),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                
                // ðŸ‘‡ FIX 1: Added isExpanded to Priority Dropdown
                DropdownButtonFormField<String>(
                  value: selectedPriority,
                  isExpanded: true, // <--- Prevents Overflow
                  decoration: const InputDecoration(labelText: "Priority Level", prefixIcon: Icon(Icons.flag)),
                  items: const [
                    DropdownMenuItem(value: 'High', child: Text("ðŸŸ  High Priority", overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Normal', child: Text("ðŸŸ¡ Normal Priority", overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Low', child: Text("ðŸ”µ Low Priority", overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) => setDialogState(() => selectedPriority = val!),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: "Description (Optional)"),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                
                // ðŸ‘‡ FIX 2: Added isExpanded to Assignee Dropdown
                DropdownButtonFormField<String>(
                  isExpanded: true, // <--- Prevents Overflow
                  decoration: const InputDecoration(labelText: "Assign To", prefixIcon: Icon(Icons.person_outline)),
                  items: teamMembers.map((m) {
                    return DropdownMenuItem(
                      value: m['uid'],
                      child: Text(m['name']!, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) {
                    selectedUserId = val;
                    selectedUserName = teamMembers.firstWhere((m) => m['uid'] == val)['name']!;
                  },
                ),
                const SizedBox(height: 16),

                // Date Picker Row
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text("Due: ${selectedDate.month}/${selectedDate.day}"),
                    const Spacer(),
                    TextButton(
                      child: const Text("Change"),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                    )
                  ],
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.isNotEmpty && selectedUserId != null) {
                  await manager!.addTask(
                    titleCtrl.text.trim(), 
                    descCtrl.text.trim(), 
                    selectedUserId!, 
                    selectedUserName, 
                    selectedDate,
                    selectedPriority 
                  );
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Task Assigned!")));
                  }
                }
              },
              child: const Text("Assign Task"),
            )
          ],
        ),
      ),
    );
  }

  void _showTaskActionDialog(Task task, bool canEdit) {
    // 1. Define permissions
    final bool isOwner = manager?.user.isOwner ?? false;
    final noteCtrl = TextEditingController(text: task.completionNote);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(task.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Task Details
              const Text("Description:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text(task.description.isNotEmpty ? task.description : "No description provided.", style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text("Assigned to: ${task.assignedToName}", style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text("Due: ${task.dueDate.month}/${task.dueDate.day}", style: const TextStyle(fontSize: 12)),
                ],
              ),
              const Divider(height: 32),

              // 2. Action Section
              if (canEdit) ...[
                const Text("Update Status:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: "Completion Notes / Issues",
                    hintText: "e.g. 'Done, keys at desk' or 'Missing parts'",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // ðŸ‘‡ UPDATED INCOMPLETE BUTTON
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await manager!.updateTaskStatus(task.id, false, noteCtrl.text.trim());
                          if (mounted) Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[700], // Yellowish Orange
                          foregroundColor: Colors.white,      // White Text
                          elevation: 0,
                        ),
                        child: const Text("Mark Incomplete", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // COMPLETE BUTTON
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await manager!.updateTaskStatus(task.id, true, noteCtrl.text.trim());
                          if (mounted) Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green, 
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        child: const Text("Mark Complete", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                if (isOwner)
                   Center(
                     child: Padding(
                       padding: const EdgeInsets.only(top: 12.0),
                       child: TextButton.icon(
                         icon: const Icon(Icons.delete, size: 16, color: Colors.grey),
                         label: const Text("Delete Task", style: TextStyle(color: Colors.grey)),
                         onPressed: () {
                           Navigator.pop(ctx);
                           manager!.deleteTask(task.id);
                         },
                       ),
                     ),
                   )
              ] else 
                // Read-only view
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8)
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Latest Note:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(task.completionNote.isNotEmpty ? task.completionNote : "No notes yet."),
                      const SizedBox(height: 8),
                      Text("Status: ${task.isCompleted ? 'COMPLETE' : 'PENDING'}", style: TextStyle(fontWeight: FontWeight.bold, color: task.isCompleted ? Colors.green : Colors.orange)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreatePODialog() {
    // Basic controllers
    final supplierCtrl = TextEditingController();
    
    // We need a temp list to hold items we are adding to the cart
    List<POItem> cart = [];
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("New Purchase Order"),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: supplierCtrl, decoration: const InputDecoration(labelText: "Supplier Name", hintText: "e.g. Acme Corp")),
                const SizedBox(height: 16),
                const Text("Items to Order:", style: TextStyle(fontWeight: FontWeight.bold)),
                
                // THE CART LIST
                ...cart.map((item) => ListTile(
                  dense: true,
                  title: Text(item.name),
                  subtitle: Text("${item.quantity} x \$${item.costPerUnit}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    onPressed: () => setDialogState(() => cart.remove(item)),
                  ),
                )),

                // ADD ITEM BUTTON
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text("Add Item to Order"),
                  onPressed: () async {
                    // Show a mini dialog to pick an item from your Inventory list
                    // This returns a POItem or null
                    final POItem? result = await _showItemPicker(ctx); 
                    if (result != null) {
                      setDialogState(() => cart.add(result));
                    }
                  },
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                if (cart.isNotEmpty && supplierCtrl.text.isNotEmpty) {
                  await manager!.createPurchaseOrder(supplierCtrl.text, cart);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PO Created!")));
                }
              }, 
              child: const Text("Submit Order")
            )
          ],
        ),
      ),
    );
  }

  Future<POItem?> _showItemPicker(BuildContext context) async {
    // 1. Get available items
    final comps = manager?.components ?? [];
    if (comps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No items defined in Stock yet."))
      );
      return null;
    }

    // 2. Setup Controllers
    final qtyCtrl = TextEditingController(text: '10');
    final costCtrl = TextEditingController();
    
    String? selectedId;
    String selectedName = '';

    // 3. Show the Dialog
    return showDialog<POItem>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Select Item to Order"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Item Dropdown
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    hint: const Text("Choose Item"),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      border: OutlineInputBorder(),
                    ),
                    items: comps.map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (val) {
                      final c = comps.firstWhere((e) => e.id == val);
                      setState(() {
                        selectedId = val;
                        selectedName = c.name;
                        // Auto-fill the cost with the current cost basis
                        costCtrl.text = c.costPerUnit.toString();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Qty & Cost Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: "Quantity"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: costCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(       // <--- "const" removed
                            labelText: "Unit Cost (\$)",
                            prefixText: "\$ ",
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx), 
                  child: const Text("Cancel")
                ),
                ElevatedButton(
                  onPressed: () {
                    // Validation
                    if (selectedId != null && qtyCtrl.text.isNotEmpty) {
                      Navigator.pop(ctx, POItem(
                        componentId: selectedId!,
                        name: selectedName,
                        quantity: int.tryParse(qtyCtrl.text) ?? 0,
                        costPerUnit: double.tryParse(costCtrl.text) ?? 0.0,
                      ));
                    }
                  },
                  child: const Text("Add to Order"),
                )
              ],
            );
          }
        );
      }
    );
  }

  Widget _buildPurchaseOrderList() {
    if (manager == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5')
          .collection('companies')
          .doc(manager!.user.companyId)
          .collection('purchase_orders')
          .orderBy('orderDate', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Error loading orders"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState(Icons.shopping_cart_outlined, "No Purchase Orders yet.\nCreate one to track incoming stock.");

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            // Helper to safely parse the PO from Firestore data
            final po = PurchaseOrder.fromMap(docs[index].id, data);
            
            final bool isReceived = po.status == POStatus.received;
            final Color statusColor = isReceived ? Colors.green : Colors.orange;

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isReceived ? Colors.transparent : Colors.orange.withOpacity(0.5))
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(po.supplierName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(
                              "${po.items.length} Items â€¢ \$${po.totalCost.toStringAsFixed(2)}", 
                              style: const TextStyle(color: Colors.grey, fontSize: 12)
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusColor)
                          ),
                          child: Text(
                            po.status.name.toUpperCase(),
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)
                          ),
                        )
                      ],
                    ),
                    const Divider(height: 24),
                    // Item Preview (First 3 items)
                    ...po.items.take(3).map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("â€¢ ${item.name}", style: const TextStyle(fontSize: 13)),
                          Text("x${item.quantity}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    )),
                    if (po.items.length > 3) 
                      Text("+ ${po.items.length - 3} more...", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    
                    const SizedBox(height: 16),
                    
                    // ACTION BUTTONS
                    if (!isReceived)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            // CONFIRM RECEIVE
                            final confirm = await showDialog<bool>(
                              context: context, 
                              builder: (ctx) => AlertDialog(
                                title: const Text("Receive Shipment?"),
                                content: const Text("This will add stock to inventory and recalculate average costs. This cannot be undone."),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                                  ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Receive All")),
                                ],
                              )
                            );

                            if (confirm == true && manager != null) {
                              await manager!.receivePurchaseOrder(po);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stock Updated Successfully!")));
                              }
                            }
                          }, 
                          icon: const Icon(Icons.inventory), 
                          label: const Text("RECEIVE ITEMS"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kSecondaryColor,
                            foregroundColor: Colors.white
                          ),
                        ),
                      )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _importCSV() async {
    try {
      // 1. Pick the file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) return; 

      // 2. Read the file
      File file = File(result.files.single.path!);
      String csvString = await file.readAsString();
      List<List<dynamic>> rows = const CsvToListConverter().convert(csvString);

      if (rows.isEmpty) throw Exception("File is empty.");

      // 3. Find Columns dynamically
      final headers = rows[0].map((e) => e.toString().toLowerCase().trim()).toList();
      
      int nameIdx = headers.indexWhere((h) => h.contains('name') || h.contains('item'));
      int qtyIdx = headers.indexWhere((h) => h.contains('qty') || h.contains('quantity'));
      int costIdx = headers.indexWhere((h) => h.contains('cost') || h.contains('price'));
      int minIdx = headers.indexWhere((h) => h.contains('min') || h.contains('limit'));

      if (nameIdx == -1) throw Exception("Could not find 'Name' column.");

      int added = 0;
      int updated = 0;
      int skipped = 0;

      // 4. Loop through rows (Start at 1 to skip headers)
      for (int i = 1; i < rows.length; i++) {
        // ðŸ‘‡ SAFETY BUBBLE: If this specific row fails, catch the error and continue to the next
        try {
          final row = rows[i];
          if (row.length <= nameIdx) continue;

          String name = row[nameIdx].toString().trim();
          if (name.isEmpty) continue;

          // --- CLEAN DATA PARSING ---
          // 1. Quantity: Remove commas (e.g. "1,000" -> "1000")
          String qtyRaw = (qtyIdx != -1 && row.length > qtyIdx) ? row[qtyIdx].toString() : '0';
          int qty = int.tryParse(qtyRaw.replaceAll(',', '').replaceAll('.', '')) ?? 0;
          
          // 2. Cost: Remove '$' and ',' (e.g. "$1,200.50" -> "1200.50")
          String costRaw = (costIdx != -1 && row.length > costIdx) ? row[costIdx].toString() : '0';
          costRaw = costRaw.replaceAll(RegExp(r'[^0-9.]'), ''); 
          double cost = double.tryParse(costRaw) ?? 0.0;
          
          // 3. Min Stock
          String minRaw = (minIdx != -1 && row.length > minIdx) ? row[minIdx].toString() : '10';
          int minStock = int.tryParse(minRaw.replaceAll(',', '').replaceAll('.', '')) ?? 10;

          if (manager != null) {
            // --- UPSERT LOGIC ---
            // Check if this item name ALREADY exists in our list
            final existingItem = manager!.components.firstWhere(
              (c) => c.name.toLowerCase() == name.toLowerCase(),
              orElse: () => Component(id: '', name: '', quantity: 0, minStock: 0, costPerUnit: 0),
            );

            if (existingItem.id.isNotEmpty) {
              // âœ… FOUND IT! Update the existing one (Keeps Product links alive)
              // Note: We overwrite the cost and minStock with the CSV values
              await manager!.updateComponentQuantity(existingItem.id, qty); 
              // If you want the CSV to update cost/min as well, you'd add those manager methods here.
              // For now, we mainly care about Quantity not breaking things.
              updated++;
            } else {
              // ðŸ†• NEW ITEM! Create it.
              await manager!.addComponent(name, qty, minStock, cost);
              added++;
            }
          }
        } catch (e) {
          print("âš ï¸ Skipped Row $i ($e)");
          skipped++;
        }
      }

      if (!mounted) return;
      setState(() {}); 

      // 5. Show Summary
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Import Complete: $added new, $updated updated. ($skipped skipped)"), 
          backgroundColor: skipped > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 4),
        )
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("File Error: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _acceptInvite(String inviteId, Map<String, dynamic> data) async {
    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
      final newCompanyId = data['companyId'];
      final newRole = data['role'];
      final newName = data['companyName'];
      final senderEmail = data['invitedByEmail']; 

      final newMembership = {
        'companyId': newCompanyId,
        'companyName': newName,
        'role': newRole,
      };

      final userRef = db.collection('users').doc(manager!.user.uid);

      await db.runTransaction((transaction) async {
        // 1. Add Membership Card AND 'connectedCompanyIds' tag (The Fix)
        transaction.update(userRef, {
          'memberships': FieldValue.arrayUnion([newMembership]),
          'connectedCompanyIds': FieldValue.arrayUnion([newCompanyId]),
        });
        
        // 2. Delete the Invite ticket
        transaction.delete(db.collection('invitations').doc(inviteId));

        // 3. Notify the Sender ("User X joined your team")
        if (senderEmail != null) {
          final notifRef = db.collection('notifications').doc();
          transaction.set(notifRef, {
            'targetEmail': senderEmail,
            'title': 'Invite Accepted',
            'message': '${manager!.user.displayName} has joined $newName as a ${_roleToDisplay(newRole)}.',
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'info',
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Joined $newName!"),
            action: SnackBarAction(
              label: "SWITCH NOW",
              onPressed: () {
                manager!.switchOrganization(CompanyMembership(
                  companyId: newCompanyId, 
                  companyName: newName, 
                  role: newRole
                ));
              },
            ),
          )
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error joining: $e"), backgroundColor: Colors.red));
    }
  }

  void _showNotificationsDialog(List<Map<String, dynamic>> items) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Notifications"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_,__) => const Divider(),
            itemBuilder: (context, index) {
              final item = items[index];
              final DocumentSnapshot doc = item['doc'];
              final bool isInvite = item['isInvite'];
              final data = doc.data() as Map<String, dynamic>;

              if (isInvite) {
                // --- NEW LOGIC START ---
                final companyName = data['companyName'] ?? 'Unknown Org';
                final inviter = data['invitedBy'] ?? 'Someone';
                
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: kPrimaryColor.withOpacity(0.1),
                    child: const Icon(Icons.mail_outline, color: kPrimaryColor, size: 20),
                  ),
                  title: Text("Invite: $companyName", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("From $inviter\nTap to view details"),
                  isThreeLine: true,
                  // 1. THIS LINE FIXES THE WARNING:
                  onTap: () {
                    Navigator.pop(ctx); // Close the notification list first
                    _showProfessionalInviteDialog(doc.id, data); // Open the new dialog
                  },
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                );
                // --- NEW LOGIC END ---
              } else {
                // (Keep existing logic for normal alerts)
                final title = data['title'] ?? 'Alert';
                final message = data['message'] ?? '';
                
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(Icons.check, color: Colors.white, size: 20),
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(message),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey),
                    onPressed: () async {
                      await doc.reference.delete();
                      if (mounted && items.length == 1) Navigator.pop(ctx);
                    },
                  ),
                );
              }
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }

  Widget _buildNotificationBell() {
    if (manager == null) return const SizedBox.shrink();
    
    final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
    final myEmail = manager!.user.email;

    // 1. Listen for Invites (Actions)
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('invitations').where('targetEmail', isEqualTo: myEmail).snapshots(),
      builder: (context, inviteSnap) {
        
        // Safety: If permissions fail temporarily, show disabled icon instead of crashing
        if (inviteSnap.hasError) {
          return const Icon(Icons.notifications_off, color: Colors.grey, size: 20);
        }

        // 2. Listen for General Notifications (Info - "User Joined")
        return StreamBuilder<QuerySnapshot>(
          stream: db.collection('notifications').where('targetEmail', isEqualTo: myEmail).snapshots(),
          builder: (context, notifSnap) {
            
            if (notifSnap.hasError) return const SizedBox.shrink();
            
            final inviteCount = inviteSnap.hasData ? inviteSnap.data!.docs.length : 0;
            final notifCount = notifSnap.hasData ? notifSnap.data!.docs.length : 0;
            final totalCount = inviteCount + notifCount;

            // Merge data for the popup list
            final allDocs = [
               if (inviteSnap.hasData) ...inviteSnap.data!.docs.map((d) => {'doc': d, 'isInvite': true}),
               if (notifSnap.hasData) ...notifSnap.data!.docs.map((d) => {'doc': d, 'isInvite': false}),
            ];

            return Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  tooltip: "Notifications",
                  onPressed: () {
                    if (totalCount > 0) {
                      _showNotificationsDialog(allDocs);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No new notifications.")));
                    }
                  },
                ),
                if (totalCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$totalCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
              ],
            );
          }
        );
      },
    );
  }

  void _setupUserListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    // ðŸ‘‡ðŸ‘‡ðŸ‘‡ WRAP THIS LINE TOO ðŸ‘‡ðŸ‘‡ðŸ‘‡
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
       Purchases.logIn(firebaseUser.uid); 
    }

    final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
    
    _userProfileSubscription = db.collection('users').doc(firebaseUser.uid).snapshots().listen((userDoc) async {
      if (!userDoc.exists) return; 

      var userData = userDoc.data()!;
      
      // Auto-heal logic
      if (userData['connectedCompanyIds'] == null) {
         List<dynamic> mems = userData['memberships'] ?? [];
         Set<String> ids = mems.map((m) => m['companyId'].toString()).toSet();
         if (userData['companyId'] != null) ids.add(userData['companyId']);
         await db.collection('users').doc(firebaseUser.uid).update({'connectedCompanyIds': ids.toList()});
         return; 
      }

      UserProfile newProfile = UserProfile.fromMap(firebaseUser.uid, userData);

      // --- CRITICAL FIX: FETCH DATE FROM COMPANY ---
      // We ignore the User's creation date. We want the COMPANY'S creation date.
      String currentCompanyId = userData['companyId'] ?? '';
      
      if (currentCompanyId.isNotEmpty) {
        try {
          // Fetch the Company Document
          final companySnap = await db.collection('companies').doc(currentCompanyId).get();
          final companyData = companySnap.data();

          if (companyData != null) {
             // Look for 'created_at' in the COMPANY document
             final rawDate = companyData['created_at'] ?? companyData['createdAt'];
             
             if (rawDate != null) {
                if (rawDate is Timestamp) {
                   newProfile = newProfile.copyWith(createdAt: rawDate.toDate());
                } else if (rawDate is String) {
                   // Handles your manual edits in the Company collection
                   newProfile = newProfile.copyWith(createdAt: DateTime.tryParse(rawDate));
                }
             }
          }
        } catch (e) {
          print("Error fetching company date: $e");
        }
      }
      // ---------------------------------------------

      _latestProfile = newProfile; 

      bool shouldRefreshManager = false;

      if (manager == null) {
        shouldRefreshManager = true;
      } else {
        if (manager!.user.companyId != newProfile.companyId) shouldRefreshManager = true;
        if (manager!.user.role != newProfile.role) shouldRefreshManager = true;
        if (manager!.user.isPro != newProfile.isPro) shouldRefreshManager = true;
        // Also refresh if the date changed
        if (manager!.user.createdAt != newProfile.createdAt) shouldRefreshManager = true;
      }

      if (shouldRefreshManager) {
        manager?.dispose();
        
        if (newProfile.companyId.isNotEmpty) {
           manager = InventoryManager(user: newProfile);
           manager!.listen(() {
             if (mounted) setState(() => isLoading = false);
           });
        } else {
           manager = null;
        }

        _selectedIndex = 0; 
        if (mounted) setState(() => isLoading = false);
      } else {
        if (mounted) setState(() {});
      }
      
    }, onError: (e) {
       print("User Listener Error: $e");
       if (mounted) setState(() => isLoading = false);
    });
  }

  Future<void> _refresh() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() {});
  }

  String _roleToDisplay(String role) {
    switch (role) {
      case 'owner': return 'Business Owner';
      case 'business_admin': return 'Administrator';
      case 'manager': return 'Manager';
      case 'user': return 'Staff';
      case 'inactive': return 'Deactivated';
      default: return 'Unknown';
    }
  }

  // --- LIMIT LOGIC (UPDATED) ---
  bool _checkLimit(int currentCount, int limitTypeFree, String featureName) {
    // 1. CHECK ORGANIZATION STATUS
    final bool isProOrg = (manager?.isCurrentCompanyPro ?? false);

    // 2. Fallback: Check individual user flags
    final bool isProUser = (manager?.user.isPro ?? false) || (_latestProfile?.isPro ?? false);

    final bool hasProAccess = isProOrg || isProUser;

    // 3. Check Trial Logic
    bool trialIsActive = false;
    final DateTime? created = _latestProfile?.createdAt;
    
    if (created != null) {
      final trialExpiry = created.add(const Duration(days: 7));
      if (DateTime.now().isBefore(trialExpiry)) trialIsActive = true; 
    } else {
      // ðŸ‘‡ THIS WAS MISSING
      // If date is missing (loading or new account glitch), default to TRIAL mode to be safe.
      // This matches your UI logic which shows "PRO TRIAL" when date is null.
      trialIsActive = true; 
    }

    // --- DECISION TIME ---

    

    // A. If Pro OR Trial -> ALLOW (up to safety cap)
    if (hasProAccess || trialIsActive) {
      if (currentCount >= kProMaxStock) {
        _showEnterpriseContactDialog(featureName);
        return false;
      }
      return true; 
    }

    // B. If Free Plan -> BLOCK if limit reached
    if (currentCount >= limitTypeFree) {
      _showPaywallDialog(featureName, limitTypeFree);
      return false; 
    }

    return true; 
  }

  void _showPaywallDialog(String feature, int limit) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.lock_outline, color: kAccentColor), SizedBox(width: 8), Text("Limit Reached")]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("You have reached the free limit of $limit $feature."),
            const SizedBox(height: 12),
            const Text("Upgrade to Pro to add 1,000 items, invite more staff, and access advanced analytics.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            
            // ðŸ‘‡ UPDATED PRICE TO $49.99 ðŸ‘‡
            Container(
              padding: const EdgeInsets.all(12), 
              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)), 
              child: const Row(
                children: [
                  Icon(Icons.star, color: Colors.blue, size: 20), 
                  SizedBox(width: 8), 
                  // âœ… FIXED: Escaped the '$' with '\$'
                  Text("Pro Plan: \$49.99 / month", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))
                ]
              )
            )
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Maybe Later")),
          ElevatedButton(
            onPressed: () async { 
              Navigator.pop(ctx); 
              // ðŸ‘‡ ADDED ASYNC/AWAIT REFRESH LOGIC HERE TOO ðŸ‘‡
              await Navigator.push(context, MaterialPageRoute(builder: (_) => SubscriptionScreen(manager: manager!)));
              if (mounted) setState(() {});
            }, 
            child: const Text("Upgrade Now")
          ),        
        ],
      ),
    );
  }

  // --- REMOVE / LEAVE LOGIC ---
  Future<void> _handleRemoveUser(String targetUserId, String targetEmail, {bool isSelf = false}) async {
    if (manager == null) return;
    
    String orgName = 'this organization';
    try {
      final membership = manager!.user.memberships.firstWhere(
          (m) => m.companyId == manager!.user.companyId, 
          orElse: () => CompanyMembership(companyId: '', companyName: 'this organization', role: '')
      );
      orgName = membership.companyName;
    } catch (_) {}

    final bool confirm = await showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: Text(isSelf ? "Leave Organization?" : "Remove User?"), 
        content: Text(isSelf ? "Are you sure you want to leave $orgName?" : "Are you sure you want to remove $targetEmail from $orgName?"), 
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")), 
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isSelf ? "Leave" : "Remove", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))
        ]
      )
    ) ?? false;

    if (!confirm) return;

    try {
      final currentOrgId = manager!.user.companyId;
      final userRef = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5').collection('users').doc(targetUserId);

      await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5').runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        if (!snapshot.exists) throw Exception("User does not exist");
        
        // 1. Remove Membership
        List<dynamic> memberships = List.from(snapshot.data()?['memberships'] ?? []);
        memberships.removeWhere((m) => m['companyId'] == currentOrgId);
        
        // 2. Remove from Search Index (FIXED)
        // This ensures they stop appearing in the query
        List<dynamic> connectedIds = List.from(snapshot.data()?['connectedCompanyIds'] ?? []);
        connectedIds.remove(currentOrgId);

        // 3. Handle Active Company Switch (if they are currently logged into this org)
        String? newCompanyId = snapshot.data()?['companyId'];
        if (newCompanyId == currentOrgId) {
           // If they are leaving the org they are currently viewing, switch them to another one
           if (memberships.isNotEmpty) {
             newCompanyId = memberships.first['companyId'];
           } else {
             newCompanyId = ''; // No orgs left
           }
        }

        transaction.update(userRef, {
          'memberships': memberships,
          'connectedCompanyIds': connectedIds, // <--- UPDATE THE INDEX
          'companyId': newCompanyId 
        });
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isSelf ? "You left $orgName." : "User removed successfully.")));
      if (!isSelf && mounted) setState(() {}); 
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  Widget _buildUserHeader(String statusLabel, Color statusColor) {
    // USE LIVE PROFILE
    final user = _latestProfile ?? manager?.user;
    if (user == null) return const SizedBox.shrink();

    final String displayRole = _roleToDisplay(user.role).toUpperCase();
    
    // --- DARK MODE LOGIC ---
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = Theme.of(context).cardColor;
    final Color textColor = isDark ? Colors.white : kPrimaryColor;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.grey[500]!;
    final Color borderColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;

    // --- ROLE COLORS & ICONS (Restored) ---
    Color roleColor; 
    IconData roleIcon;
    if (user.role == 'owner') { 
      roleColor = Colors.amber[900]!; 
      roleIcon = Icons.stars; // Star for Owner
    } else if (user.role == 'business_admin') { 
      roleColor = Colors.purple; 
      roleIcon = Icons.verified_user; 
    } else if (user.role == 'manager') { 
      roleColor = Colors.blue[700]!; 
      roleIcon = Icons.manage_accounts; 
    } else if (user.role == 'user') { 
      roleColor = Colors.green[700]!; 
      roleIcon = Icons.person; 
    } else { 
      roleColor = Colors.grey[600]!; 
      roleIcon = Icons.block; 
    }

    return Container(
      width: double.infinity,
      // COMPACT PADDING: Reduced vertical from 16 to 12
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          // 1. AVATAR (Restored Icon Style)
          CircleAvatar(
            radius: 18, 
            backgroundColor: roleColor.withOpacity(0.1), // Light tint of role color
            child: Icon(roleIcon, color: roleColor, size: 20) // The Role Icon
          ),
          const SizedBox(width: 12),
          
          // 2. NAME & EMAIL (Left Aligned)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(
                  user.displayName.isNotEmpty ? user.displayName : "Team Member", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                  overflow: TextOverflow.ellipsis
                ),
                Text(
                  user.email, 
                  style: TextStyle(fontSize: 11, color: subTextColor, height: 1.2),
                  overflow: TextOverflow.ellipsis
                ),
              ]
            ),
          ),

          // 3. STATUS & ROLE (Right Aligned Column)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // STATUS BADGE
              InkWell(
                onTap: (user.role == 'owner' && !_isPro) ? () => _showPaywallDialog("Premium Features", 0) : null,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor.withOpacity(0.5), width: 0.5)
                  ),
                  child: Text(
                    statusLabel, 
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: statusColor, letterSpacing: 0.5),
                  ),
                ),
              ),
              
              const SizedBox(height: 4), // Tight gap

              // ROLE TEXT
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield, size: 10, color: roleColor.withOpacity(0.8)),
                  const SizedBox(width: 3),
                  Text(
                    displayRole, 
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: roleColor.withOpacity(0.8), letterSpacing: 0.2)
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String label, String value, Color color) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.3))), child: Row(mainAxisSize: MainAxisSize.min, children: [Text("$label: ", style: TextStyle(fontSize: 9, color: color.withOpacity(0.8))), Text(value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color))]));
  }

  Widget _buildFinanceItem(String label, String value, Color color) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color))]);
  }

  Widget _buildStockIndicator(int current, int minThreshold) {
    double safeLevel = minThreshold * 2.0; 
    if (safeLevel == 0) safeLevel = 100;
    
    double percentage = (current / safeLevel).clamp(0.0, 1.0);
    
    // Logic: Red if low, Green if healthy
    Color color; 
    if (current <= minThreshold) color = Colors.red; 
    else if (current < safeLevel) color = kAccentColor; 
    else color = Colors.green;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start, 
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, 
          children: [
            // FIX: Changed "Stock Level" to "Qty" to save space
            Text('Qty', style: TextStyle(fontSize: 10, color: Colors.grey[600])), 
            // FIX: Allow number to shrink slightly if it gets huge (e.g. 10,000)
            Flexible(
              child: Text(
                current.toString(), 
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            )
          ]
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(10), 
          child: LinearProgressIndicator(
            value: percentage, 
            backgroundColor: Colors.grey[200], 
            color: color, 
            minHeight: 6
          )
        )
      ]
    );
  }

  // --- ACTIONS & DIALOGS ---
  void _showInviteCode() async {
    if (manager == null) return;
    String code = await manager!.getJoinCode();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(title: const Text("Invite Staff"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Share this code with your employees.\nThey enter it when creating an account.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13)), const SizedBox(height: 24), Container(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)), child: SelectableText(code, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: kPrimaryColor))), const SizedBox(height: 8), const Text("Tap code to copy", style: TextStyle(fontSize: 10, color: Colors.grey))]), actions: [TextButton.icon(icon: const Icon(Icons.refresh, size: 16, color: Colors.red), label: const Text("Generate New Code", style: TextStyle(color: Colors.red)), onPressed: () async { bool confirm = await showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Reset Invite Code?"), content: const Text("The old code will stop working immediately."), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Reset", style: TextStyle(color: Colors.red)))])) ?? false; if (confirm && manager != null) { String newCode = await manager!.resetJoinCode(); setDialogState(() { code = newCode; }); } }), TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done"))])));
  }

  void _scanBarcode() {
    bool hasScanned = false;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.black, builder: (ctx) => SizedBox(height: MediaQuery.of(context).size.height * 0.8, child: Column(children: [AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text("Scan Barcode"), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))), Expanded(child: MobileScanner(onDetect: (capture) { if (hasScanned) return; final List<Barcode> barcodes = capture.barcodes; for (final barcode in barcodes) { if (barcode.rawValue != null) { hasScanned = true; Navigator.pop(ctx); Future.delayed(const Duration(milliseconds: 400), () => _handleScanResult(barcode.rawValue!)); return; } } })), const Padding(padding: EdgeInsets.all(24.0), child: Text("Point camera at a barcode", style: TextStyle(color: Colors.white)))])));
  }

  void _handleScanResult(String code) {
    if (manager == null) return;
    Component? existing;
    final matches = manager!.components.where((c) => c.barcode == code);
    if (matches.isNotEmpty) existing = matches.first;
    if (existing != null) { _showComponentOptions(existing); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Found: ${existing.name}"), backgroundColor: Colors.green)); } 
    else { _showAddComponent(scannedBarcode: code); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New Item! Enter details to save."))); }
  }

  void _showLowStockDialog() {
    if (manager == null) return;
    final lowItems = manager!.components.where((c) => c.quantity <= c.minStock).toList();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Row(children: [const Icon(Icons.warning_amber, color: Colors.red), const SizedBox(width: 8), Flexible(child: Text("Low Stock Alerts (${lowItems.length})", style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))]), content: SizedBox(width: double.maxFinite, child: lowItems.isEmpty ? const Padding(padding: EdgeInsets.all(16.0), child: Text("All stock levels are healthy!")) : ListView.separated(shrinkWrap: true, itemCount: lowItems.length, separatorBuilder: (_, __) => const Divider(), itemBuilder: (context, index) { final c = lowItems[index]; return ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: CircleAvatar(backgroundColor: Colors.red[50], child: Text("${c.quantity}", style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold))), title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text("Min Required: ${c.minStock}"), trailing: TextButton(onPressed: () { Navigator.pop(ctx); _showComponentOptions(c); }, child: const Text("RESTOCK"))); })), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))]));
  }

  void _showTeamDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('My Organization'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- HEADER ROW ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Team Members", style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text("Invite"),
                    onPressed: () async {
                      // 1. Get current count (Active + Pending)
                      final int currentCount = await manager!.getTeamMemberCount();
                      
                      // 2. Run the check. 
                      // This will automatically show the paywall if they are at 2/2 on Free.
                      if (!_checkLimit(currentCount, kFreeMaxTeam, "Team Members")) return;

                      if (context.mounted) {
                        Navigator.pop(ctx); 
                        _showInviteUserDialog();
                      }
                    }
                  )
                ]
              ),
              
              const Divider(),

              // --- NEW: PENDING INVITES SECTION (FIXED FOR DARK MODE) ---
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5')
                    .collection('invitations')
                    .where('companyId', isEqualTo: manager!.user.companyId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();

                  final invites = snapshot.data!.docs;
                  final bool isDark = Theme.of(context).brightness == Brightness.dark;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      // FIX: Dark background for Dark Mode, Light for Light Mode
                      color: isDark ? Colors.orange.withOpacity(0.15) : Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.orange.withOpacity(0.5) : Colors.orange[200]!
                      )
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            "Pending Invites (${invites.length})", 
                            style: TextStyle(
                              fontSize: 11, 
                              fontWeight: FontWeight.bold, 
                              // FIX: Make text bright orange in Dark Mode so it stands out
                              color: isDark ? Colors.orangeAccent : Colors.orange[800]
                            )
                          ),
                        ),
                        ...invites.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(
                              data['targetEmail'] ?? '', 
                              style: TextStyle(
                                fontSize: 13, 
                                fontWeight: FontWeight.w500,
                                // FIX: Force correct text color based on background
                                color: isDark ? Colors.white : Colors.black87
                              )
                            ),
                            subtitle: Text(
                              data['role']?.toString().toUpperCase() ?? 'STAFF', 
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? Colors.grey[400] : Colors.grey[700]
                              )
                            ),
                            trailing: TextButton(
                              onPressed: () async {
                                // REVOKE ACTION
                                await doc.reference.delete();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invite revoked/cancelled.")));
                                }
                              },
                              child: const Text("REVOKE", style: TextStyle(color: Colors.red, fontSize: 10)),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }
              ),
              // ------------------------------------

              // --- EXISTING: ACTIVE USERS LIST ---
              Flexible(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5')
                      .collection('users')
                      .where('connectedCompanyIds', arrayContains: manager!.user.companyId)
                      .snapshots(),
                  builder: (context, snapshot) { 
                    if (snapshot.hasError) return Text("Error: ${snapshot.error}");
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator()); 
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Text("No active members found."); 
                    
                    final users = snapshot.data!.docs;
                    
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (context, index) { 
                        final userData = users[index].data() as Map<String, dynamic>; 
                        final email = userData['email'] ?? 'Unknown';
                        final userId = users[index].id;
                        final isMe = userId == manager!.user.uid;
                        
                        String? targetRole; 
                        List<dynamic> mems = userData['memberships'] ?? [];
                        for(var m in mems) {
                           if(m['companyId'] == manager!.user.companyId) {
                              targetRole = m['role'];
                              break;
                           }
                        }

                        if (targetRole == null) return const SizedBox.shrink();

                        final bool amIOwner = manager!.user.role == 'owner'; 
                        final bool amIAdmin = manager!.user.role == 'business_admin'; 
                        bool canEdit = false; 
                        
                        if (!isMe) { 
                          if (amIOwner) canEdit = true; 
                          else if (amIAdmin) canEdit = targetRole != 'owner' && targetRole != 'business_admin'; 
                        } 
                        
                        Color bgColor; IconData icon; Color iconColor;
                        if (targetRole == 'owner') { bgColor = Colors.amber[100]!; iconColor = Colors.amber[900]!; icon = Icons.stars; } 
                        else if (targetRole == 'business_admin') { bgColor = Colors.purple[50]!; iconColor = Colors.purple; icon = Icons.verified_user; } 
                        else if (targetRole == 'manager') { bgColor = Colors.blue[50]!; iconColor = Colors.blue; icon = Icons.manage_accounts; } 
                        else if (targetRole == 'user') { bgColor = Colors.green[50]!; iconColor = Colors.green; icon = Icons.person; } 
                        else { bgColor = Colors.grey[200]!; iconColor = Colors.grey; icon = Icons.block; }
                        
                        return ListTile(
                          contentPadding: EdgeInsets.zero, 
                          leading: CircleAvatar(backgroundColor: bgColor, child: Icon(icon, color: iconColor, size: 20)), 
                          title: Text(email, style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal)), 
                          subtitle: Text(_roleToDisplay(targetRole), style: const TextStyle(fontSize: 10, color: Colors.grey)), 
                          trailing: canEdit ? IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.grey), onPressed: () { _updateUserRole(userId, email, targetRole!); }) : null
                        ); 
                      }
                    ); 
                  }
                )
              )
            ]
          )
        ), 
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))]
      )
    );
  }

  Future<void> _updateUserRole(String userId, String email, String currentRole) async {
    final myRole = manager?.user.role;
    if (myRole != 'owner' && myRole != 'business_admin') return;
    final bool amIOwner = myRole == 'owner';

    await showDialog(context: context, builder: (ctx) => SimpleDialog(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Manage Role for", style: TextStyle(fontSize: 12, color: Colors.grey[600])), Text(email, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]), children: [_buildRoleOption(ctx, userId, email, roleKey: 'user', title: "Staff", subtitle: "Can produce items.", isSelected: currentRole == 'user'), const Divider(height: 1), _buildRoleOption(ctx, userId, email, roleKey: 'manager', title: "Manager", subtitle: "Can edit stock & products.", isSelected: currentRole == 'manager'), if (amIOwner) ...[const Divider(height: 1), _buildRoleOption(ctx, userId, email, roleKey: 'business_admin', title: "Administrator", subtitle: "Full access.", isDangerous: true, isSelected: currentRole == 'business_admin')], const Divider(height: 1), SimpleDialogOption(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24), onPressed: () async { Navigator.pop(ctx); await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5').collection('users').doc(userId).update({'role': 'inactive'}); if (manager != null) await manager!.logActivity("User Deactivated", "Deactivated access for $email"); setState(() {}); }, child: Row(children: [const Icon(Icons.block, color: Colors.grey, size: 20), const SizedBox(width: 16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Deactivate User", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)), Text("Revoke all access.", style: TextStyle(fontSize: 12, color: Colors.grey[500]))])])),
    const Divider(height: 1),
    SimpleDialogOption(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24), onPressed: () { Navigator.pop(ctx); _handleRemoveUser(userId, email, isSelf: false); }, child: Row(children: [const Icon(Icons.person_remove, color: Colors.red, size: 20), const SizedBox(width: 16), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Remove from Team", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)), Text("Permanently remove user.", style: TextStyle(fontSize: 12, color: Colors.red[200]))])]))]));
  }

  Widget _buildRoleOption(BuildContext ctx, String userId, String email, {required String roleKey, required String title, required String subtitle, bool isDangerous = false, bool isSelected = false}) {
    return SimpleDialogOption(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      onPressed: () async {
        Navigator.pop(ctx);
        if (isSelected) {
          return;
        }

        try {
          final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
          final userRef = db.collection('users').doc(userId);
          final currentOrgId = manager!.user.companyId;

          // RUN TRANSACTION
          await db.runTransaction((transaction) async {
            final snapshot = await transaction.get(userRef);
            if (!snapshot.exists) {
              return;
            }

            // 1. Get the list
            List<dynamic> memberships = List.from(snapshot.data()?['memberships'] ?? []);
            
            // 2. Modify the list in memory (No 'found' variable needed)
            for (var i = 0; i < memberships.length; i++) {
              if (memberships[i]['companyId'] == currentOrgId) {
                memberships[i]['role'] = roleKey;
                break; // We found it, updated it, and now we stop looking.
              }
            }

            // 3. Write it back
            transaction.update(userRef, {
               'memberships': memberships,
            });
          });

          if (manager != null) {
            await manager!.logActivity("Role Change", "Changed $email to $title");
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Success: $email is now a $title"))
            );
            setState(() {});
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Failed to update role: $e"), backgroundColor: Colors.red)
            );
          }
        }
      },
      child: Row(
        // ... (Rest of your UI code remains the same)
        children: [
          Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, color: isSelected ? kPrimaryColor : Colors.grey[400], size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDangerous ? Colors.purple : kPrimaryColor)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }

  void _showInviteUserDialog() {
    final emailCtrl = TextEditingController();
    String selectedRole = 'user';
    bool isSending = false;
    final bool isOwner = manager?.user.isOwner ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invite Team Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("They will receive an in-app notification to join.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email)),
                keyboardType: TextInputType.emailAddress
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  const DropdownMenuItem(value: 'user', child: Text('Staff (Produce Only)', overflow: TextOverflow.ellipsis)),
                  const DropdownMenuItem(value: 'manager', child: Text('Manager (Edit Stock)', overflow: TextOverflow.ellipsis)),
                  if (isOwner) const DropdownMenuItem(value: 'business_admin', child: Text('Administrator (Full Access)', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))
                ],
                onChanged: (val) => setDialogState(() => selectedRole = val!)
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSending ? null : () async {
                if (emailCtrl.text.isEmpty) return;
                setDialogState(() => isSending = true);
                
                final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
                final targetEmail = emailCtrl.text.trim();
                
                // Get safe current company details
                final myCompanyId = manager!.user.companyId;
                final myMem = manager!.user.memberships.firstWhere(
                    (m) => m.companyId == myCompanyId, 
                    orElse: () => CompanyMembership(companyId: '', companyName: 'Our Company', role: '')
                );
                final myCompanyName = myMem.companyName;

                try {
                  // --- 1. NEW CHECK: Prevent Duplicate Invites ---
                  final existingInvites = await db.collection('invitations')
                      .where('targetEmail', isEqualTo: targetEmail)
                      .where('companyId', isEqualTo: myCompanyId)
                      .get();

                  if (existingInvites.docs.isNotEmpty) {
                    if (mounted) {
                      setDialogState(() => isSending = false);
                      // Close the dialog so they can't spam click
                      Navigator.pop(ctx); 
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('An invite is already pending for this user.'),
                          backgroundColor: Colors.orange
                        )
                      );
                    }
                    return; // STOP HERE
                  }
                  // -----------------------------------------------

                  // 2. Check if user exists ("Ghost User" Fix)
                  final userQuery = await db.collection('users').where('email', isEqualTo: targetEmail).limit(1).get();
                  
                  if (userQuery.docs.isNotEmpty) {
                    final userDoc = userQuery.docs.first;
                    final userData = userDoc.data();
                    List<dynamic> mems = userData['memberships'] ?? [];
                    
                    // If they are already a member, just un-hide them!
                    if (mems.any((m) => m['companyId'] == myCompanyId)) {
                        await userDoc.reference.update({
                            'connectedCompanyIds': FieldValue.arrayUnion([myCompanyId])
                        });
                        if (mounted) { 
                            Navigator.pop(ctx); 
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User is already on the team! Added to list."))); 
                        }
                        return;
                    }
                  }

                  // 3. Create the Invitation
                  await db.collection('invitations').add({
                    'targetEmail': targetEmail,
                    'companyId': myCompanyId,
                    'companyName': myCompanyName,
                    'role': selectedRole,
                    'invitedBy': manager!.user.displayName,
                    'invitedByEmail': manager!.user.email,
                    'createdAt': FieldValue.serverTimestamp()
                  });

                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite sent successfully!')));
                  }
                } catch (e) {
                  setDialogState(() => isSending = false);
                  print("Invite Error: $e");
                }
              },
              child: isSending 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) 
                  : const Text('Send Invite')
            )
          ]
        )
      )
    );
  }

  void _showJoinOrgDialog() {
    final codeCtrl = TextEditingController(); 
    bool isJoining = false;
    
    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Join Organization"), 
          content: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              const Text("Enter the 6-digit Invite Code."), 
              const SizedBox(height: 16), 
              TextField(
                controller: codeCtrl, 
                decoration: const InputDecoration(labelText: "Invite Code", hintText: "e.g. XJ9KL2", prefixIcon: Icon(Icons.vpn_key)), 
                textCapitalization: TextCapitalization.characters, 
                maxLength: 6
              )
            ]
          ), 
          actions: [
            TextButton(onPressed: isJoining ? null : () => Navigator.pop(ctx), child: const Text("Cancel")), 
            ElevatedButton(
              onPressed: isJoining ? null : () async { 
                if (codeCtrl.text.length < 6) return; 
                setDialogState(() => isJoining = true); 
                
                try { 
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;
                  final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
                  
                  // 1. Find Company
                  final snapshot = await db.collection('companies').where('joinCode', isEqualTo: codeCtrl.text.trim().toUpperCase()).limit(1).get();
                  if (snapshot.docs.isEmpty) throw Exception("Invalid Code");
                  
                  final companyDoc = snapshot.docs.first;
                  final companyId = companyDoc.id;
                  final companyName = companyDoc.data()['name'] ?? 'Org';

                  // 2. Update User (Default to 'user' role)
                  await db.collection('users').doc(user.uid).update({
                    'companyId': companyId,
                    'role': 'user',
                    'memberships': FieldValue.arrayUnion([{
                      'companyId': companyId,
                      'companyName': companyName,
                      'role': 'user'
                    }]),
                    'connectedCompanyIds': FieldValue.arrayUnion([companyId])
                  });

                  if (mounted) { 
                    Navigator.pop(ctx); 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Joined & Switched Successfully!"))); 
                  } 
                } catch (e) { 
                  setDialogState(() => isJoining = false); 
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll("Exception:", "")), backgroundColor: Colors.red)); 
                } 
              }, 
              child: isJoining ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator()) : const Text("Join")
            )
          ]
        )
      )
    );
  }

  void _showCreateOrgDialog() {
    final nameCtrl = TextEditingController();
    bool isCreating = false;

    showDialog(
      context: context, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Create New Organization"), 
          content: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              const Text("You will be the Owner of this new workspace."), 
              const SizedBox(height: 16), 
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Organization Name", hintText: "e.g. My Side Hustle"), textCapitalization: TextCapitalization.words)
            ]
          ), 
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), 
            ElevatedButton(
              onPressed: isCreating ? null : () async { 
                if (nameCtrl.text.isEmpty) return;
                setDialogState(() => isCreating = true);
                
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;
                  final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
                  
                  // 1. Create Company
                  final newCompanyRef = db.collection('companies').doc(); // Auto-ID
                  final rnd = Random();
                  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
                  String joinCode = List.generate(6, (i) => chars[rnd.nextInt(chars.length)]).join();
                  
                  await newCompanyRef.set({
                    'name': nameCtrl.text.trim(),
                    'created_at': FieldValue.serverTimestamp(),
                    'joinCode': joinCode,
                    'ownerId': user.uid
                  });
                  
                  // 2. Update User
                  await db.collection('users').doc(user.uid).update({
                    'companyId': newCompanyRef.id,
                    'role': 'owner',
                    'memberships': FieldValue.arrayUnion([{
                      'companyId': newCompanyRef.id,
                      'companyName': nameCtrl.text.trim(),
                      'role': 'owner'
                    }]),
                    'connectedCompanyIds': FieldValue.arrayUnion([newCompanyRef.id])
                  });

                  if (mounted) {
                    Navigator.pop(ctx); 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Organization Created & Switched!"))); 
                  }
                } catch (e) {
                   setDialogState(() => isCreating = false);
                   print(e);
                }
              }, 
              child: isCreating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator()) : const Text("Create & Switch")
            )
          ]
        )
      )
    );
  }
  
  void _showRenameOrgDialog() {
    final nameCtrl = TextEditingController();
    try { final matches = manager?.user.memberships.where((m) => m.companyId == manager?.user.companyId); final currentName = (matches != null && matches.isNotEmpty) ? matches.first.companyName : ""; nameCtrl.text = currentName; } catch (_) {}
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Rename Organization"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Enter a new name for this organization."), const SizedBox(height: 16), TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Organization Name"), textCapitalization: TextCapitalization.words)]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(onPressed: () async { if (nameCtrl.text.isNotEmpty && manager != null) { try { await manager!.renameOrganization(nameCtrl.text); if (mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Renamed to ${nameCtrl.text}"))); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red)); } } }, child: const Text("Save"))]));
  }

  void _showComponentOptions(Component c) {
    final qtyCtrl = TextEditingController();
    final minCtrl = TextEditingController(text: c.minStock.toString());
    final bool isOwner = manager?.user.isOwner ?? false;
    final bool isManager = manager?.user.canManageStock ?? false; // Managers & Owners

    Product? linkedProduct;
    final matches = manager!.products.where((p) => p.name == c.name);
    if (matches.isNotEmpty) linkedProduct = matches.first;
    final bool isProduct = linkedProduct != null;

    final costCtrl = TextEditingController(
        text: isProduct
            ? linkedProduct.sellingPrice.toString()
            : c.costPerUnit.toString());
    bool hasAmount = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. STOCK BADGE
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  decoration: BoxDecoration(
                      color: isProduct
                          ? Colors.orange.withOpacity(0.1)
                          : kPrimaryColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isProduct ? Colors.orange : kPrimaryColor.withOpacity(0.1))),
                  child: Column(children: [
                    Text(isProduct ? "FINISHED GOODS STOCK" : "RAW MATERIAL STOCK",
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: Colors.grey[700])),
                    const SizedBox(height: 4),
                    Text("${c.quantity}",
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: isProduct ? Colors.orange[800] : kPrimaryColor))
                  ]),
                ),
                const SizedBox(height: 24),
                
                // 2. INPUTS
                TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                        hintText: "Enter Amount",
                        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    onChanged: (val) => setDialogState(() => hasAmount = val.isNotEmpty)),
                const SizedBox(height: 16),
                TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Low Stock Alert Level",
                        prefixIcon: Icon(Icons.warning_amber, color: Colors.orange))),
                const SizedBox(height: 12),
                TextField(
                    controller: costCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: isProduct ? "Selling Price (\$)" : "Cost Per Unit (\$)",
                        prefixIcon: Icon(Icons.attach_money,
                            color: isProduct ? Colors.blue : Colors.green),
                        helperText: isProduct
                            ? "Update value for Margins."
                            : "Cost to buy this material.")),
                const SizedBox(height: 24),

                // 3. UPDATE / ADD / REMOVE BUTTONS
                if (!hasAmount)
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                          onPressed: () async {
                            if (!_checkLimit(manager!.components.length, kFreeMaxStock, "Stock Edits")) return;

                            int newMin = int.tryParse(minCtrl.text) ?? c.minStock;
                            if (newMin != c.minStock && manager != null) {
                              await manager!.updateComponentThreshold(c.id, newMin);
                            }
                            double newVal = double.tryParse(costCtrl.text) ?? 0.0;
                            if (manager != null) {
                              if (isProduct) {
                                await manager!.updateProductPrice(linkedProduct!.id, newVal);
                              } else if (newVal != c.costPerUnit) {
                                await manager!.updateComponentCost(c.id, newVal);
                              }
                            }
                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Item updated")));
                            }
                            setState(() {});
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: const Text("UPDATE DETAILS")))
                else
                  Row(children: [
                    Expanded(
                        child: ElevatedButton.icon(
                            onPressed: () async {
                              if (!_checkLimit(manager!.components.length, kFreeMaxStock, "Stock Adjustments")) return;
                              int delta = int.tryParse(qtyCtrl.text) ?? 0;
                              if (delta > 0) {
                                await manager!.updateComponentQuantity(c.id, -delta);
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text("Removed $delta from ${c.name}"),
                                      backgroundColor: Colors.orange[800]));
                                }
                                setState(() {});
                              }
                            },
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text("REMOVE"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.red[700],
                                elevation: 0,
                                side: BorderSide(color: Colors.red[200]!),
                                padding: const EdgeInsets.symmetric(vertical: 16)))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: ElevatedButton.icon(
                            onPressed: () async {
                              if (!_checkLimit(manager!.components.length, kFreeMaxStock, "Stock Adjustments")) return;
                              int delta = int.tryParse(qtyCtrl.text) ?? 0;
                              if (delta > 0) {
                                await manager!.updateComponentQuantity(c.id, delta);
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      content: Text("Added $delta to ${c.name}"),
                                      backgroundColor: kSecondaryColor));
                                }
                                setState(() {});
                              }
                            },
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text("ADD"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: kSecondaryColor,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(vertical: 16))))
                  ]),

                const SizedBox(height: 24),

                // 4. ðŸ‘‡ RESTORED PRINT BUTTON ðŸ‘‡
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // Ask user how many labels to print
                      final qtyStr = await showDialog<String>(
                        context: context,
                        builder: (ctx) {
                          final qCtrl = TextEditingController(text: '30'); 
                          return AlertDialog(
                            title: const Text("Print Labels"),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text("Generate a PDF of QR codes to stick on boxes/shelves."),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: qCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: "Quantity (Labels)"),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, qCtrl.text), child: const Text("Generate PDF"))
                            ],
                          );
                        }
                      );

                      if (qtyStr != null && qtyStr.isNotEmpty) {
                        int q = int.tryParse(qtyStr) ?? 1;
                        String dataToEncode = c.barcode.isNotEmpty ? c.barcode : c.id;
                        await PdfService().printItemLabels(c.name, dataToEncode, q);
                      }
                    },
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text("Print Barcode Labels"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[800],
                      side: BorderSide(color: Colors.blue[200]!)
                    ),
                  ),
                ),
                // ðŸ‘† END PRINT BUTTON ðŸ‘†

                // 5. ARCHIVE & DELETE
                if (isManager) ...[
                  const Divider(height: 32),
                  
                  // Archive: Visible to Managers & Owners
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDelete("Archive ${c.name}?", () async {
                          if (manager != null) {
                            await manager!.updateComponentStatus(c.id, false);
                            setState(() {});
                          }
                        }, isArchive: true);
                      },
                      icon: const Icon(Icons.archive_outlined, color: Colors.grey, size: 18),
                      label: const Text("Archive Item",
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  ),

                  // Delete: Visible ONLY to Owner
                  if (isOwner)
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDelete("Delete ${c.name} entirely?", () async {
                            if (manager != null) {
                              await manager!.removeComponent(c.id);
                              setState(() {});
                            }
                          });
                        },
                        icon: const Icon(Icons.delete_forever, color: Colors.red, size: 18),
                        label: const Text("Delete Item Permanently",
                            style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showProductOptions(Product p) {
    final qtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: p.sellingPrice.toString());
    final bool isManager = manager?.user.canManageStock ?? false;
    final bool isOwner = manager?.user.isOwner ?? false;

    // 1. ðŸ‘‡ FIND REAL STOCK ITEM FOR THIS PRODUCT
    final matchingStock = manager!.components.firstWhere(
      (c) => c.name.toLowerCase() == p.name.toLowerCase(),
      orElse: () => Component(id: '', name: '', quantity: 0, minStock: 0, costPerUnit: 0.0),
    );
    final int displayQty = matchingStock.id.isNotEmpty ? matchingStock.quantity : p.producedCount;
    final String label = matchingStock.id.isNotEmpty ? "CURRENT STOCK" : "LIFETIME PRODUCED";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                
                // 2. ðŸ‘‡ DYNAMIC STOCK BADGE CONTAINER
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  decoration: BoxDecoration(
                    color: matchingStock.id.isNotEmpty 
                        ? kSecondaryColor.withOpacity(0.1) // Greenish if tracked
                        : Colors.orange.withOpacity(0.1),  // Orange if not tracked
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: matchingStock.id.isNotEmpty ? kSecondaryColor : Colors.orange.withOpacity(0.3)
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(label, 
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                              color: Colors.grey[700])),
                      const SizedBox(height: 4),
                      Text("$displayQty", 
                          style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: matchingStock.id.isNotEmpty ? kSecondaryColor : Colors.orange[800])),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "Enter Quantity",
                    hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (isManager) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Selling Price (\$)",
                      prefixIcon: Icon(Icons.attach_money, color: Colors.blue),
                      helperText: "Used to calculate profit margin.",
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  isManager
                      ? "Note: Adding consumes components.\nShipping removes stock (Sales)."
                      : "Enter amount to produce.\nThis will deduct components from stock.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                
                // 3. ðŸ‘‡ ACTION BUTTONS ROW
                Row(
                  children: [
                    if (isManager) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            int delta = int.tryParse(qtyCtrl.text) ?? 0;
                            double newPrice = double.tryParse(priceCtrl.text) ?? p.sellingPrice;
                            
                            // A. Update Price if changed
                            if (newPrice != p.sellingPrice && manager != null) {
                              await manager!.updateProductPrice(p.id, newPrice);
                            }

                            // B. Handle Shipping
                            if (delta > 0 && manager != null) {
                              // Find stock item again to be safe
                              final stockItem = manager!.components.firstWhere(
                                (c) => c.name.toLowerCase() == p.name.toLowerCase(),
                                orElse: () => Component(id: '', name: '', quantity: 0, minStock: 0, costPerUnit: 0.0),
                              );

                              if (stockItem.id.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("This product isn't tracked in Stock yet. Produce some first!"))
                                );
                                return; 
                              }

                              if (stockItem.quantity < delta) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Not enough stock! Only ${stockItem.quantity} available."),
                                    backgroundColor: Colors.redAccent,
                                  )
                                );
                                return;
                              }

                              // EXECUTE SHIP
                              await manager!.batchAdjustDown(p.id, delta);
                              
                              if (mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text("Shipped $delta ${p.name}"),
                                  backgroundColor: kSecondaryColor,
                                ));
                              }
                              setState(() {});
                            } else if (newPrice != p.sellingPrice) {
                              Navigator.pop(ctx);
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.output),
                          label: const Text("SHIP"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.orange[800],
                            elevation: 0,
                            side: BorderSide(color: Colors.orange[200]!),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    
                    // PRODUCE BUTTON
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // Ask for Production Details (Total vs Scrap)
                          final values = await showDialog<Map<String, int>>(
                            context: context,
                            builder: (ctx) {
                              final totalCtrl = TextEditingController(text: qtyCtrl.text); 
                              final scrapCtrl = TextEditingController(text: '0');
                              return AlertDialog(
                                title: const Text("Production Run"),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: totalCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: "Total Run Size"),
                                    ),
                                    const SizedBox(height: 16),
                                    TextField(
                                      controller: scrapCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: "Failed / Scrap Qty",
                                        prefixIcon: Icon(Icons.delete_outline, color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(ctx, {
                                        'total': int.tryParse(totalCtrl.text) ?? 0,
                                        'scrap': int.tryParse(scrapCtrl.text) ?? 0,
                                      });
                                    },
                                    child: const Text("Confirm"),
                                  )
                                ],
                              );
                            }
                          );

                          if (values == null) return; 

                          int total = values['total']!;
                          int scrap = values['scrap']!;
                          int good = total - scrap;

                          if (total > 0 && manager != null) {
                            // Run Production Logic
                            bool success = await manager!.batchProduce(p.id, total, scrap);
                            
                            if (mounted) {
                              // If successful, update the UI (Dialog stays open or closes depending on pref)
                              if(success) {
                                Navigator.pop(ctx); // Close dialog on success
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Produced $good Good. Scrapped $scrap."),
                                    backgroundColor: kSecondaryColor,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("STOCK LOW: Cannot run production."),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                            setState(() {});
                          }
                        },
                        icon: const Icon(Icons.factory),
                        label: const Text("PRODUCE"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSecondaryColor,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // 4. ðŸ‘‡ DELETE/ARCHIVE OPTIONS
                if (isManager) ...[
                  const Divider(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: isOwner
                        ? TextButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmDelete("Delete Product Definition?", () async {
                                if (manager != null) {
                                  await manager!.removeProduct(p.id);
                                  setState(() {});
                                }
                              });
                            },
                            icon: const Icon(Icons.delete_forever, color: Colors.red, size: 18),
                            label: const Text("Delete Product Permanently",
                                style: TextStyle(color: Colors.red, fontSize: 12)),
                          )
                        : TextButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmDelete("Archive this Product?", () async {
                                if (manager != null) {
                                  await manager!.updateProductStatus(p.id, false);
                                  setState(() {});
                                }
                              });
                            },
                            icon: const Icon(Icons.archive_outlined, color: Colors.grey, size: 18),
                            label: const Text("Archive Product",
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(String title, VoidCallback onConfirm, {bool isArchive = false}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(isArchive 
          ? 'This item will be hidden from the main list but kept in records.' 
          : 'Are you sure? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx);
            },
            child: Text(
              isArchive ? 'Archive' : 'Delete',
              style: TextStyle(
                color: isArchive ? Colors.orange[800] : Colors.red, 
                fontWeight: FontWeight.bold
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddStockChoice() {
    if (!_checkLimit(manager!.components.length, kFreeMaxStock, "Stock Items")) return;
    
    // Check Dark Mode
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = Theme.of(context).cardColor;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor, 
      useSafeArea: true, 
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24.0, 
          right: 24.0, 
          top: 24.0, 
          bottom: 24.0 + MediaQuery.of(ctx).padding.bottom, 
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Add Inventory Item", 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8)
                ),
                child: const Icon(Icons.grain, color: Colors.blue),
              ),
              title: Text("New Raw Material", style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
              subtitle: Text("Create a basic component from scratch.", style: TextStyle(color: subTextColor)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddComponent();
              },
            ),
            
            // --- FIXED LINE BELOW (Removed the comma before else) ---
            if (isDark) const Divider(color: Colors.grey) else const Divider(),
            // ------------------------------------------------------

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(isDark ? 0.2 : 0.1), 
                  borderRadius: BorderRadius.circular(8)
                ),
                child: const Icon(Icons.widgets, color: Colors.orange),
              ),
              title: Text("Track Production Item", style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
              subtitle: Text("Add a Product to stock so it can be used in other recipes.", style: TextStyle(color: subTextColor)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddProductAsComponent();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddComponent({String? scannedBarcode}) {
    // 1. Check limits
    if (!_checkLimit(manager!.components.length, kFreeMaxStock, "Stock Items")) return;
    
    final nameCtrl = TextEditingController(); 
    final qtyCtrl = TextEditingController(text: '100'); 
    final minCtrl = TextEditingController(text: '20'); 
    final costCtrl = TextEditingController(text: '0.00'); 
    bool isDialogLoading = false;

    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Component'), 
          content: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
               // ... (Barcode UI Code is fine to keep) ...
               if (scannedBarcode != null && scannedBarcode.isNotEmpty) 
                 Container(padding: const EdgeInsets.all(8), child: Text("Linked: $scannedBarcode")),

              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Component Name', prefixIcon: Icon(Icons.inventory_2)), textCapitalization: TextCapitalization.sentences), 
              const SizedBox(height: 12), 
              Row(children: [
                  Expanded(child: TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'Start Qty'), keyboardType: TextInputType.number)), 
                  const SizedBox(width: 12), 
                  Expanded(child: TextField(controller: minCtrl, decoration: const InputDecoration(labelText: 'Min Limit'), keyboardType: TextInputType.number))
              ]), 
              const SizedBox(height: 12), 
              TextField(controller: costCtrl, decoration: const InputDecoration(labelText: 'Cost (\$)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))
            ]
          ), 
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), 
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kSecondaryColor, foregroundColor: Colors.white),
              onPressed: isDialogLoading ? null : () async { 
                if (nameCtrl.text.isEmpty) return; 
                setDialogState(() => isDialogLoading = true); 
                try { 
                  if (manager != null) { 
                    // 2. Add to Database
                    await manager!.addComponent(nameCtrl.text, int.tryParse(qtyCtrl.text) ?? 0, int.tryParse(minCtrl.text) ?? 10, double.tryParse(costCtrl.text) ?? 0.0, barcode: scannedBarcode ?? ''); 
                    
                    // 3. âœ¨ THE CRITICAL FIX: Check mounted before using context
                    if (!mounted) return; 

                    Navigator.pop(ctx); // Close dialog
                    setState(() {});    // Refresh list
                    
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Item Added to Stock!"), backgroundColor: Colors.green));
                  } 
                } catch (e) { 
                  if (mounted) setDialogState(() => isDialogLoading = false); 
                } 
              }, 
              child: isDialogLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Text('Add to Stock')
            )
          ]
        )
      )
    );
  }

  void _showAddProduct() {
    if (!_checkLimit(manager!.products.length, kFreeMaxProducts, "Production Items")) return;
    final nameCtrl = TextEditingController(); final priceCtrl = TextEditingController(text: '0.00'); final Map<String, int> bom = {}; bool isDialogLoading = false;
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(title: const Text('New Product Definition'), content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Product Name'), enabled: !isDialogLoading), const SizedBox(height: 12), TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Selling Price (\$)', prefixIcon: Icon(Icons.attach_money)), keyboardType: const TextInputType.numberWithOptions(decimal: true), enabled: !isDialogLoading), const SizedBox(height: 20), const Text('Bill of Materials (BOM)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(height: 8), if (manager?.components.isEmpty ?? true) Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8)), child: const Text("No components available. Add components to stock first.", style: TextStyle(fontSize: 12, color: Colors.brown))), if (manager != null) ...manager!.components.map((c) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(c.name)), SizedBox(width: 100, height: 40, child: TextField(keyboardType: TextInputType.number, enabled: !isDialogLoading, decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8)), onChanged: (v) { final q = int.tryParse(v) ?? 0; if (q > 0) bom[c.id] = q; else bom.remove(c.id); }))])))])),), actions: [TextButton(onPressed: isDialogLoading ? null : () => Navigator.pop(ctx), child: const Text('Cancel')), ElevatedButton(onPressed: isDialogLoading ? null : () async { if (nameCtrl.text.isNotEmpty && bom.isNotEmpty && manager != null) { setDialogState(() => isDialogLoading = true); try { await manager!.addProduct(nameCtrl.text, bom, double.tryParse(priceCtrl.text) ?? 0.0); if (mounted) setState(() {}); if (context.mounted) Navigator.pop(ctx); } catch (e) { setDialogState(() => isDialogLoading = false); } } }, child: isDialogLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Product'))])));
  }

  void _showAddProductAsComponent() {
    if (!_checkLimit(manager!.components.length, kFreeMaxStock, "Stock Items")) return;
    if (manager == null) return;

    final existingNames = manager!.components.map((c) => c.name.toLowerCase()).toSet();
    final availableProducts = manager!.products.where((p) => !existingNames.contains(p.name.toLowerCase())).toList();

    if (availableProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All products are already tracked in stock!")));
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Track Product in Stock"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: availableProducts.length,
            separatorBuilder: (_, __) => const Divider(),
            // ðŸ‘‡ RENAMED 'context' TO 'listCtx' TO PREVENT SHADOWING BUG
            itemBuilder: (listCtx, index) {
              final p = availableProducts[index];
              return ListTile(
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Current Production Count: ${p.producedCount}"),
                trailing: const Icon(Icons.add_circle_outline, color: kPrimaryColor),
                onTap: () async {
                  // 1. Close the dialog
                  Navigator.pop(dialogCtx);

                  // 2. Do the work
                  await manager!.addComponent(p.name, p.producedCount, 1, 0.0);

                  // 3. Safety Check
                  if (!mounted) return;

                  // 4. Update UI
                  setState(() {});

                  // 5. Show Message using 'this.context' (The Main Screen)
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text("${p.name} is now tracked in Stock."),
                      backgroundColor: kSecondaryColor,
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text("Cancel")),
        ],
      ),
    );
  }

  // --- UI LISTS ---
  Widget _buildInventoryList() {
    if (manager == null || manager!.components.isEmpty) {
      return _buildEmptyState(Icons.grid_view, "No components in stock.");
    }

    final bool showMoney = manager!.user.role == 'owner' || manager!.user.role == 'business_admin';
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // --- 1. FILTERING LOGIC ---
    var filteredList = List<Component>.from(manager!.components);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredList = filteredList.where((c) => 
        c.name.toLowerCase().contains(q) || 
        c.id.contains(q) || 
        c.barcode.contains(q)
      ).toList();
    }

    if (!_showArchived) {
      filteredList = filteredList.where((c) => c.isActive).toList();
    }

    // --- 2. SORTING LOGIC (FIXED) ---
    
    // âš¡ Performance: Create a map of Product Name -> Selling Price
    // This allows the sorter to look up prices instantly (O(1)) instead of looping every time.
    final Map<String, double> productPrices = {
      for (var p in manager!.products) p.name : p.sellingPrice
    };

    filteredList.sort((a, b) {
      switch (_sortBy) {
        case 'quantity_asc': return a.quantity.compareTo(b.quantity);
        case 'quantity_desc': return b.quantity.compareTo(a.quantity);
        
        case 'value_high': 
          // Use Selling Price if it's a product, otherwise use Cost
          double priceA = productPrices[a.name] ?? a.costPerUnit;
          double valA = a.quantity * priceA;
          
          double priceB = productPrices[b.name] ?? b.costPerUnit;
          double valB = b.quantity * priceB;
          
          return valB.compareTo(valA); // High to Low
          
        case 'value_low':
          double priceA = productPrices[a.name] ?? a.costPerUnit;
          double valA = a.quantity * priceA;
          
          double priceB = productPrices[b.name] ?? b.costPerUnit;
          double valB = b.quantity * priceB;
          
          return valA.compareTo(valB); // Low to High
          
        default: return a.name.compareTo(b.name); 
      }
    });

    return Column(
      children: [
        // --- TOP BAR (Search/Sort) ---
        Container(
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: "Search items...",
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        filled: true
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => setState(() => _showArchived = !_showArchived),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _showArchived ? Colors.orange.withOpacity(0.2) : (isDark ? Colors.grey[800] : Colors.grey[200]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _showArchived ? Icons.archive : Icons.archive_outlined,
                        color: _showArchived ? Colors.orange[800] : Colors.grey,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text("Name"),
                      selected: _sortBy == 'name',
                      onSelected: (val) => setState(() => _sortBy = 'name'),
                    ),
                    const SizedBox(width: 8),
                    _buildToggleSortChip("Stock", "quantity_asc", "quantity_desc"),
                    const SizedBox(width: 8),
                    _buildToggleSortChip("Value", "value_low", "value_high", defaultToDesc: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // --- THE LIST ---
        Expanded(
          child: filteredList.isEmpty 
            ? Center(child: Text("No items found", style: TextStyle(color: Colors.grey[500])))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: filteredList.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8), 
                // ... inside ListView.separated ...
                itemBuilder: (ctx, i) {
                  final c = filteredList[i];
                  final bool isArchived = !c.isActive;
                  final bool isLow = c.quantity <= c.minStock;

                  // --- 1. ðŸ§  AUTOMATIC TIER LOGIC ---
                  // Calculates depth based on recipe ingredients (1 = Raw, 2 = Simple, 3 = Sub-Assembly, etc.)
                  int tierLevel = _resolveTier(c.name); 

                  // --- 2. PRODUCT DATA LOOKUP ---
                  // We still need the Product object to calculate costs/margins for tiers > 1
                  Product? linkedProduct;
                  if (tierLevel > 1) { 
                    final matches = manager!.products.where((p) => p.name == c.name);
                    if (matches.isNotEmpty) linkedProduct = matches.first;
                  }
                  final bool isProducedItem = linkedProduct != null;

                  // --- 3. GET STYLES ---
                  final style = _getTierStyle(tierLevel, isDark);
                  final Color badgeColor = style['color'];
                  
                  // Handle Archived State override
                  final Color cardBg = isArchived 
                      ? (isDark ? Colors.black : Colors.grey[100]!) 
                      : style['bg'];
                      
                  final Color borderColor = isArchived
                      ? (isDark ? Colors.grey[900]! : Colors.grey[300]!)
                      : (tierLevel > 1 ? badgeColor.withOpacity(0.5) : (isLow ? Colors.red.withOpacity(0.5) : (isDark ? Colors.grey[800]! : Colors.grey[200]!)));

                  final Color primaryText = isDark ? Colors.white : kPrimaryColor;
                  final Color secondaryText = isDark ? Colors.grey[400]! : Colors.grey[600]!;

                  return Opacity(
                    opacity: isArchived ? 0.6 : 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBg, 
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                // A. EDIT BUTTONS
                                if (manager?.user.canManageStock ?? false) ...[
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => isArchived ? manager!.updateComponentStatus(c.id, true) : _showComponentOptions(c),
                                    icon: Icon(isArchived ? Icons.settings_backup_restore : Icons.edit, size: 18, color: tierLevel > 1 ? badgeColor : kPrimaryColor),
                                  ),
                                  const SizedBox(width: 4),
                                ],

                                // B. NAME & ID COLUMN
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              c.name,
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryText),
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          
                                          // ðŸ‘‡ DYNAMIC BADGE RENDERING (TIER 2, 3, 4, 5)
                                          if (tierLevel > 1) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: badgeColor.withOpacity(0.2), // Tinted background
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: badgeColor.withOpacity(0.5))
                                              ),
                                              child: Text(
                                                style['label'], // "TIER 3", "TIER 4", etc.
                                                style: TextStyle(color: badgeColor, fontSize: 8, fontWeight: FontWeight.bold)
                                              ),
                                            ),
                                          ]
                                        ],
                                      ),
                                      Text("ID: ${c.id.substring(c.id.length - 4)}", style: TextStyle(fontSize: 9, color: secondaryText)),
                                    ],
                                  ),
                                ),

                                // C. STOCK INDICATOR
                                SizedBox(width: 85, child: _buildStockIndicator(c.quantity, c.minStock)),
                              ],
                            ),

                            FutureBuilder<Map<String, int>>(
                              future: _calculateDaysOfSupply(), 
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const SizedBox.shrink(); 
                                
                                // Default to 999 (Safe) if no data found for this item
                                final daysLeft = snapshot.data![c.name] ?? 999;
                                
                                // Hide the badge if we have plenty of stock (e.g. > 60 days)
                                if (daysLeft > 60) return const SizedBox.shrink();

                                Color pillColor;
                                String text;
                                
                                if (daysLeft <= 7) {
                                  pillColor = Colors.red;
                                  text = "CRITICAL: $daysLeft Days Left";
                                } else if (daysLeft <= 30) {
                                  pillColor = Colors.orange;
                                  text = "Low: $daysLeft Days Supply";
                                } else {
                                  pillColor = Colors.blue;
                                  text = "~$daysLeft Days Supply";
                                }

                                return Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: pillColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: pillColor.withOpacity(0.3))
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.timelapse, size: 12, color: pillColor),
                                      const SizedBox(width: 6),
                                      Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: pillColor)),
                                    ],
                                  ),
                                );
                              },
                            ),
                            
                            // D. FINANCIALS ROW
                            if (showMoney && !isArchived) ...[
                              Divider(height: 8, thickness: 0.5, color: isDark ? Colors.white10 : Colors.black12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  if (isProducedItem) ...[
                                    // Uses 'linkedProduct' which is safe here because tierLevel > 1 checks for it
                                    _buildMiniBadge("Build Cost", "\$${linkedProduct.getProductionCost(manager!.components).toStringAsFixed(2)}", tierLevel > 1 ? badgeColor : Colors.teal),
                                    Text("Value: \$${(c.quantity * linkedProduct.sellingPrice).toStringAsFixed(0)}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryText)),
                                  ] else ...[
                                    _buildMiniBadge("Cost", "\$${c.costPerUnit.toStringAsFixed(2)}", secondaryText),
                                    Text("Value: \$${(c.quantity * c.costPerUnit).toStringAsFixed(0)}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryText)),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  // ðŸ§  LOGIC: Calculate Max Buildable & Show Details
  int _calculateMaxBuildable(Product p) {
    if (manager == null || p.componentsNeeded.isEmpty) return 0;
    int minBuild = 999999; // Start high
    
    for (var entry in p.componentsNeeded.entries) {
       final comp = manager!.getComponent(entry.key);
       if (comp == null) return 0; // Missing ingredient = 0 build
       
       // Calculate how many we can make with THIS specific ingredient
       int possible = (comp.quantity / entry.value).floor();
       
       // If this is the lowest so far, it's our bottleneck
       if (possible < minBuild) minBuild = possible;
    }
    return minBuild == 999999 ? 0 : minBuild;
  }

  void _showBottleneckDetails(Product p) {
    List<Map<String, dynamic>> ingredients = [];
    int maxPossible = 999999;
    String bottleneckName = "";

    // 1. Analyze all ingredients
    for (var entry in p.componentsNeeded.entries) {
        final comp = manager!.getComponent(entry.key);
        String name = comp?.name ?? "Unknown Item";
        int stock = comp?.quantity ?? 0;
        int needed = entry.value;
        int possible = needed > 0 ? (stock / needed).floor() : 0;
        
        if (possible < maxPossible) {
            maxPossible = possible;
            bottleneckName = name;
        }
        
        ingredients.add({
           "name": name,
           "stock": stock,
           "needed": needed,
           "possible": possible
        });
    }

    // 2. Show the "Smart" Dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Row(
           children: [
             const Icon(Icons.analytics, color: kSecondaryColor),
             const SizedBox(width: 8),
             const Text("Build Analysis"),
           ],
         ),
         content: Column(
           mainAxisSize: MainAxisSize.min,
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             // The Big Result
             Container(
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(
                 color: maxPossible > 0 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                 borderRadius: BorderRadius.circular(8),
                 border: Border.all(color: maxPossible > 0 ? Colors.green : Colors.red)
               ),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   const Text("You can build:", style: TextStyle(fontWeight: FontWeight.bold)),
                   Text("$maxPossible", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: maxPossible > 0 ? Colors.green : Colors.red)),
                 ],
               ),
             ),
             const SizedBox(height: 16),
             
             // The Bottleneck Warning
             if (maxPossible == 0 || maxPossible < 10) 
               Text("âš ï¸ Limiting Factor: $bottleneckName", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
             
             const Divider(height: 24),
             
             // The Breakdown
             const Text("Ingredient Status:", style: TextStyle(fontSize: 12, color: Colors.grey)),
             const SizedBox(height: 8),
             
             // SCROLLABLE LIST CONTAINER (Fixes Overflow if list is long)
             SizedBox(
               width: double.maxFinite,
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: ingredients.map((item) {
                    bool isLimit = item['name'] == bottleneckName;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 1. NAME (Flexible + Ellipsis to prevent overflow)
                          Expanded(
                            child: Text(
                              "â€¢ ${item['name']}", 
                              style: TextStyle(fontWeight: isLimit ? FontWeight.bold : FontWeight.normal),
                              overflow: TextOverflow.ellipsis, 
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8), // Spacing
                          
                          // 2. MATH (Fixed logic, stays visible)
                          Text(
                            "${item['stock']} / ${item['needed']} = ${item['possible']}", 
                            style: TextStyle(fontSize: 12, color: isLimit ? Colors.red : Colors.grey[700])
                          ),
                        ],
                      ),
                    );
                 }).toList(),
               ),
             )
           ],
         ),
         actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done"))],
      )
    );
  }

  // Helper for Smart Toggle Chips
  Widget _buildToggleSortChip(String label, String keyAsc, String keyDesc, {bool defaultToDesc = false}) {
    final bool isActive = _sortBy == keyAsc || _sortBy == keyDesc;
    final bool isAsc = _sortBy == keyAsc;
    const Color activeColor = Colors.green; 

    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (isActive) ...[
            const SizedBox(width: 4),
            Icon(isAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: activeColor),
          ]
        ],
      ),
      selected: isActive,
      showCheckmark: false,
      selectedColor: activeColor.withOpacity(0.1),
      side: isActive ? const BorderSide(color: activeColor) : BorderSide(color: Colors.grey.withOpacity(0.3)),
      labelStyle: TextStyle(
        color: isActive ? activeColor : Colors.grey[700],
        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        fontSize: 13 // <--- Increased Font Size
      ),
      onSelected: (val) {
        if (isActive) {
          setState(() => _sortBy = isAsc ? keyDesc : keyAsc);
        } else {
          setState(() => _sortBy = defaultToDesc ? keyDesc : keyAsc);
        }
      },
      // Removed VisualDensity.compact to make buttons taller/larger
    );
  }

  Widget _buildProductionList() {
    if (manager == null || manager!.products.isEmpty) {
      return _buildEmptyState(Icons.precision_manufacturing_outlined, "No products defined.\nCreate a product to start manufacturing.");
    }

    return ListenableBuilder(
      listenable: manager!,
      builder: (context, _) {
        final userRole = manager!.user.role;
        final bool showMoney = userRole == 'owner' || userRole == 'business_admin';
        final bool isDark = Theme.of(context).brightness == Brightness.dark;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: manager!.products.length,
          itemBuilder: (ctx, i) {
            final p = manager!.products[i];
            
            // --- 1. CALCULATE TIER & STYLE ---
            int tierLevel = _resolveTier(p.name); 
            final style = _getTierStyle(tierLevel, isDark);
            final Color badgeColor = style['color'];

            // Financials
            double cost = p.getProductionCost(manager!.components);
            double margin = p.sellingPrice - cost;
            double marginPercent = p.sellingPrice > 0 ? (margin / p.sellingPrice) * 100 : 0.0;

            // Stock Check
            final matchingStock = manager!.components.firstWhere(
              (c) => c.name.toLowerCase() == p.name.toLowerCase(),
              orElse: () => Component(id: '', name: '', quantity: 0, minStock: 0, costPerUnit: 0.0),
            );
            final bool isTrackedInStock = matchingStock.id.isNotEmpty;
            final int currentStock = matchingStock.quantity;

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start, // Align to top
                      children: [
                        
                        // --- LEFT COLUMN (Badge + Undo) ---
                        Padding(
                          padding: const EdgeInsets.only(right: 12, top: 2),
                          child: Column(
                            children: [
                              // 1. BADGE (If applicable)
                              if (tierLevel > 1) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withOpacity(0.2), 
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: badgeColor.withOpacity(0.5))
                                  ),
                                  child: Text(
                                    style['label'], 
                                    style: TextStyle(color: badgeColor, fontSize: 8, fontWeight: FontWeight.bold)
                                  ),
                                ),
                                const SizedBox(height: 8), // Gap between badge and button
                              ],

                              // 2. UNDO BUTTON
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () async {
                                  if (manager != null) {
                                    bool s = await manager!.undoProduce(p.id);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(s ? "Production Undone" : "Nothing to undo"),
                                        duration: const Duration(milliseconds: 800)));
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
                                  child: const Icon(Icons.undo, color: Colors.orange, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // --- MIDDLE COLUMN (Name + Stock + Ingredients) ---
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Name & Stock Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.name, 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      // No overflow needed as much now, but safe to keep
                                      maxLines: 2, 
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isTrackedInStock ? kSecondaryColor : kPrimaryColor.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isTrackedInStock ? "STOCK: $currentStock" : "TOTAL: ${p.producedCount}",
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () => _showBottleneckDetails(p), // Opens the popup!
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _calculateMaxBuildable(p) > 0 ? Colors.blue.withOpacity(0.05) : Colors.red.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: _calculateMaxBuildable(p) > 0 ? Colors.blue.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                                      width: 1
                                    )
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _calculateMaxBuildable(p) > 0 ? Icons.check_circle_outline : Icons.block, 
                                        size: 12, 
                                        color: _calculateMaxBuildable(p) > 0 ? Colors.blue : Colors.red
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Max Buildable: ${_calculateMaxBuildable(p)} units",
                                        style: TextStyle(
                                          fontSize: 11, 
                                          fontWeight: FontWeight.bold,
                                          color: _calculateMaxBuildable(p) > 0 ? Colors.blue[800] : Colors.red[800]
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.info_outline, size: 12, color: _calculateMaxBuildable(p) > 0 ? Colors.blue : Colors.red)
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              
                              // Ingredients List
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: p.componentsNeeded.entries.map((e) {
                                  final compName = manager!.getComponent(e.key)?.name ?? "?";
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white10 : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!),
                                    ),
                                    child: Text(
                                      "$compName: ${e.value}",
                                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.grey[700], fontWeight: FontWeight.w500),
                                    ),
                                  );
                                }).toList(),
                              )
                            ],
                          ),
                        ),
                        
                        // --- RIGHT COLUMN (Edit Button) ---
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _showProductOptions(p),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.05), shape: BoxShape.circle),
                              child: const Icon(Icons.edit, color: kPrimaryColor, size: 20),
                            ),
                          ),
                        )
                      ],
                    ),

                    // Financials Footer
                    if (showMoney) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildFinanceItem("Cost", "\$${cost.toStringAsFixed(2)}", Colors.red[700]!),
                          _buildFinanceItem("Value", "\$${p.sellingPrice.toStringAsFixed(2)}", Colors.blue[700]!),
                          _buildFinanceItem("Profit", "\$${margin.toStringAsFixed(2)}", margin > 0 ? Colors.green[700]! : Colors.red),
                          _buildFinanceItem("Margin", "${marginPercent.toStringAsFixed(1)}%", Colors.grey[700]!),
                        ],
                      )
                    ]
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAuditLog() {
    if (manager == null) return const SizedBox.shrink();

    // 1. CHECK DARK MODE
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color titleColor = isDark ? Colors.white : Colors.black87;
    final Color detailsColor = isDark ? Colors.blue[200]! : kPrimaryColor; // Light Blue in Dark Mode
    final Color metaColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5')
          .collection('companies')
          .doc(manager!.user.companyId)
          .collection('logs')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get(),
      builder: (context, snapshot) {
        
        if (snapshot.connectionState == ConnectionState.waiting) {
           return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
           return Center(child: Text("Error loading history: ${snapshot.error}", style: TextStyle(color: metaColor)));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
           return _buildEmptyState(Icons.history, "No activity recorded yet.");
        }
        
        final logs = snapshot.data!.docs;
        
        return RefreshIndicator(
          onRefresh: () async { setState(() {}); },
          backgroundColor: isDark ? Colors.grey[800] : Colors.white,
          color: kSecondaryColor,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.grey[800] : Colors.grey[300]),
            itemBuilder: (context, index) {
               final logData = logs[index].data() as Map<String, dynamic>;
               
               final String action = logData['action'] ?? 'Unknown Action'; 
               final String details = logData['details'] ?? 'No details available.'; 
               final String actor = logData['actorEmail'] ?? 'Unknown User'; 
               
               String timeStr = "Unknown Time";
               final Timestamp? timestamp = logData['timestamp'] as Timestamp?;
               if (timestamp != null) { 
                 final dt = timestamp.toDate(); 
                 timeStr = "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}"; 
               }
               
               IconData icon = Icons.info_outline; 
               Color iconColor = Colors.grey;
               
               if (action.contains("Sale")) { icon = Icons.monetization_on; iconColor = Colors.green[700]!; } 
               else if (action.contains("Stock")) { icon = Icons.inventory; iconColor = Colors.blue; } 
               else if (action.contains("Created")) { icon = Icons.add_circle; iconColor = Colors.teal; } 
               else if (action.contains("Deleted")) { icon = Icons.delete; iconColor = Colors.red; } 
               else if (action.contains("Production")) { icon = Icons.build; iconColor = kAccentColor; } 
               else if (action.contains("Role")) { icon = Icons.security; iconColor = Colors.purple; }
               
               return ListTile(
                 contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                 leading: CircleAvatar(
                   backgroundColor: iconColor.withOpacity(0.1), 
                   child: Icon(icon, color: iconColor, size: 20)
                 ), 
                 title: Text(
                   action, 
                   style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: titleColor) // <--- FIXED
                 ), 
                 subtitle: Column(
                   crossAxisAlignment: CrossAxisAlignment.start, 
                   children: [
                     const SizedBox(height: 4),
                     Text(
                       details, 
                       style: TextStyle(color: detailsColor, fontSize: 13) // <--- FIXED
                     ), 
                     const SizedBox(height: 4),
                     Row(
                       children: [
                         Icon(Icons.person_outline, size: 12, color: metaColor),
                         const SizedBox(width: 4),
                         Flexible(
                           child: Text(
                             "$actor â€¢ $timeStr", 
                             style: TextStyle(fontSize: 11, color: metaColor), // <--- FIXED
                             overflow: TextOverflow.ellipsis
                           )
                         ),
                       ],
                     )
                   ]
                 )
               );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String msg) {
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: MediaQuery.of(context).size.height * 0.35), Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 64, color: Colors.grey[300]), const SizedBox(height: 16), Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500]))]))]);
  }

  // ðŸ“Š CALCULATE DAYS OF SUPPLY (The Brain)
  Future<Map<String, int>> _calculateDaysOfSupply() async {
    if (manager == null) return {};

    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
    
    // We look at 'sales' of products to infer component usage
    final salesQuery = await db.collection('companies')
        .doc(manager!.user.companyId)
        .collection('sales')
        .where('date', isGreaterThan: Timestamp.fromDate(thirtyDaysAgo))
        .get();

    Map<String, double> usageMap = {};

    for (var doc in salesQuery.docs) {
      final data = doc.data();
      final String pName = data['productName'] ?? "";
      final int qty = data['quantity'] ?? 0;
      
      if (pName.isNotEmpty && qty > 0) {
        // 1. Direct Usage (This product was sold)
        usageMap[pName] = (usageMap[pName] ?? 0) + qty;

        // 2. Component Usage (Deduct ingredients based on BOM)
        try {
          final productDef = manager!.products.firstWhere((p) => p.name == pName);
          for (var entry in productDef.componentsNeeded.entries) {
             final comp = manager!.getComponent(entry.key);
             if (comp != null) {
               usageMap[comp.name] = (usageMap[comp.name] ?? 0) + (qty * entry.value);
             }
          }
        } catch (_) {} 
      }
    }

    Map<String, int> daysSupply = {};
    
    // Calculate for every component currently in stock
    for (var comp in manager!.components) {
      final double totalUsed30Days = usageMap[comp.name] ?? 0;
      if (totalUsed30Days == 0) {
        daysSupply[comp.name] = 999; // Infinite/Safe
      } else {
        double dailyRate = totalUsed30Days / 30.0;
        int days = (comp.quantity / dailyRate).floor();
        daysSupply[comp.name] = days;
      }
    }
    
    return daysSupply;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    // 1. DATA SOURCE: Use _latestProfile (Live) for structure
    final bool hasNoOrg = _latestProfile?.companyId.isEmpty ?? true;
    final bool isBanned = _latestProfile?.role == 'inactive';
    final bool isInactive = isBanned || hasNoOrg;
    
    // Permission checks
    final bool isOwner = !isInactive && (_latestProfile?.role == 'owner');
    final bool canManageStock = !isInactive && (
      _latestProfile?.role == 'owner' || 
      _latestProfile?.role == 'manager' || 
      _latestProfile?.role == 'business_admin'
    );
    final bool canManageTeam = !isInactive && (
      isOwner || _latestProfile?.role == 'business_admin'
    );

    // --- 2. HYBRID STATUS LOGIC (UPDATED FOR PER-ORG) ---
    // We now check if the CURRENT COMPANY is Pro.
    final bool effectiveIsPro = manager?.isCurrentCompanyPro ?? false;

    String statusLabel = "MEMBER"; 
    bool isTrialActive = false;
    Color statusColor = Colors.blueGrey[400]!;
    
    if (!isInactive) {
      if (effectiveIsPro) {
        // If Company is Pro (Paid or Debug), show PRO immediately
        statusLabel = "PREMIUM";
        statusColor = const Color.fromARGB(255, 27, 209, 88);
      } else if (isOwner) { 
        // Read the date from the LIVE profile
        final DateTime? created = _latestProfile?.createdAt;

        if (created != null) {
          final trialExpiry = created.add(const Duration(days: 7));
          final now = DateTime.now();
          
          if (now.isBefore(trialExpiry)) {
            final daysLeft = trialExpiry.difference(now).inDays + 1;
            statusLabel = "PRO TRIAL [$daysLeft DAYS]";
            statusColor = Colors.orange[800]!;
            isTrialActive = true;
          } else {
            statusLabel = "FREE PLAN";
            statusColor = Colors.grey[600]!;
          }
        } else {
          // If date is completely missing, default to 7 days
          statusLabel = "PRO TRIAL"; 
          statusColor = Colors.orange[800]!;
          isTrialActive = true;
        }
      } else {
        statusLabel = _latestProfile?.role.toUpperCase() ?? "USER"; 
      }
    }

    // 3. Stock Logic
    int lowStockCount = 0;
    if (!isInactive && manager != null) {
      lowStockCount = manager!.components.where((c) => c.quantity <= c.minStock).length;
    }

    // --- DEFINE TABS ---
    final destinations = [
      const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stock'),
      const NavigationDestination(icon: Icon(Icons.factory_outlined), selectedIcon: Icon(Icons.factory), label: 'Production'),
      
      // ðŸ‘‡ NEW TASK TAB ADDED HERE (Index 2)
      const NavigationDestination(icon: Icon(Icons.check_circle_outline), selectedIcon: Icon(Icons.check_circle), label: 'Tasks'),
      
      if (canManageStock)
        const NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: 'Orders'),
      if (canManageStock) 
        const NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.manage_history), label: 'History'),
    ];

    final List<Widget> pages = [
      RefreshIndicator(onRefresh: _refresh, backgroundColor: Colors.white, color: kSecondaryColor, child: _buildInventoryList()),
      RefreshIndicator(onRefresh: _refresh, backgroundColor: Colors.white, color: kSecondaryColor, child: _buildProductionList()),
      
      // ðŸ‘‡ NEW TASK PAGE ADDED HERE (Index 2)
      RefreshIndicator(onRefresh: _refresh, backgroundColor: Colors.white, color: kSecondaryColor, child: _buildTaskList()),
      
      if (canManageStock) RefreshIndicator(onRefresh: _refresh, backgroundColor: Colors.white, color: kSecondaryColor, child: _buildPurchaseOrderList()),
      if (canManageStock) _buildAuditLog()
    ];

    final int safeIndex = (_selectedIndex >= destinations.length) ? 0 : _selectedIndex;

    return Scaffold(
      appBar: AppBar(
        // --- PRO BRANDING TITLE ---
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min, // Keeps it centered nicely
            children: [
              Icon(Icons.layers, size: 20), // Brand Icon
              SizedBox(width: 8),
              Text(
                'PRODUCTION PRO', // Short, Uppercase, Premium
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.w900, // Extra Bold
                  letterSpacing: 1.5, // The "Premium" look
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        
        // --- EXISTING ACTIONS (Kept exactly the same) ---
        actions: [
          _buildNotificationBell(),
          if (!isInactive && canManageStock)
            Stack(children: [
              IconButton(icon: const Icon(Icons.warning_amber), tooltip: 'Low Stock Alerts', onPressed: _showLowStockDialog),
              if (lowStockCount > 0) Positioned(right: 8, top: 8, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), constraints: const BoxConstraints(minWidth: 16, minHeight: 16), child: Text('$lowStockCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)))
            ]),
          if (!isInactive && canManageStock)
            IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan Item', onPressed: _scanBarcode),
          Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu), tooltip: 'Open Menu', onPressed: () => Scaffold.of(context).openEndDrawer())),
          const SizedBox(width: 8),
        ],
      ),

      endDrawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(color: kPrimaryColor),
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 30,
                              child: Text(
                                (_latestProfile?.displayName.isNotEmpty == true ? _latestProfile!.displayName[0] : "U").toUpperCase(),
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kPrimaryColor),
                              ),
                            ),
                            if (!hasNoOrg && manager != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text("Switch Org", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                                  PopupMenuButton<CompanyMembership>(
                                    icon: const Icon(Icons.arrow_drop_down_circle_outlined, color: Colors.white, size: 28),
                                    tooltip: "Switch Organization",
                                    offset: const Offset(0, 40),
                                    onSelected: (membership) {
                                      Navigator.pop(context);
                                      if (membership.companyId == 'CREATE_NEW') {
                                        _showCreateOrgDialog();
                                      } else if (membership.companyId == 'JOIN_EXISTING') {
                                        _showJoinOrgDialog();
                                      } else {
                                        manager!.switchOrganization(membership);
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Switching to ${membership.companyName}...")));
                                      }
                                    },
                                    itemBuilder: (context) {
                                      List<PopupMenuEntry<CompanyMembership>> items = [];
                                      items.addAll(manager!.user.memberships.map((m) {
                                        bool isActive = m.companyId == manager!.user.companyId;
                                        return PopupMenuItem(
                                          value: m,
                                          child: Row(children: [
                                            Icon(isActive ? Icons.radio_button_checked : Icons.radio_button_off, color: isActive ? kSecondaryColor : Colors.grey, size: 18),
                                            const SizedBox(width: 12),
                                            Expanded(child: Text(m.companyName, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis))
                                          ]),
                                        );
                                      }));
                                      items.add(const PopupMenuDivider());
                                      items.add(PopupMenuItem(value: CompanyMembership(companyId: 'CREATE_NEW', companyName: '', role: ''), child: const Row(children: [Icon(Icons.add_business, color: kSecondaryColor), SizedBox(width: 12), Text("Create New Org", style: TextStyle(color: kSecondaryColor, fontWeight: FontWeight.bold))])));
                                      items.add(PopupMenuItem(value: CompanyMembership(companyId: 'JOIN_EXISTING', companyName: '', role: ''), child: const Row(children: [Icon(Icons.group_add, color: Colors.blue), SizedBox(width: 12), Text("Join Existing Org", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))])));
                                      return items;
                                    },
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const Spacer(),
                        Text(_latestProfile?.displayName ?? "User", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(child: Text(_latestProfile?.email ?? "", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13), overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 12),
                            if (!hasNoOrg && manager != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      manager!.user.memberships.firstWhere((m) => m.companyId == manager!.user.companyId, orElse: () => CompanyMembership(companyId: '', companyName: 'ORG', role: '')).companyName.toUpperCase(),
                                      style: const TextStyle(fontSize: 10, color: kAccentColor, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                    ),
                                    if (canManageTeam) ...[
                                      const SizedBox(width: 4),
                                      InkWell(onTap: () => _showRenameOrgDialog(), child: const Icon(Icons.edit, size: 12, color: kAccentColor)),
                                    ]
                                  ],
                                ),
                              )
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (manager != null)
                    ListTile(
                      leading: const Icon(Icons.settings, color: Colors.grey),
                      title: const Text("Account Settings"),
                      onTap: () {
                        Navigator.pop(context); 
                        Navigator.push(context, MaterialPageRoute(builder: (_) => UserOptionsScreen(manager: manager!)));
                      },
                    ),
            
                  if (!isInactive && manager != null) ...[
                    if (canManageStock) 
                      ListTile(
                        // âœ… FIX: Use white or teal depending on theme
                        leading: Icon(Icons.group_add, color: isDark ? Colors.tealAccent : kPrimaryColor), 
                        title: const Text("Invite Staff"), 
                        subtitle: const Text("Get join codes"), 
                        onTap: () { Navigator.pop(context); _showInviteCode(); }
                      ),

                    if (canManageTeam) 
                      ListTile(
                        // âœ… FIX: Use white or teal depending on theme
                        leading: Icon(Icons.people_alt_outlined, color: isDark ? Colors.tealAccent : kPrimaryColor), 
                        title: const Text("Manage Team"), 
                        subtitle: const Text("Roles & Permissions"), 
                        onTap: () { Navigator.pop(context); _showTeamDialog(); }
                      ),
                    const Divider(),

                    if (canManageStock)
                      ListTile(leading: const Icon(Icons.upload_file, color: Colors.blue), title: const Text("Bulk Import CSV"), subtitle: const Text("Auto-detects columns"), onTap: () { Navigator.pop(context); _importCSV(); }),

                    if (canManageTeam)
                      ListTile(
                        leading: const Icon(Icons.bar_chart, color: kSecondaryColor),
                        title: const Text("Reports & Analytics"),
                        // FIX: Logic now respects effectiveIsPro (the button) OR trial logic
                        subtitle: Text((isTrialActive || effectiveIsPro) ? "ACCESS GRANTED" : "Sales & Profit", style: TextStyle(color: (isTrialActive || effectiveIsPro) ? Colors.green : Colors.grey)),
                        trailing: (isTrialActive || effectiveIsPro) ? const Icon(Icons.lock_open, size: 16, color: Colors.green) : const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(context);
                          if (isOwner && (isTrialActive || effectiveIsPro)) {
                             Navigator.push(context, MaterialPageRoute(builder: (_) => ReportsScreen(manager: manager!)));
                          } else if (!isOwner) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Only the Business Owner can access Reports.")));
                          } else {
                            _showPaywallDialog("Advanced Analytics", 0);
                          }
                        },
                      ),
                      
                    if (canManageTeam) 
                      ListTile(
                        leading: Icon(effectiveIsPro ? Icons.verified : Icons.workspace_premium, color: effectiveIsPro ? kSecondaryColor : Colors.orange[800]),
                        title: const Text("Subscription & Limits"),
                        subtitle: Text(effectiveIsPro ? "Manage Plan" : "Upgrade to Pro", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => SubscriptionScreen(manager: manager!)));
                        },
                      ),
                  ],

                  const Divider(height: 1),
                  ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text("Sign Out", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), onTap: () async { Navigator.pop(context); await FirebaseAuth.instance.signOut(); }),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
      
      body: Column(
        children: [
          // FIX: Pass the correct label/color calculated above
          _buildUserHeader(statusLabel, statusColor),
          Expanded(
            child: isInactive 
              ? Center(
                  child: (_latestProfile?.memberships.isEmpty ?? true)
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.business, size: 64, color: kPrimaryColor)),
                          const SizedBox(height: 24),
                          const Text("No Organization Selected", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text("Create a new workspace or join an existing team.", style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(onPressed: _showJoinOrgDialog, icon: const Icon(Icons.group_add), label: const Text("Join Team"), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(onPressed: _showCreateOrgDialog, icon: const Icon(Icons.add_business), label: const Text("Create New"), style: ElevatedButton.styleFrom(backgroundColor: kSecondaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
                            ],
                          )
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_person, size: 64, color: Colors.grey),
                          const SizedBox(height: 24),
                          const Text("Access Deactivated", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text("Your access to this organization has been revoked.", style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          const Text("Use the menu (top right) to switch organizations.", style: TextStyle(color: kSecondaryColor, fontWeight: FontWeight.bold)),
                        ]
                      ),
                )
              : PageView(controller: _pageController, onPageChanged: (index) { setState(() { _selectedIndex = index; }); }, children: pages),
          )
        ]
      ),
      
      floatingActionButton: !isInactive && safeIndex != 4 
              ? FloatingActionButton(
                  onPressed: () { 
                    if (safeIndex == 0) { _showAddStockChoice(); } 
                    else if (safeIndex == 1) { _showAddProduct(); } 
                    else if (safeIndex == 2) { _showAddTaskDialog(); } // ðŸ‘ˆ Opens Task Dialog
                    else if (safeIndex == 3) { _showCreatePODialog(); } 
                  }, 
                  child: Icon(
                    safeIndex == 0 ? Icons.add_box : 
                    safeIndex == 1 ? Icons.add_business : 
                    safeIndex == 2 ? Icons.playlist_add : // ðŸ‘ˆ Icon for tasks
                    Icons.post_add
                  )
                ) 
              : null,

      bottomNavigationBar: isInactive 
        ? null 
        : NavigationBar(
            selectedIndex: safeIndex, 
            onDestinationSelected: (i) {
              setState(() => _selectedIndex = i);
              _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
            }, 
            backgroundColor: Theme.of(context).cardColor, 
            indicatorColor: const Color.fromARGB(255, 15, 148, 137).withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 1 : 0.2
            ),
            surfaceTintColor: Colors.transparent, 
            elevation: 3, 
            destinations: destinations
          ),
    );
  }

  // 1. THE LOGIC HANDLER
  Future<void> _respondToInvite(String inviteId, bool accept, Map<String, dynamic> data) async {
    // Dismiss the dialog first
    // (Navigator.pop is handled in the UI button, so we don't need it here)
    
    if (accept) {
      // Reuse your existing logic which is already perfect (handles transaction + profile update)
      await _acceptInvite(inviteId, data);
    } else {
      // Handle Decline (Just delete the invite)
      try {
        await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5')
            .collection('invitations').doc(inviteId).delete();
            
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invitation declined."))
          );
        }
      } catch (e) {
        print("Error declining: $e");
      }
    }
  }

  // 2. THE PROFESSIONAL DIALOG UI
  void _showProfessionalInviteDialog(String inviteId, Map<String, dynamic> inviteData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.business_center_rounded, size: 48, color: kPrimaryColor),
                ),
                const SizedBox(height: 24),
                const Text("Team Invitation", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87, fontSize: 16, height: 1.4),
                    children: [
                      const TextSpan(text: "You have been invited to join\n"),
                      TextSpan(
                        text: inviteData['companyName'] ?? 'a Company',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimaryColor, fontSize: 18)
                      ),
                      const TextSpan(text: "\nas a "),
                      TextSpan(
                        text: (inviteData['role'] ?? 'Staff').toString().toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)
                      ),
                      const TextSpan(text: "."),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () {
                          Navigator.pop(ctx); // Close Dialog
                          _respondToInvite(inviteId, false, inviteData); // Decline
                        },
                        child: Text("Decline", style: TextStyle(color: Colors.grey[600])),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: kPrimaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () {
                          Navigator.pop(ctx); // Close Dialog
                          _respondToInvite(inviteId, true, inviteData); // Accept
                        },
                        child: const Text("Join Team", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper to get color and label based on complexity
  Map<String, dynamic> _getTierStyle(int tier, bool isDark) {
    switch (tier) {
      case 5: // Legendary Logic -> Now looks like TIER 2 (Teal/Green)
        return {
          'color': isDark ? const Color(0xFF34D399) : const Color(0xFF0F766E), // Teal
          'bg': isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
          'label': 'TIER 5'
        };
      case 4: // Epic / Complex Assembly (Unchanged Deep Purple)
        return {
          'color': isDark ? const Color(0xFFC084FC) : const Color(0xFF9333EA),
          'bg': isDark ? const Color(0xFF3B0764) : const Color(0xFFFAF5FF),
          'label': 'TIER 4'
        };
      case 3: // Assembly Logic -> Now looks like TIER 5 (Gold/Amber)
        return {
          'color': isDark ? const Color(0xFFFFD700) : const Color(0xFFF59E0B), // Gold
          'bg': isDark ? const Color(0xFF422006) : const Color(0xFFFFFBEB),
          'label': 'TIER 3'
        };
      case 2: // Simple Product Logic -> Now looks like TIER 3 (Your Custom Purple)
        return {
          'color': isDark ? const Color.fromARGB(255, 193, 139, 212) : const Color(0xFF7C3AED), 
          'bg': isDark ? const Color(0xFF4C3E72).withOpacity(0.2) : const Color(0xFFF9F7FF),
          'label': 'TIER 2'
        };
      default: // Common / Raw Material
        return {
          'color': isDark ? Colors.grey[400] : Colors.grey[700],
          'bg': isDark ? const Color(0xFF1E1E1E) : Colors.white,
          'label': ''
        };
    }
  }

  // ðŸ§  RECURSIVE TIER CALCULATOR (Paste this at the bottom of your State class)
  int _resolveTier(String itemName, {int depth = 0}) {
    if (manager == null) return 1;
    if (depth > 6) return 1; // Safety brake for circular recipes

    // 1. Is this item a Product?
    final productIndex = manager!.products.indexWhere((p) => p.name == itemName);
    if (productIndex == -1) return 1; // Not a product -> Tier 1

    // 2. Check its ingredients
    final product = manager!.products[productIndex];
    int maxChildTier = 0; 

    for (String compId in product.componentsNeeded.keys) {
      final comp = manager!.getComponent(compId);
      if (comp != null) {
        // Recursive Call
        int t = _resolveTier(comp.name, depth: depth + 1);
        if (t > maxChildTier) maxChildTier = t;
      }
    }
    return maxChildTier + 1; 
  }
}

