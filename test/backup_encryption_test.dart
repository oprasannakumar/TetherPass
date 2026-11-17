import 'package:flutter_test/flutter_test.dart';
import 'package:card_vault/models/vault_item.dart';
import 'package:card_vault/services/secure_backup_export_service.dart';

void main() {
  test('V2 Backup can be decrypted by Password AND by Recovery Key', () {
    final sampleItems = [
      VaultItem(
        id: '1',
        type: VaultItemType.card,
        bankName: 'HDFC Bank',
        nickname: 'Salary Card',
        notes: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        cardNumber: '4567890123456789',
        cardHolder: 'JOHN DOE',
        cardNetwork: 'Visa',
        cardType: 'Credit',
        expiry: '12/28',
        cvv: '123',
      ),
    ];

    const masterPassword = 'MySecretMasterPassword123!';
    const recoveryKey = 'ABCD-EFGH-JKLM-NPQR';

    // 1. Export with both password and recovery key
    final payload = SecureBackupExportService.exportVaultWithPassword(
      items: sampleItems,
      userPassword: masterPassword,
      recoveryKey: recoveryKey,
    );

    expect(payload.contains('TETHERPASS_SECURE_BACKUP_V2'), isTrue);

    // 2. Decrypt using Master Password
    final restoredViaPassword = SecureBackupExportService.importVaultWithPassword(
      backupPayload: payload,
      userPassword: masterPassword,
    );
    expect(restoredViaPassword.length, 1);
    expect(restoredViaPassword.first.bankName, 'HDFC Bank');

    // 3. Decrypt using formatted Recovery Key
    final restoredViaRecoveryFormatted = SecureBackupExportService.importVaultWithPassword(
      backupPayload: payload,
      userPassword: 'ABCD-EFGH-JKLM-NPQR',
    );
    expect(restoredViaRecoveryFormatted.length, 1);
    expect(restoredViaRecoveryFormatted.first.cardNumber, '4567890123456789');

    // 4. Decrypt using lowercase / unhyphenated Recovery Key
    final restoredViaRecoveryRaw = SecureBackupExportService.importVaultWithPassword(
      backupPayload: payload,
      userPassword: 'abcdefghjklmnpqr',
    );
    expect(restoredViaRecoveryRaw.length, 1);

    // 5. Wrong password should fail
    expect(
      () => SecureBackupExportService.importVaultWithPassword(
        backupPayload: payload,
        userPassword: 'WrongPassword!',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
