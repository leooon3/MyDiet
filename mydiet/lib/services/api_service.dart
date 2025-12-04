import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // Serve per debugPrint
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../constants.dart';

class ApiService {
  // 1. Upload Dieta
  static Future<Map<String, dynamic>?> uploadDietPdf() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        final path = result.files.single.path!;
        debugPrint("📂 File selezionato: $path");
        debugPrint("⏳ Inizio upload dieta...");

        File file = File(path);
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$serverUrl/upload-diet'),
        );
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          debugPrint("✅ Upload Dieta completato con successo!");
          return json.decode(utf8.decode(response.bodyBytes));
        } else {
          debugPrint("❌ Errore Server: ${response.statusCode}");
          debugPrint("Body: ${response.body}");
          throw Exception("Errore Server: ${response.statusCode}");
        }
      } else {
        debugPrint("azione annullata dall'utente");
      }
    } catch (e) {
      debugPrint("❌ Errore eccezione upload: $e");
      rethrow;
    }
    return null;
  }

  // 2. Scan Scontrino
  static Future<List<dynamic>?> scanReceipt() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'pdf'],
      );

      if (result != null) {
        final path = result.files.single.path!;
        debugPrint("📷 Scontrino selezionato: $path");
        debugPrint("⏳ Analisi scontrino in corso...");

        File file = File(path);
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$serverUrl/scan-receipt'),
        );
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          debugPrint("✅ Scansione completata!");
          return json.decode(utf8.decode(response.bodyBytes));
        } else {
          debugPrint("❌ Errore Server Scan: ${response.statusCode}");
          throw Exception("Errore Server: ${response.statusCode}");
        }
      }
    } catch (e) {
      debugPrint("❌ Errore eccezione scan: $e");
      rethrow;
    }
    return null;
  }
}
