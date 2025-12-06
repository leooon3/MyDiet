import '../models/diet_models.dart';
import '../services/api_client.dart';

class DietRepository {
  final ApiClient _api = ApiClient();

  Future<DietPlan> uploadDiet(String filePath) async {
    final jsonResponse = await _api.uploadFile('/upload-diet', filePath);
    return DietPlan.fromJson(jsonResponse);
  }

  Future<List<dynamic>> scanReceipt(String filePath) async {
    final jsonResponse = await _api.uploadFile('/scan-receipt', filePath);
    return jsonResponse as List<dynamic>;
  }
}
