import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

class AdminRepository {
  final String _baseUrl = "https://mydiet-74rg.onrender.com";

  Future<String?> _getToken() async {
    return await FirebaseAuth.instance.currentUser?.getIdToken();
  }

  // --- MAINTENANCE & CONFIGURATION ---

  Future<bool> getMaintenanceStatus() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/admin/config/maintenance'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['enabled'] ?? false;
    }
    return false;
  }

  Future<void> setMaintenanceStatus(bool enabled, {String? message}) async {
    final token = await _getToken();
    await http.post(
      Uri.parse('$_baseUrl/admin/config/maintenance'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'enabled': enabled,
        if (message != null) 'message': message,
      }),
    );
  }

  Future<void> scheduleMaintenance(DateTime date, bool notifyUsers) async {
    final token = await _getToken();
    String isoDate = date.toUtc().toIso8601String();
    String formattedDate = DateFormat('EEEE, d MMM "at" HH:mm').format(date);

    final response = await http.post(
      Uri.parse('$_baseUrl/admin/schedule-maintenance'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'scheduled_time': isoDate,
        'message':
            "Scheduled Maintenance: The app will be unavailable on $formattedDate.",
        'notify': notifyUsers,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to schedule: ${response.body}');
    }
  }

  Future<void> cancelMaintenanceSchedule() async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/cancel-maintenance'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to cancel: ${response.body}');
    }
  }

  // --- USER MANAGEMENT ---

  Future<void> createUser({
    required String email,
    required String password,
    required String role,
    required String firstName,
    required String lastName,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/create-user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'role': role,
        'first_name': firstName,
        'last_name': lastName,
      }),
    );
    if (response.statusCode != 200)
      throw Exception('Failed to create user: ${response.body}');
  }

  Future<void> updateUser(
    String uid, {
    String? email,
    String? firstName,
    String? lastName,
  }) async {
    final token = await _getToken();
    final response = await http.put(
      Uri.parse('$_baseUrl/admin/update-user/$uid'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (email != null) 'email': email,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update user: ${response.body}');
    }
  }

  Future<void> assignUserToNutritionist(
    String targetUid,
    String nutritionistId,
  ) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/assign-user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'target_uid': targetUid,
        'nutritionist_id': nutritionistId,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to assign user: ${response.body}');
    }
  }

  Future<void> unassignUser(String targetUid) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/unassign-user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'target_uid': targetUid}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to unassign user: ${response.body}');
    }
  }

  Future<void> deleteUser(String uid) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse('$_baseUrl/admin/delete-user/$uid'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200)
      throw Exception('Failed to delete user: ${response.body}');
  }

  Future<String> syncUsers() async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/sync-users'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200)
      return jsonDecode(response.body)['message'] ?? "Sync completato.";
    throw Exception("Sync fallito: ${response.body}");
  }

  Future<void> uploadDietForUser(String targetUid, PlatformFile file) async {
    final token = await _getToken();
    if (file.bytes == null) throw Exception("File corrotto");
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/upload-diet/$targetUid'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
        contentType: MediaType('application', 'pdf'),
      ),
    );
    final response = await request.send();
    if (response.statusCode != 200)
      throw Exception(await response.stream.bytesToString());
  }

  Future<void> uploadParserConfig(String targetUid, PlatformFile file) async {
    final token = await _getToken();
    if (file.bytes == null) throw Exception("File vuoto");
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/admin/upload-parser/$targetUid'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
        contentType: MediaType('text', 'plain'),
      ),
    );
    final response = await request.send();
    if (response.statusCode != 200)
      throw Exception(await response.stream.bytesToString());
  }
}
