import 'package:flutter/material.dart';

class AuthScreenBackground extends StatelessWidget {
  final Widget child;

  const AuthScreenBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.5),
          radius: 1.5,
          colors: [
            Color(0xFF2B72B8),
            Color(0xFF081F3A),
          ],
          stops: [0.0, 1.0],
        ),
      ),
      child: child,
    );
  }
}
