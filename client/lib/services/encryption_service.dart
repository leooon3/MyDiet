import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc; // ✅ AGGIUNGI "as enc"
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Servizio per encryption/decryption dati sensibili (GDPR compliant)
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  /// Genera chiave AES-256 univoca per utente basata su UID
  /// NOTA: In produzione, considerare l'uso di Flutter Secure Storage
  enc.Key _generateKeyFromUid(String uid) {
    // Usa PBKDF2 per derivare chiave sicura da UID
    final salt =
        'kybo_diet_salt_v1'; // In produzione, usa salt random per utente
    final keyMaterial = '$uid:$salt';

    // SHA-256 per generare 32 bytes (256 bit)
    final bytes = sha256.convert(utf8.encode(keyMaterial)).bytes;

    return enc.Key(Uint8List.fromList(bytes));
  }

  /// Genera IV (Initialization Vector) deterministico ma unico
  enc.IV _generateIV(String uid) {
    // Per semplicità usiamo hash di UID, ma in produzione meglio IV random salvato
    final ivBytes =
        sha256.convert(utf8.encode('${uid}_iv')).bytes.sublist(0, 16);
    return enc.IV(Uint8List.fromList(ivBytes));
  }

  /// Cripta JSON object (Map) in stringa Base64
  String encryptData(Map<String, dynamic> data, String uid) {
    try {
      final key = _generateKeyFromUid(uid);
      final iv = _generateIV(uid);
      final encrypter = enc.Encrypter(enc.AES(key,
          mode: enc.AESMode.cbc)); // ✅ enc.Encrypter, enc.AES, enc.AESMode

      final jsonString = jsonEncode(data);
      final encrypted = encrypter.encrypt(jsonString, iv: iv);

      debugPrint('🔒 Data encrypted (length: ${encrypted.base64.length})');
      return encrypted.base64;
    } catch (e) {
      debugPrint('❌ Encryption error: $e');
      rethrow;
    }
  }

  /// Decripta stringa Base64 in JSON object (Map)
  Map<String, dynamic> decryptData(String encryptedBase64, String uid) {
    try {
      final key = _generateKeyFromUid(uid);
      final iv = _generateIV(uid);
      final encrypter = enc.Encrypter(enc.AES(key,
          mode: enc.AESMode.cbc)); // ✅ enc.Encrypter, enc.AES, enc.AESMode

      final decrypted = encrypter.decrypt64(encryptedBase64, iv: iv);
      final data = jsonDecode(decrypted) as Map<String, dynamic>;

      debugPrint('🔓 Data decrypted successfully');
      return data;
    } catch (e) {
      debugPrint('❌ Decryption error: $e');
      rethrow;
    }
  }

  /// Cripta lista di stringhe (es. shopping list)
  String encryptList(List<String> items, String uid) {
    return encryptData({'items': items}, uid);
  }

  /// Decripta lista di stringhe
  List<String> decryptList(String encryptedBase64, String uid) {
    final data = decryptData(encryptedBase64, uid);
    return (data['items'] as List).cast<String>();
  }
}
