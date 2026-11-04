package com.example.card_vault

import java.io.ByteArrayOutputStream
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.math.pow

/**
 * High-performance RFC 6238 TOTP Generator for Native Android Autofill Service.
 */
object TotpGenerator {

    fun generateCurrentCode(secret: String): String? {
        val cleanSecret = secret.trim().replace(" ", "").replace("-", "").uppercase()
        if (cleanSecret.isEmpty()) return null
        val keyBytes = decodeBase32(cleanSecret) ?: return null
        val timeStep = System.currentTimeMillis() / 1000L / 30L
        return generateTotp(keyBytes, timeStep, 6)
    }

    private fun decodeBase32(input: String): ByteArray? {
        val base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        val clean = input.trim().uppercase().replace("=", "")
        if (clean.isEmpty()) return null

        val bytes = ByteArrayOutputStream()
        var buffer = 0
        var bitsLeft = 0
        for (c in clean) {
            val valIndex = base32Chars.indexOf(c)
            if (valIndex < 0) return null
            buffer = (buffer shl 5) or valIndex
            bitsLeft += 5
            if (bitsLeft >= 8) {
                bytes.write((buffer shr (bitsLeft - 8)) and 0xFF)
                bitsLeft -= 8
            }
        }
        return bytes.toByteArray()
    }

    private fun generateTotp(key: ByteArray, timeStep: Long, digits: Int = 6): String {
        val msg = ByteArray(8)
        var t = timeStep
        for (i in 7 downTo 0) {
            msg[i] = (t and 0xFFL).toByte()
            t = t shr 8
        }
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(key, "RAW"))
        val hash = mac.doFinal(msg)
        val offset = hash[hash.size - 1].toInt() and 0x0F
        val binary = ((hash[offset].toInt() and 0x7F) shl 24) or
                ((hash[offset + 1].toInt() and 0xFF) shl 16) or
                ((hash[offset + 2].toInt() and 0xFF) shl 8) or
                (hash[offset + 3].toInt() and 0xFF)
        val otp = binary % 10.0.pow(digits.toDouble()).toInt()
        return String.format("%0${digits}d", otp)
    }
}
