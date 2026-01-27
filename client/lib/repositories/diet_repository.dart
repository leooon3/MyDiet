import 'dart:convert';
import 'package:kybo/services/upload_client.dart';

import '../services/api_client.dart';
import '../models/diet_models.dart';

class DietRepository {
  final ApiClient _client = ApiClient();
  final UploadClient _uploadClient = UploadClient();

  Future<DietPlan> uploadDiet(
    String filePath, {
    String? fcmToken,
    Function(double progress)? onProgress, // ✅ AGGIUNGI callback
  }) async {
    final Map<String, String> fields = {};
    if (fcmToken != null) {
      fields['fcm_token'] = fcmToken;
    }

    // ✅ USA il nuovo UploadClient con progress
    final response = await _uploadClient.uploadFile(
      endpoint: '/upload-diet',
      filePath: filePath,
      fields: fields,
      onProgress: onProgress, // ✅ Passa callback
    );

    return DietPlan.fromJson(response);
  }

  Future<List<dynamic>> scanReceipt(
    String filePath,
    List<String> allowedFoods,
  ) async {
    final String foodsJson = jsonEncode(allowedFoods);

    final response = await _client.uploadFile(
      '/scan-receipt',
      filePath,
      fields: {'allowed_foods': foodsJson},
    );

    return response as List<dynamic>;
  }

  void dispose() {
    _uploadClient.dispose();
  }
}
