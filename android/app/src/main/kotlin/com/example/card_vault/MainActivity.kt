package com.example.card_vault

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import android.view.autofill.AutofillManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.example.card_vault/autofill_bridge"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent screenshots, screen recording, and recent app thumbnails
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncVaultState" -> {
                    val isUnlocked = call.argument<Boolean>("isUnlocked") ?: false
                    val cards = call.argument<List<Map<String, Any?>>>("cards")
                    val passwords = call.argument<List<Map<String, Any?>>>("passwords")
                    AutofillBridge.sync(isUnlocked, cards, passwords)
                    result.success(true)
                }
                "isAutofillEnabled" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val afm = getSystemService(AutofillManager::class.java)
                        val hasAny = afm?.hasEnabledAutofillServices() == true
                        if (!hasAny) {
                            result.success(false)
                        } else {
                            try {
                                val currentService = Settings.Secure.getString(contentResolver, "autofill_service")
                                val isOurs = currentService != null && currentService.contains(packageName)
                                result.success(isOurs)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                    } else {
                        result.success(false)
                    }
                }
                "openAutofillSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                                data = Uri.parse("package:com.example.card_vault")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val fallback = Intent("android.settings.AUTOFILL_SETTINGS")
                                startActivity(fallback)
                                result.success(true)
                            } catch (e2: Exception) {
                                try {
                                    startActivity(Intent(Settings.ACTION_SETTINGS))
                                    result.success(true)
                                } catch (e3: Exception) {
                                    result.error("UNAVAILABLE", e3.message, null)
                                }
                            }
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // Do NOT clear AutofillBridge on Activity destroy!
        // The background AutofillService needs to provide credentials while the user uses other apps (like Amazon).
        // AutofillBridge is cleared only on explicit lock or session expiry from Flutter.
    }
}
