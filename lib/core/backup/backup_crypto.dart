import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class BackupCrypto {
  static const _format = 'fintrack-encrypted-backup';
  static const _version = 1;
  static const _iterations = 210000;

  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  static Future<String> encrypt({
    required String plaintext,
    required String password,
  }) async {
    _validatePassword(password);
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final box = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return const JsonEncoder.withIndent('  ').convert({
      'format': _format,
      'version': _version,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _iterations,
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  static Future<String> decrypt({
    required String encrypted,
    required String password,
  }) async {
    _validatePassword(password);
    final decoded = jsonDecode(encrypted);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _format ||
        decoded['version'] != _version ||
        decoded['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        decoded['iterations'] != _iterations ||
        decoded['cipher'] != 'AES-256-GCM') {
      throw const FormatException('Format backup terenkripsi tidak dikenali.');
    }

    List<int> bytes(String key) {
      final value = decoded[key];
      if (value is! String) throw FormatException('Bagian $key tidak valid.');
      try {
        return base64Decode(value);
      } on FormatException {
        throw FormatException('Bagian $key rusak.');
      }
    }

    final salt = bytes('salt');
    final nonce = bytes('nonce');
    final ciphertext = bytes('ciphertext');
    final mac = bytes('mac');
    if (salt.length != 16 || nonce.length != _cipher.nonceLength ||
        mac.length != _cipher.macAlgorithm.macLength) {
      throw const FormatException('Struktur file backup tidak valid.');
    }

    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    try {
      final clear = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Kata sandi salah atau file backup telah diubah.',
      );
    }
  }

  static void _validatePassword(String password) {
    if (password.length < 10) {
      throw ArgumentError('Kata sandi backup minimal 10 karakter.');
    }
  }
}
