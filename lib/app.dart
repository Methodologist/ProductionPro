import 'package:flutter/material.dart';

import 'constants.dart';
import 'views/auth/auth_gate.dart';

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Production Pro',
          debugShowCheckedModeBanner: false,

          // 1. LIGHT THEME
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: kBgColor,
            colorScheme: ColorScheme.fromSeed(seedColor: kPrimaryColor, primary: kPrimaryColor, secondary: kSecondaryColor, surface: Colors.white),
            appBarTheme: const AppBarTheme(backgroundColor: kPrimaryColor, foregroundColor: Colors.white, elevation: 0, centerTitle: true),
            cardTheme: CardThemeData(elevation: 2, shadowColor: Colors.black12, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)), color: Colors.white),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: BorderSide(color: Colors.grey[300]!)),
              contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)))),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: kSecondaryColor, foregroundColor: Colors.white),
          ),

          // 2. DARK THEME
          darkTheme: ThemeData.dark().copyWith(
            primaryColor: kPrimaryColor,
            scaffoldBackgroundColor: const Color(0xFF121212),
            cardColor: const Color(0xFF1E1E1E),

            iconTheme: const IconThemeData(color: Colors.white70),
            primaryIconTheme: const IconThemeData(color: Colors.white),

            colorScheme: const ColorScheme.dark(
              primary: kSecondaryColor,
              secondary: kSecondaryColor,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
              onPrimary: Colors.white,
            ),

            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.white),
              elevation: 0,
            ),

            textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),

            cardTheme: CardThemeData(
              color: const Color(0xFF1E1E1E),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kRadius),
                side: BorderSide(color: Colors.grey[800]!, width: 1),
              )
            ),

            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF2C2C2C),
              prefixIconColor: kSecondaryColor,
              labelStyle: const TextStyle(color: Colors.white70),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadius),
                borderSide: BorderSide(color: Colors.grey[700]!)
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadius),
                borderSide: BorderSide(color: Colors.grey[800]!)
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadius),
                borderSide: const BorderSide(color: kSecondaryColor)
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),

            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: kSecondaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                elevation: 0
              )
            ),
          ),

          themeMode: currentMode,
          home: const AuthGate(),
        );
      },
    );
  }
}
