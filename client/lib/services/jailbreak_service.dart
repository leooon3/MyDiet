import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

/// Servizio per rilevare dispositivi jailbroken/rooted
class JailbreakService {
  static final JailbreakService _instance = JailbreakService._internal();
  factory JailbreakService() => _instance;
  JailbreakService._internal();

  bool? _isJailbroken;
  bool? _isDeveloperMode;

  /// Controlla se il dispositivo è compromesso
  Future<bool> checkDevice() async {
    try {
      // Esegui i controlli disponibili
      _isJailbroken = await FlutterJailbreakDetection.jailbroken;
      _isDeveloperMode = await FlutterJailbreakDetection.developerMode;

      debugPrint('🔐 Device Security Check:');
      debugPrint('  Jailbroken: $_isJailbroken');
      debugPrint('  Developer Mode: $_isDeveloperMode');

      // Log su Firebase Analytics
      await FirebaseAnalytics.instance.logEvent(
        name: 'device_security_check',
        parameters: {
          'jailbroken': _isJailbroken ?? false,
          'developer_mode': _isDeveloperMode ?? false,
        },
      );

      return _isJailbroken ?? false;
    } catch (e) {
      debugPrint('⚠️ Jailbreak detection error: $e');
      // In caso di errore, assume dispositivo sicuro
      return false;
    }
  }

  /// Getter per stato jailbreak
  bool get isJailbroken => _isJailbroken ?? false;

  /// Getter per developer mode (Android)
  bool get isDeveloperMode => _isDeveloperMode ?? false;

  /// Controlla se il dispositivo è considerato "a rischio"
  bool get isDeviceAtRisk {
    // Considera a rischio solo se jailbroken
    // (rimosso check emulatore perché non supportato dal package)
    return isJailbroken;
  }
}
