import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockService {
  AppLockService._();
  static final instance = AppLockService._();

  static const _storage = FlutterSecureStorage();
  static const _pinKey = 'fintrack_app_pin';
  static const _biometricKey = 'fintrack_biometric_enabled';
  static const _failedAttemptsKey = 'fintrack_pin_failed_attempts';
  static const _lockUntilKey = 'fintrack_pin_lock_until';
  static const _maxPinAttempts = 5;
  static const _lockDuration = Duration(seconds: 30);
  static const _pinHashPrefix = 'v1';
  static final _sha256 = Sha256();
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> hasPin() async => (await _storage.read(key: _pinKey)) != null;

  Future<String> _hashPin(String pin, String salt) async {
    final digest = await _sha256.hash(utf8.encode('$salt:$pin'));
    return base64UrlEncode(digest.bytes);
  }

  Future<String> _createPinRecord(String pin) async {
    final random = Random.secure();
    final salt = base64UrlEncode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final hash = await _hashPin(pin, salt);
    return '$_pinHashPrefix:$salt:$hash';
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\\d{6}$').hasMatch(pin)) {
      throw ArgumentError('PIN harus terdiri dari 6 angka.');
    }
    await _storage.write(key: _pinKey, value: await _createPinRecord(pin));
  }

  Future<bool> verifyPin(String pin) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lockUntil = int.tryParse(
          await _storage.read(key: _lockUntilKey) ?? '',
        ) ??
        0;
    if (lockUntil > now) {
      final seconds = ((lockUntil - now) / 1000).ceil();
      throw StateError('Terlalu banyak percobaan. Coba lagi dalam $seconds detik.');
    }

    final savedPin = await _storage.read(key: _pinKey);
    var isValid = false;
    if (savedPin != null && savedPin.startsWith('$_pinHashPrefix:')) {
      final parts = savedPin.split(':');
      if (parts.length == 3 && parts[1].isNotEmpty && parts[2].isNotEmpty) {
        final candidateHash = await _hashPin(pin, parts[1]);
        isValid = _constantTimeEquals(candidateHash, parts[2]);
      }
    } else if (savedPin != null && savedPin == pin) {
      // Migrate existing installations from a plaintext PIN to a salted hash.
      await _storage.write(key: _pinKey, value: await _createPinRecord(pin));
      isValid = true;
    }

    if (isValid) {
      await _storage.delete(key: _failedAttemptsKey);
      await _storage.delete(key: _lockUntilKey);
      return true;
    }

    final attempts = (int.tryParse(
              await _storage.read(key: _failedAttemptsKey) ?? '',
            ) ??
            0) +
        1;
    if (attempts >= _maxPinAttempts) {
      final until = now + _lockDuration.inMilliseconds;
      await _storage.write(key: _lockUntilKey, value: until.toString());
      await _storage.delete(key: _failedAttemptsKey);
      throw StateError('PIN salah 5 kali. Akses dikunci selama 30 detik.');
    }

    await _storage.write(
      key: _failedAttemptsKey,
      value: attempts.toString(),
    );
    return false;
  }

  Future<bool> biometricEnabled() async =>
      (await _storage.read(key: _biometricKey)) == 'true';

  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled && !await canUseBiometrics()) {
      throw StateError('Perangkat tidak memiliki biometrik yang siap digunakan.');
    }
    await _storage.write(key: _biometricKey, value: enabled.toString());
  }

  Future<bool> authenticateBiometric() async {
    try {
      if (!await biometricEnabled() || !await canUseBiometrics()) return false;
      return await _auth.authenticate(
        localizedReason: 'Verifikasi untuk membuka FinTrack Paday',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
