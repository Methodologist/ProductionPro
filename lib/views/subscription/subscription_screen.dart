import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../constants.dart';
import '../../controllers/inventory_controller.dart';
class SubscriptionScreen extends StatefulWidget {
  final InventoryManager manager;
  const SubscriptionScreen({super.key, required this.manager});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isLoading = true;
  Offerings? _offerings;

  @override
  void initState() {
    super.initState();
    _fetchOfferings();
  }

  Future<void> _fetchOfferings() async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final offerings = await Purchases.getOfferings();
      if (mounted) {
        setState(() {
          _offerings = offerings;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching offerings: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _makePurchase(Package package) async {
    setState(() => _isLoading = true);
    try {
      var result = await Purchases.purchase(
        PurchaseParams.package(package)
      );
      CustomerInfo info = (result as dynamic).customerInfo;
      _handleCustomerInfo(info);
    } catch (e) {
      print("Purchase error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      CustomerInfo customerInfo = await Purchases.restorePurchases();
      _handleCustomerInfo(customerInfo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Purchases restored successfully."))
        );
      }
    } catch (e) {
      print("Restore failed: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleCustomerInfo(CustomerInfo info) {
    if (info.entitlements.all["pro"]?.isActive == true) {
      widget.manager.activateProAccess();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Welcome to Pro! Premium features unlocked."), backgroundColor: Colors.green)
        );
        Navigator.pop(context); 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : kPrimaryColor;

    return ListenableBuilder(
      listenable: widget.manager,
      builder: (context, child) {
        // 1. Check Paid Pro Status
        final bool isPro = widget.manager.isCurrentCompanyPro;

        // 2. Check Trial Status (Same logic as Dashboard)
        bool isTrial = false;
        int daysLeft = 0;
        final DateTime? created = widget.manager.user.createdAt; // This holds the Company Date now
        
        if (!isPro) {
          if (created != null) {
            final trialExpiry = created.add(const Duration(days: 7));
            if (DateTime.now().isBefore(trialExpiry)) {
              isTrial = true;
              daysLeft = trialExpiry.difference(DateTime.now()).inDays + 1;
            }
          } else {
            // Safety: If date is missing, assume trial to be nice
            isTrial = true;
            daysLeft = 7;
          }
        }
        
        // 3. Determine Colors & Text based on status
        List<Color> gradientColors;
        String badgeText;
        String titleText;
        String descText;

        if (isPro) {
          gradientColors = [const Color(0xFF0F766E), const Color(0xFF134E4A)]; // Green/Teal
          badgeText = "â˜… PREMIUM ACTIVE";
          titleText = "Premium Plan";
          descText = "All limits removed. Advanced features unlocked.";
        } else if (isTrial) {
          gradientColors = [Colors.orange[800]!, Colors.deepOrange[900]!]; // Orange
          badgeText = "â³ TRIAL ACTIVE ($daysLeft DAYS)";
          titleText = "Pro Trial";
          descText = "Enjoying full Pro access. Upgrade to keep it.";
        } else {
          gradientColors = [const Color(0xFF1E293B), Colors.black]; // Dark Blue/Black
          badgeText = "STARTER PLAN";
          titleText = "Free Starter";
          descText = "Upgrade to unlock higher limits.";
        }

        // Limits Logic (Visual only)
        // If Trial is active, show the "Pro" limits so they know what they currently have
        final int stockLimit = (isPro || isTrial) ? kProMaxStock : kFreeMaxStock;
        final int prodLimit = (isPro || isTrial) ? kProMaxProducts : kFreeMaxProducts;
        final int teamLimit = (isPro || isTrial) ? kProMaxTeam : kFreeMaxTeam;

        final int stockCount = widget.manager.components.length;
        final int prodCount = widget.manager.products.length;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Plan & Billing"),
            backgroundColor: Colors.transparent,
            foregroundColor: textColor,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. HEADER CARD (Dynamic)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradientColors),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: gradientColors[0].withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(100)),
                            child: Text(
                              badgeText,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                          ),
                          Icon(isPro ? Icons.verified : (isTrial ? Icons.timelapse : Icons.lock_clock), color: Colors.white24, size: 40),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        titleText,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descText,
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 2. USAGE TRACKING SECTION
                Text("CURRENT USAGE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5), letterSpacing: 1.2)),
                const SizedBox(height: 16),
                
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!)
                  ),
                  child: Column(
                    children: [
                      _buildLimitBar("Stock Items", stockCount, stockLimit, Colors.blue, isDark),
                      const SizedBox(height: 16),
                      _buildLimitBar("Products / Recipes", prodCount, prodLimit, Colors.orange, isDark),
                      const SizedBox(height: 16),
                      FutureBuilder<int>(
                        future: widget.manager.getTeamMemberCount(),
                        builder: (context, snapshot) {
                          final int count = snapshot.data ?? 1;
                          return _buildLimitBar("Team Members", count, teamLimit, kSecondaryColor, isDark);
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),

                // 4. DESKTOP/WEB WARNING
                if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange)),
                    child: const Row(children: [Icon(Icons.desktop_windows, color: Colors.orange), SizedBox(width: 12), Expanded(child: Text("Subscriptions are managed via the Mobile App."))]),
                  ),

                // 5. PURCHASE BUTTONS (Hide if PRO, show if Free OR Trial)
                if (!isPro && !kIsWeb && !Platform.isWindows) ...[
                  Text("AVAILABLE PLANS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5), letterSpacing: 1.2)),
                  const SizedBox(height: 16),

                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_offerings?.current == null || _offerings!.current!.availablePackages.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      width: double.infinity,
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                      child: const Text("Store not ready or no internet connection.", style: TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    )
                  else
                    ..._offerings!.current!.availablePackages.map((package) {
                      final isLifetime = package.packageType == PackageType.lifetime;
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: ElevatedButton(
                          onPressed: () => _makePurchase(package),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLifetime ? Colors.amber[800] : kPrimaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: isLifetime ? const BorderSide(color: Colors.amber, width: 2) : BorderSide.none,
                            ),
                            elevation: isLifetime ? 8 : 4,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            package.storeProduct.title,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isLifetime) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                                            child: const Text("BEST VALUE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                                          )
                                        ]
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isLifetime ? "Pay once, own forever" : package.storeProduct.description,
                                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                package.storeProduct.priceString,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: _restorePurchases,
                      child: const Text("Restore Purchases", style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                
                // 6. FEATURES LIST (Always show)
                Text("WHAT YOU GET", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.5), letterSpacing: 1.2)),
                const SizedBox(height: 16),
                _buildFeatureRow(context, "3,000 Inventory Items", Icons.all_inclusive),
                _buildFeatureRow(context, "500 Products & Recipes", Icons.factory),
                _buildFeatureRow(context, "Up to 15 Team Members", Icons.groups),
                _buildFeatureRow(context, "Advanced Analytics Reports", Icons.bar_chart),

                const SizedBox(height: 32),

                // 7. DEV BUTTON (Hidden logic)
                if (!isPro && (widget.manager.user.email == "gilligproductsusa@gmail.com" || widget.manager.user.email == "christophergillig@gmail.com"))
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 24),
                    child: ElevatedButton(
                      onPressed: () {
                        widget.manager.activateProAccess();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("âš¡ DEV MODE: Pro Access Forced!"), backgroundColor: Colors.redAccent)
                          );
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[900], 
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16)
                      ),
                      child: const Text("DEV: Force Upgrade"),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- HELPER FOR LIMIT BARS ---
  Widget _buildLimitBar(String label, int current, int max, Color color, bool isDark) {
    double percentage = (current / max).clamp(0.0, 1.0);
    // Warning color if 90% full
    Color effectiveColor = percentage > 0.9 ? Colors.red : color; 

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
            Text(
              "$current / $max", 
              style: TextStyle(fontWeight: FontWeight.bold, color: effectiveColor, fontSize: 12)
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage,
            backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
            color: effectiveColor,
            minHeight: 8,
          ),
        )
      ],
    );
  }

  Widget _buildFeatureRow(BuildContext context, String text, IconData icon) {
    final Color textColor = Theme.of(context).brightness == Brightness.dark ? Colors.white : kPrimaryColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: kSecondaryColor, size: 20),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// --- USER SETTINGS & OPTIONS SCREEN ---
