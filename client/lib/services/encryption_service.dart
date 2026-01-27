import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Servizio per encryption/decryption dati sensibili (GDPR compliant)
/// Fix #3-4: IV random per ogni encryption, salt derivato da UID
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // Versione del formato di encryption (per future migrazioni)
  static const int _formatVersion = 2;

  /// Genera chiave AES-256 univoca per utente basata su UID
  /// Fix #4: Salt derivato dall'UID stesso per unicità per utente
  enc.Key _generateKeyFromUid(String uid) {
    // Deriva un salt unico dall'UID usando doppio hashing
    final uidHash = sha256.convert(utf8.encode(uid)).toString();
    final salt = 'kybo_v2_${uidHash.substring(0, 16)}';
    final keyMaterial = '$uid:$salt';

    // SHA-256 per generare 32 bytes (256 bit)
    final bytes = sha256.convert(utf8.encode(keyMaterial)).bytes;
    return enc.Key(Uint8List.fromList(bytes));
  }

  /// Fix #3: Genera IV random (16 bytes) per ogni encryption
  /// L'IV viene prepeso al ciphertext per permettere la decryption
  Uint8List _generateRandomIV() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
  }

  /// Cripta JSON object (Map) in stringa Base64
  /// Fix #3: IV random prepeso al ciphertext
  /// Formato: [version:1byte][iv:16bytes][ciphertext:Nbytes] -> Base64
  String encryptData(Map<String, dynamic> data, String uid) {
    try {
      final key = _generateKeyFromUid(uid);
      final ivBytes = _generateRandomIV();
      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final jsonString = jsonEncode(data);
      final encrypted = encrypter.encrypt(jsonString, iv: iv);

      // Prependi version + IV al ciphertext
      final combined = Uint8List(_formatVersion == 2 ? 1 + 16 + encrypted.bytes.length : encrypted.bytes.length);
      combined[0] = _formatVersion; // Version byte
      combined.setRange(1, 17, ivBytes); // IV (16 bytes)
      combined.setRange(17, combined.length, encrypted.bytes); // Ciphertext

      final result = base64Encode(combined);
      debugPrint('🔒 Data encrypted v$_formatVersion (length: ${result.length})');
      return result;
    } catch (e) {
      debugPrint('❌ Encryption error: $e');
      rethrow;
    }
  }

  /// Decripta stringa Base64 in JSON object (Map)
  /// Supporta sia formato v1 (legacy) che v2 (con IV random)
  Map<String, dynamic> decryptData(String encryptedBase64, String uid) {
    try {
      final key = _generateKeyFromUid(uid);
      final combined = base64Decode(encryptedBase64);

      enc.IV iv;
      Uint8List ciphertext;

      // Controlla la versione del formato
      if (combined.length > 17 && combined[0] == 2) {
        // Formato v2: [version:1][iv:16][ciphertext:N]
        iv = enc.IV(Uint8List.fromList(combined.sublist(1, 17)));
        ciphertext = Uint8List.fromList(combined.sublist(17));
        debugPrint('🔓 Decrypting v2 format');
      } else {
        // Formato v1 legacy: IV deterministico (backward compatibility)
        final uidHash = sha256.convert(utf8.encode('${uid}_iv')).bytes;
        iv = enc.IV(Uint8List.fromList(uidHash.sublist(0, 16)));
        ciphertext = Uint8List.fromList(combined);
        debugPrint('🔓 Decrypting v1 legacy format');
      }

      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decrypt(enc.Encrypted(ciphertext), iv: iv);
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
