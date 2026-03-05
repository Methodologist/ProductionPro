import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

// --- CONFIGURATION ---
const Color kPrimaryColor = Color(0xFF1E293B);
const Color kSecondaryColor = Color(0xFF0F766E);
const Color kAccentColor = Color(0xFFF59E0B);
const Color kBgColor = Color(0xFFF1F5F9);
const double kRadius = 12.0;

// --- LIMITS ---
// Free Tier (Starter)
const int kFreeMaxStock = 10;
const int kFreeMaxProducts = 3;
const int kFreeMaxTeam = 2;

// Pro Tier (Safety Caps - "Fair Use Policy")
const int kProMaxStock = 3000;
const int kProMaxProducts = 500;
const int kProMaxTeam = 15;
