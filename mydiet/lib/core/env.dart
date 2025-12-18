import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get apiUrl {
    final configured = dotenv.env['API_URL'];
    if (configured != null && configured.isNotEmpty) return configured;

    // [FIX] Handle Android Emulator localhost mapping
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }

    return 'http://localhost:8000';
  }
}
