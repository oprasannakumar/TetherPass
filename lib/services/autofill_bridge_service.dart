import 'dart:developer' as developer;
import 'package:flutter/services.dart';

import '../models/vault_item.dart';

/// Bridges the in-memory vault unlock state and card credentials
/// to the native Android AutofillService and IME inline suggestions (Gboard).
class AutofillBridgeService {
  static const MethodChannel _channel = MethodChannel('com.example.card_vault/autofill_bridge');

  /// Synchronizes the unlock status and cards list to the native RAM-only singleton.
  /// When [isUnlocked] is false, native memory is immediately wiped.
  static Future<void> syncVaultState({
    required bool isUnlocked,
    List<VaultItem>? items,
  }) async {
    try {
      List<Map<String, String>>? cardMaps;
      List<Map<String, String>>? pwdMaps;
      if (isUnlocked && items != null) {
        cardMaps = items
            .where((item) => item.isCard && item.cardNumber.isNotEmpty)
            .map((item) => {
                  'nickname': item.nickname.trim().isEmpty ? item.bankName : item.nickname,
                  'bankName': item.bankName,
                  'cardNumber': item.cardNumber.replaceAll(' ', '').trim(),
                  'expiry': item.expiry.trim(),
                  'cvv': item.cvv.trim(),
                  'cardHolder': item.cardHolder.trim(),
                })
            .toList();

        pwdMaps = items
            .where((item) => item.isPassword)
            .map((item) => {
                  'nickname': item.nickname.trim().isEmpty ? item.bankName : item.nickname,
                  'website': item.website.trim(),
                  'username': item.userId.trim(),
                  'password': item.loginPassword.trim(),
                  'totpSecret': item.totpSecret.trim(),
                })
            .toList();
      }

      await _channel.invokeMethod('syncVaultState', {
        'isUnlocked': isUnlocked,
        'cards': cardMaps,
        'passwords': pwdMaps,
      });
      developer.log('AutofillBridge synchronized (isUnlocked: $isUnlocked, cards: ${cardMaps?.length ?? 0}, passwords: ${pwdMaps?.length ?? 0})', name: 'AutofillBridge');
    } catch (e) {
      developer.log('Error syncing autofill bridge: $e', name: 'AutofillBridge');
    }
  }

  /// Checks if CardVault is currently selected as the active Android Autofill Service.
  static Future<bool> isAutofillEnabled() async {
    try {
      final bool? enabled = await _channel.invokeMethod<bool>('isAutofillEnabled');
      return enabled ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Directs the user to Android Settings to enable CardVault as the system Autofill service.
  static Future<bool> openAutofillSettings() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('openAutofillSettings');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
