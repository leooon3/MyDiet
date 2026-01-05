import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get fileName => kReleaseMode ? ".env.prod" : ".env";

  static Future<void> init() async {
    try {
      await dotenv.load(fileName: fileName);
    } catch (e) {
      debugPrint("Errore caricamento $fileName: $e");
    }
  }

  static String get apiUrl => dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000';
  static bool get isProd => kReleaseMode || dotenv.env['IS_PROD'] == 'true';
}
