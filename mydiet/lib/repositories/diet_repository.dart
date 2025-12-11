import '../models/diet_models.dart';
import '../services/api_client.dart';

class DietRepository {
  final ApiClient _api = ApiClient();

  // [UPDATED] Accepts optional fcmToken
  Future<DietPlan> uploadDiet(String filePath, {String? fcmToken}) async {
    Map<String, String>? fields;

    if (fcmToken != null) {
      fields = {'fcm_token': fcmToken};
    }

    final jsonResponse = await _api.uploadFile(
      '/upload-diet',
      filePath,
      fields: fields,
    );
    return DietPlan.fromJson(jsonResponse);
  }

  Future<List<dynamic>> scanReceipt(String filePath) async {
    final jsonResponse = await _api.uploadFile('/scan-receipt', filePath);
    return jsonResponse as List<dynamic>;
  }
}
