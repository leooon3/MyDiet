import 'package:flutter/material.dart';

class DietLogo extends StatelessWidget {
  final double size;
  // Manteniamo questo parametro per compatibilità con la Dashboard,
  // anche se per ora usiamo l'immagine standard.
  final bool isDarkBackground;

  const DietLogo({super.key, this.size = 100, this.isDarkBackground = false});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/icon.png', // Assicurati che questa immagine esista e sia mappata nel pubspec.yaml
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        // Fallback temporaneo se l'immagine non viene trovata
        return Icon(Icons.spa, size: size, color: Colors.green);
      },
    );
  }
}
