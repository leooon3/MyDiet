import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/env.dart';

/// Client dedicato per upload con progress tracking
class UploadClient {
  late final Dio _dio;

  UploadClient() {
    _dio = Dio(BaseOptions(
      baseUrl: Env.apiUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Accept': 'application/json',
      },
    ));

    // Interceptor per aggiungere token Firebase automaticamente
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        debugPrint('❌ Upload Error: ${error.message}');
        return handler.next(error);
      },
    ));
  }

  /// Upload file con tracking progresso reale
  Future<Map<String, dynamic>> uploadFile({
    required String endpoint,
    required String filePath,
    Map<String, String>? fields,
    Function(double progress)? onProgress,
  }) async {
    try {
      // Verifica esistenza file
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception("File non trovato: $filePath");
      }

      // Prepara FormData
      final formData = FormData();

      // Aggiungi file
      formData.files.add(
        MapEntry(
          'file',
          await MultipartFile.fromFile(
            filePath,
            filename: filePath.split('/').last,
          ),
        ),
      );

      // Aggiungi campi extra
      if (fields != null) {
        fields.forEach((key, value) {
          formData.fields.add(MapEntry(key, value));
        });
      }

      debugPrint('🚀 Upload starting: $endpoint');
      debugPrint('📦 File size: ${await file.length()} bytes');

      // Esegui upload con tracking
      final response = await _dio.post(
        endpoint,
        data: formData,
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) {
            final progress = sent / total;
            onProgress(progress);
            debugPrint(
                '📊 Upload progress: ${(progress * 100).toStringAsFixed(1)}%');
          }
        },
      );

      debugPrint('✅ Upload completed: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } on DioException catch (e) {
      debugPrint('❌ DioException: ${e.type}');
      debugPrint('❌ Message: ${e.message}');

      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
          throw Exception('Timeout: Connessione troppo lenta');
        case DioExceptionType.receiveTimeout:
          throw Exception('Timeout: Server non risponde');
        case DioExceptionType.badResponse:
          final statusCode = e.response?.statusCode;
          final message = e.response?.data?['detail'] ??
              e.response?.statusMessage ??
              'Errore server';
          throw Exception('Errore $statusCode: $message');
        case DioExceptionType.connectionError:
          throw Exception('Nessuna connessione internet');
        default:
          throw Exception('Errore upload: ${e.message}');
      }
    } catch (e) {
      debugPrint('❌ Generic error: $e');
      rethrow;
    }
  }

  /// Cleanup resources
  void dispose() {
    _dio.close();
  }
}
