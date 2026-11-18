import 'package:flutter_test/flutter_test.dart';
import 'package:card_vault/models/vault_item.dart';
import 'package:card_vault/services/secure_backup_export_service.dart';

void main() {
  test('V2 Backup can be decrypted by Password, Recovery Key, AND Google Account Key', () {
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
    const googleAccountKey = '109283749281739_user@gmail.com';

    // 1. Export with password, recovery key, and Google Account Escrow
    final payload = SecureBackupExportService.exportVaultWithPassword(
      items: sampleItems,
      userPassword: masterPassword,
      recoveryKey: recoveryKey,
      googleAccountKey: googleAccountKey,
    );

    expect(payload.contains('TETHERPASS_SECURE_BACKUP_V2'), isTrue);
    expect(payload.contains('wrapped_key_google'), isTrue);

    // 2. Decrypt using Master Password
    final restoredViaPassword = SecureBackupExportService.importVaultWithPassword(
      backupPayload: payload,
      userPassword: masterPassword,
    );
    expect(restoredViaPassword.length, 1);
    expect(restoredViaPassword.first.bankName, 'HDFC Bank');

    // 3. Decrypt using formatted Recovery Key (NO master password)
    final restoredViaRecovery = SecureBackupExportService.importVaultWithPassword(
      backupPayload: payload,
      userPassword: 'ABCD-EFGH-JKLM-NPQR',
    );
    expect(restoredViaRecovery.length, 1);

    // 4. Decrypt using Google Account Key (NO password and NO recovery key - simulates wiped app data!)
    final restoredViaGoogleEscrow = SecureBackupExportService.importVaultWithPassword(
      backupPayload: payload,
      googleAccountKey: googleAccountKey,
    );
    expect(restoredViaGoogleEscrow.length, 1);
    expect(restoredViaGoogleEscrow.first.cardNumber, '4567890123456789');

    // 5. Wrong Google Account Key should fail
    expect(
      () => SecureBackupExportService.importVaultWithPassword(
        backupPayload: payload,
        googleAccountKey: 'wrong_account_id@gmail.com',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
