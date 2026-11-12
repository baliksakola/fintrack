import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockService {
  AppLockService._();
  static final instance = AppLockService._();

  static const _storage = FlutterSecureStorage();
  static const _pinKey = 'fintrack_app_pin';
  static const _biometricKey = 'fintrack_biometric_enabled';
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> hasPin() async => (await _storage.read(key: _pinKey)) != null;

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('PIN harus terdiri dari 6 angka.');
    }
    await _storage.write(key: _pinKey, value: pin);
  }

  Future<bool> verifyPin(String pin) async =>
      (await _storage.read(key: _pinKey)) == pin;

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
