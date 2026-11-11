import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/backup/backup_crypto.dart';

void main() {
  test('encrypted backup can be decrypted with the correct password', () async {
    const original = '{"format":"fintrack-backup","version":1,"accounts":[]}';
    final encrypted = await BackupCrypto.encrypt(
      plaintext: original,
      password: 'KataSandiAman123',
    );

    expect(encrypted, contains('fintrack-encrypted-backup'));
    expect(
      await BackupCrypto.decrypt(
        encrypted: encrypted,
        password: 'KataSandiAman123',
      ),
      original,
    );
  });

  test('wrong password is rejected', () async {
    final encrypted = await BackupCrypto.encrypt(
      plaintext: '{"data":"rahasia"}',
      password: 'KataSandiAman123',
    );

    await expectLater(
      BackupCrypto.decrypt(
        encrypted: encrypted,
        password: 'KataSandiSalah123',
      ),
      throwsFormatException,
    );
  });

  test('tampered ciphertext is rejected', () async {
    final encrypted = await BackupCrypto.encrypt(
      plaintext: '{"data":"rahasia"}',
      password: 'KataSandiAman123',
    );
    final decoded = Map<String, dynamic>.from(
      (jsonDecode(encrypted) as Map).cast<String, dynamic>(),
    );
    final ciphertext = decoded['ciphertext'] as String;
    decoded['ciphertext'] =
        '${ciphertext.substring(0, ciphertext.length - 4)}AAAA';

    await expectLater(
      BackupCrypto.decrypt(
        encrypted: jsonEncode(decoded),
        password: 'KataSandiAman123',
      ),
      throwsFormatException,
    );
  });

  test('password shorter than ten characters is rejected', () async {
    await expectLater(
      BackupCrypto.encrypt(
        plaintext: '{}',
        password: 'short',
      ),
      throwsArgumentError,
    );
  });
}
