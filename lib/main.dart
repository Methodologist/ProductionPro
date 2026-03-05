import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

import 'firebase_options.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // This forces the app to stay in Portrait mode on phones/tablets.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // --- Initialize Stripe (not supported on web) ---
  if (!kIsWeb) {
    Stripe.publishableKey = const String.fromEnvironment(
      'STRIPE_PUBLISHABLE_KEY',
      defaultValue: '',
    );
  }

  // --- RevenueCat Init (Mobile only) ---
  if (!kIsWeb) {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      try {
        await Purchases.setLogLevel(LogLevel.debug);
        PurchasesConfiguration configuration;
        if (Platform.isAndroid) {
          configuration = PurchasesConfiguration(
            const String.fromEnvironment('RC_ANDROID_KEY', defaultValue: ''),
          );
        } else {
          configuration = PurchasesConfiguration(
            const String.fromEnvironment('RC_IOS_KEY', defaultValue: ''),
          );
        }
        await Purchases.configure(configuration);
      } catch (e) {
        print("RevenueCat init failed: $e");
      }
    }
  }

  // --- Window Manager (Desktop) ---
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(400, 850),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: "Production Pro",
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const InventoryApp());
}
