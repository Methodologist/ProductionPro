import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../constants.dart';
import '../../models/models.dart';
import '../../controllers/inventory_controller.dart';
class UserOptionsScreen extends StatefulWidget {
  final InventoryManager manager;
  const UserOptionsScreen({super.key, required this.manager});

  @override
  State<UserOptionsScreen> createState() => _UserOptionsScreenState();
}

class _UserOptionsScreenState extends State<UserOptionsScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.manager.user.displayName;
  }

  Future<void> _updateName() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5')
          .collection('users').doc(widget.manager.user.uid).update({'displayName': _nameCtrl.text.trim()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name updated!")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- ACTION: Leave Organization (Fixed Role Update) ---
  Future<void> _leaveOrganization(String companyId, String role) async {
    if (role == 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Owners cannot leave. Transfer ownership or delete the organization."))
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text("Leave Organization?", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
        content: Text("You will lose access to this inventory. You will need a new invite to rejoin.", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Leave", style: TextStyle(color: Colors.red))),
        ],
      )
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);

    try {
      final uid = widget.manager.user.uid;
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5');
      final userRef = db.collection('users').doc(uid);
      
      String nextOrgName = "";
      bool didSwitch = false;

      await db.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        if (!snapshot.exists) throw Exception("User profile not found");

        final data = snapshot.data()!;
        
        // 1. Prepare Lists
        List<dynamic> memberships = List.from(data['memberships'] ?? []);
        List<dynamic> connectedIds = List.from(data['connectedCompanyIds'] ?? []);

        // 2. Remove the target organization
        memberships.removeWhere((m) => m['companyId'] == companyId);
        connectedIds.remove(companyId);

        // 3. Handle Active Company Switch
        String currentActiveId = data['companyId'] ?? '';
        String newActiveId = currentActiveId;
        String newActiveRole = data['role'] ?? 'user'; // Default to existing

        // If we are removing the ONE we are currently looking at
        if (currentActiveId == companyId) {
          didSwitch = true;
          if (memberships.isNotEmpty) {
            // Pick the first available one
            final nextOne = memberships.first;
            newActiveId = nextOne['companyId'];
            nextOrgName = nextOne['companyName'];
            newActiveRole = nextOne['role']; // <--- CRITICAL FIX: GET NEW ROLE
          } else {
            // No organizations left
            newActiveId = ''; 
            newActiveRole = 'inactive'; // <--- Set to inactive if no orgs
            nextOrgName = "No Organization";
          }
        }

        // 4. Commit to Database
        transaction.update(userRef, {
          'memberships': memberships,
          'connectedCompanyIds': connectedIds,
          'companyId': newActiveId,
          'role': newActiveRole, // <--- UPDATE THE ROLE FIELD
        });
      });

      if (mounted) {
        Navigator.pop(context); // Close Settings Screen
        
        if (didSwitch) {
           if (nextOrgName == "No Organization") {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text("You have left the organization."))
             );
           } else {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text("Switched to $nextOrgName"),
                 backgroundColor: kSecondaryColor,
                 duration: const Duration(seconds: 4),
               )
             );
           }
        } else {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text("Left organization successfully."))
           );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine current brightness to set text colors
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = Theme.of(context).cardColor;
    final Color textColor = isDark ? Colors.white70 : Colors.grey;

    return Scaffold(
      // Remove hardcoded backgroundColor so it uses the Theme's scaffoldBackgroundColor
      appBar: AppBar(title: const Text("Account Settings"), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("MY PROFILE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              // Use Theme Card Color
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: kPrimaryColor,
                    radius: 24,
                    child: Text(widget.manager.user.displayName.isNotEmpty ? widget.manager.user.displayName[0].toUpperCase() : "?", style: const TextStyle(color: Colors.white, fontSize: 20)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      // Remove border: InputBorder.none to let the Theme handle it, OR keep it if you want a clean look
                      decoration: const InputDecoration(labelText: "Display Name", border: InputBorder.none, filled: false),
                    ),
                  ),
                  IconButton(
                    icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save, color: kPrimaryColor),
                    onPressed: _updateName,
                  )
                ],
              ),
            ),
            
            const SizedBox(height: 32),

            Text("MY ORGANIZATIONS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: widget.manager.user.memberships.map((mem) {
                  final bool isCurrent = mem.companyId == widget.manager.user.companyId;
                  return ListTile(
                    title: Text(mem.companyName, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text(mem.role.toUpperCase(), style: const TextStyle(fontSize: 10)),
                    trailing: mem.role == 'owner' 
                      ? const Chip(label: Text("OWNER"), backgroundColor: Colors.grey, labelStyle: TextStyle(fontSize: 10, color: Colors.white))
                      : TextButton(onPressed: () => _leaveOrganization(mem.companyId, mem.role), child: const Text("Leave", style: TextStyle(color: Colors.red))),
                  );
                }).toList(),
              ),
            ),
            
            const SizedBox(height: 32),

            Text("PREFERENCES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (context, mode, child) {
                  return SwitchListTile(
                    title: const Text("Dark Mode"),
                    secondary: Icon(
                      mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode, 
                      color: mode == ThemeMode.dark ? Colors.purple[200] : Colors.amber
                    ),
                    value: mode == ThemeMode.dark,
                    onChanged: (bool isOn) {
                      themeNotifier.value = isOn ? ThemeMode.dark : ThemeMode.light;
                    },
                  );
                },
              ),
            ),
            
            const SizedBox(height: 40),
            Center(child: Text("Version 1.0.0", style: TextStyle(color: textColor))),
            const SizedBox(height: 8),
            Center(
               child: TextButton(
                 onPressed: () async {
                   Navigator.pop(context);
                   await FirebaseAuth.instance.signOut();
                 }, 
                 child: const Text("Log Out", style: TextStyle(color: Colors.red))
               )
            )
          ],
        ),
      ),
    );
  }
}
