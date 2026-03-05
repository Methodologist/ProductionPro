import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants.dart';
import '../../controllers/inventory_controller.dart';
class ReportsScreen extends StatefulWidget {
  final InventoryManager manager;
  const ReportsScreen({super.key, required this.manager});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _timeFilter = 'Week';

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : kPrimaryColor;

    // 1. Calculate Inventory Assets
    double rawMaterialValue = widget.manager.components.fold(0, (sum, c) => sum + (c.quantity * c.costPerUnit));
    double finishedGoodsValue = widget.manager.products.fold(0, (sum, p) {
      double cost = p.getProductionCost(widget.manager.components);
      return sum + (p.producedCount * cost);
    });
    double totalAssetValue = rawMaterialValue + finishedGoodsValue;

    return Scaffold(
      // Standard Scaffold background handles light/dark transitions automatically
      appBar: AppBar(
        title: const Text("Analytics & Reports"),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.download), tooltip: "Export CSV", onPressed: _exportToCSV),
          const SizedBox(width: 8)
        ],
      ),
      body: Column(
        children: [
          // --- TIME FILTER BAR ---
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: isDark ? Colors.transparent : Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ['Today', 'Week', 'Month', 'All'].map((filter) {
                  final bool isSelected = _timeFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: isSelected,
                      selectedColor: kSecondaryColor,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                      ),
                      onSelected: (val) { if (val) setState(() => _timeFilter = filter); }
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getSalesStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text("Error loading data"));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                final docs = snapshot.data!.docs;
                double totalRevenue = 0;
                double totalProfit = 0;
                Map<String, double> chartData = {};
                Map<String, double> productSales = {};
                Map<String, double> userSales = {};

                for (var doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final double rev = (data['totalRevenue'] ?? 0).toDouble();
                  final double prof = (data['totalProfit'] ?? 0).toDouble();
                  final String pName = data['productName'] ?? 'Unknown';
                  final String user = data['soldBy']?.split('@')[0] ?? 'Unknown';
                  
                  totalRevenue += rev;
                  totalProfit += prof;

                  final Timestamp? ts = data['date'] as Timestamp?;
                  if (ts != null) {
                    final date = ts.toDate();
                    String key = "${date.month}/${date.day}";
                    if (_timeFilter == 'Today') key = "${date.hour}:00";
                    chartData[key] = (chartData[key] ?? 0) + rev;
                  }
                  productSales[pName] = (productSales[pName] ?? 0) + rev;
                  userSales[user] = (userSales[user] ?? 0) + rev;
                }

                double margin = totalRevenue > 0 ? (totalProfit / totalRevenue) * 100 : 0.0;
                double avgOrderValue = docs.isNotEmpty ? totalRevenue / docs.length : 0.0;
                var sortedProducts = productSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. ASSET VALUE HEADER (Gradients for Premium feel)
                      if (_timeFilter == 'All')
                        _buildAssetCard(totalAssetValue, rawMaterialValue, finishedGoodsValue),

                      // 2. KPI GRID (2x2)
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.4,
                        children: [
                          _buildStatCard("Total Revenue", totalRevenue, Colors.blue, icon: Icons.attach_money, isDark: isDark),
                          _buildStatCard("Net Profit", totalProfit, totalProfit >= 0 ? Colors.greenAccent : Colors.redAccent, icon: Icons.trending_up, isDark: isDark),
                          _buildStatCard("Avg Margin", margin, Colors.purpleAccent, isPercent: true, icon: Icons.pie_chart, isDark: isDark),
                          _buildStatCard("Order Average", avgOrderValue, Colors.orangeAccent, icon: Icons.shopping_bag, isDark: isDark),
                        ],
                      ),

                      const SizedBox(height: 24),
                      _buildSectionTitle("Revenue Trend", isDark),
                      _buildModernContainer(
                        isDark,
                        height: 220,
                        child: _buildCustomBarChart(chartData, isDark),
                      ),

                      const SizedBox(height: 24),
                      _buildSectionTitle("Top Selling Products", isDark),
                      _buildModernContainer(
                        isDark,
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sortedProducts.take(5).length,
                          separatorBuilder: (_,__) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey[200]),
                          itemBuilder: (context, index) {
                            final entry = sortedProducts[index];
                            final double percentage = totalRevenue > 0 ? (entry.value / totalRevenue) : 0.0;
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                backgroundColor: kSecondaryColor.withOpacity(0.2),
                                child: Text("${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold, color: kSecondaryColor)),
                              ),
                              title: Text(entry.key, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                              subtitle: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(value: percentage, minHeight: 4, backgroundColor: isDark ? Colors.white10 : Colors.grey[100], color: kSecondaryColor),
                              ),
                              trailing: Text("\$${entry.value.toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
                            );
                          },
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      if (userSales.isNotEmpty) ...[
                        _buildSectionTitle("Staff Contribution", isDark),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: userSales.entries.map((e) => Chip(
                            label: Text("${e.key}: \$${e.value.toStringAsFixed(0)}"),
                            backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                          )).toList(),
                        ),
                      ],
                      const SizedBox(height: 50),
                    ],
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }

  // --- PRIVATE HELPER WIDGETS ---

  Widget _buildAssetCard(double total, double raw, double finished) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF0F172A)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("TOTAL INVENTORY VALUE", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text("\$${total.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildAssetMini("Raw", raw, Colors.blue),
              const SizedBox(width: 16),
              _buildAssetMini("Finished", finished, kSecondaryColor),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAssetMini(String label, double val, Color col) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text("$label: \$${val.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildStatCard(String title, double value, Color color, {bool isPercent = false, IconData? icon, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? Colors.white54 : Colors.grey[600])),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              isPercent ? "${value.toStringAsFixed(1)}%" : "\$${value.toStringAsFixed(0)}",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildModernContainer(bool isDark, {required Widget child, double? height}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
    );
  }

  Widget _buildCustomBarChart(Map<String, double> data, bool isDark) {
    if (data.isEmpty) return const Center(child: Text("No Sales Data", style: TextStyle(color: Colors.grey)));
    double maxVal = data.values.fold(0, (max, v) => v > max ? v : max);
    if (maxVal == 0) maxVal = 1;
    final keys = data.keys.toList();
    final displayKeys = keys.length > 7 ? keys.sublist(keys.length - 7) : keys;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: displayKeys.map((key) {
          final value = data[key]!;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 14,
                height: 120 * (value / maxVal),
                decoration: BoxDecoration(
                  color: kSecondaryColor,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [if(isDark) BoxShadow(color: kSecondaryColor.withOpacity(0.3), blurRadius: 8)]
                ),
              ),
              const SizedBox(height: 8),
              Text(key, style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black54)),
            ],
          );
        }).toList(),
      ),
    );
  }

  // --- LOGIC FUNCTIONS (Kept from original) ---

  Future<void> _exportToCSV() async {
    try {
      final salesQuery = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5')
          .collection('companies')
          .doc(widget.manager.user.companyId)
          .collection('sales')
          .orderBy('date', descending: true)
          .get();

      if (salesQuery.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export.")));
        return;
      }

      List<List<dynamic>> rows = [];
      rows.add(["Date", "Product Name", "Quantity", "Unit Cost", "Unit Price", "Total Revenue", "Total Profit", "Sold By"]);

      for (var doc in salesQuery.docs) {
        final data = doc.data();
        final Timestamp? ts = data['date'] as Timestamp?;
        final dateStr = ts != null ? ts.toDate().toIso8601String().split('T')[0] : "";
        
        rows.add([
          dateStr,
          data['productName'] ?? "Unknown",
          data['quantity'] ?? 0,
          data['unitCost'] ?? 0.00,
          data['unitPrice'] ?? 0.00,
          data['totalRevenue'] ?? 0.00,
          data['totalProfit'] ?? 0.00,
          data['soldBy'] ?? "System"
        ]);
      }

      String csvData = const ListToCsvConverter().convert(rows);
      final directory = await getTemporaryDirectory();
      final path = "${directory.path}/sales_report_${DateTime.now().millisecondsSinceEpoch}.csv";
      final file = File(path);
      await file.writeAsString(csvData);
      
      final xFile = XFile(path, mimeType: 'text/csv');
      await Share.shareXFiles([xFile], text: 'Production Pro - Report', subject: 'Production Pro - Report');
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export failed: $e"), backgroundColor: Colors.red));
    }
  }

  Stream<QuerySnapshot> _getSalesStream() {
    Query query = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'east-5')
        .collection('companies')
        .doc(widget.manager.user.companyId)
        .collection('sales')
        .orderBy('date', descending: true);

    DateTime now = DateTime.now();
    DateTime? start;

    if (_timeFilter == 'Today') {
      start = DateTime(now.year, now.month, now.day);
    } else if (_timeFilter == 'Week') {
      start = now.subtract(const Duration(days: 7));
    } else if (_timeFilter == 'Month') {
      start = DateTime(now.year, now.month, 1);
    }
    
    if (start != null) {
      query = query.where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    }

    return query.snapshots();
  }
}

// --- SUBSCRIPTION & BILLING SCREEN (RevenueCat Integrated) ---
