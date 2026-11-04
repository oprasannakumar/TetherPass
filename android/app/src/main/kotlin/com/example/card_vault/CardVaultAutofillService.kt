package com.example.card_vault

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.InlinePresentation
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import androidx.autofill.inline.v1.InlineSuggestionUi

@RequiresApi(Build.VERSION_CODES.O)
class CardVaultAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback
    ) {
        val fillContext = request.fillContexts.lastOrNull()
        val structure = fillContext?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }

        val targetPackage = structure.activityComponent?.packageName?.lowercase() ?: ""

        val detector = AutofillFieldDetector()
        for (i in 0 until structure.windowNodeCount) {
            val window = structure.getWindowNodeAt(i)
            detector.traverse(window.rootViewNode)
        }

        val hasTotpFields = detector.totp != null
        val hasCardFields = (detector.cardNumber != null || detector.expiry != null ||
                detector.expiryMonth != null || detector.expiryYear != null || detector.cvv != null) &&
                !hasTotpFields
        val hasLoginFields = detector.username != null || detector.password != null || hasTotpFields

        if (!hasCardFields && !hasLoginFields) {
            callback.onSuccess(null)
            return
        }

        // If vault is locked in RAM, offer an Unlock prompt so the user can authenticate TetherPass and autofill!
        if (!AutofillBridge.isUnlocked) {
            val targetField = detector.focusedField
                ?: detector.totp
                ?: detector.cardNumber
                ?: detector.username
                ?: detector.password
                ?: detector.expiry
                ?: detector.cvv

            if (targetField != null) {
                try {
                    val unlockIntent = Intent(applicationContext, MainActivity::class.java).apply {
                        action = Intent.ACTION_VIEW
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    }
                    val pendingIntent = PendingIntent.getActivity(
                        applicationContext,
                        1001,
                        unlockIntent,
                        PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    val unlockViews = RemoteViews(packageName, R.layout.autofill_dropdown_item).apply {
                        setTextViewText(R.id.autofill_title, "🔒 Unlock TetherPass")
                        setTextViewText(R.id.autofill_subtitle, "Tap to authenticate & autofill")
                    }
                    val resp = FillResponse.Builder()
                        .setAuthentication(arrayOf(targetField.id), pendingIntent.intentSender, unlockViews)
                        .build()
                    callback.onSuccess(resp)
                    return
                } catch (_: Exception) {}
            }
            callback.onSuccess(null)
            return
        }

        val cards = AutofillBridge.getCards()
        val passwords = AutofillBridge.getPasswords()
        if (cards.isEmpty() && passwords.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val responseBuilder = FillResponse.Builder()
        val inlineRequest = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            request.inlineSuggestionsRequest
        } else null

        val specs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && inlineRequest != null) {
            inlineRequest.inlinePresentationSpecs
        } else null

        // ── 0. 2FA / TOTP VERIFICATION CODES AUTOFILL ──
        if (hasTotpFields && passwords.isNotEmpty()) {
            val passwordsWithTotp = passwords.filter { it.totpSecret.isNotEmpty() }
            val matchingTotp = passwordsWithTotp.filter { pwd ->
                val cleanWeb = cleanDomain(pwd.website)
                val domainRoot = extractDomainRoot(pwd.website)
                val nick = pwd.nickname.lowercase().trim()

                val webMatch = detector.webDomains.any { dom ->
                    cleanWeb.isNotEmpty() && (
                        dom == cleanWeb ||
                        dom.endsWith(".$cleanWeb") ||
                        cleanWeb.endsWith(".$dom") ||
                        (domainRoot.length >= 3 && dom.contains(domainRoot))
                    )
                }

                val pkgMatch = targetPackage.isNotEmpty() && (
                    (domainRoot.length >= 3 && targetPackage.contains(domainRoot)) ||
                    (nick.length >= 3 && targetPackage.contains(nick))
                )

                webMatch || pkgMatch
            }.let { filtered ->
                if (filtered.isNotEmpty()) filtered else passwordsWithTotp
            }

            for (pwd in matchingTotp) {
                val totpCode = TotpGenerator.generateCurrentCode(pwd.totpSecret) ?: continue
                val datasetBuilder = Dataset.Builder()
                val displayTitle = "⚡ $totpCode"
                val displaySub = if (pwd.nickname.isNotEmpty()) pwd.nickname else pwd.website.ifEmpty { "2FA Code" }

                var inlinePresentation: InlinePresentation? = null
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && specs != null && specs.isNotEmpty()) {
                    try {
                        val spec = specs[0]
                        val emptyIntent = PendingIntent.getActivity(
                            applicationContext,
                            0,
                            Intent(),
                            PendingIntent.FLAG_IMMUTABLE
                        )
                        val contentBuilder = InlineSuggestionUi.newContentBuilder(emptyIntent)
                            .setTitle(displayTitle)
                            .setContentDescription(displayTitle)
                            .setSubtitle(displaySub)

                        val slice = contentBuilder.build().slice
                        inlinePresentation = InlinePresentation(slice, spec, false)
                    } catch (_: Exception) {}
                }

                val afVal = AutofillValue.forText(totpCode)
                val fieldRemoteViews = RemoteViews(packageName, R.layout.autofill_dropdown_item).apply {
                    setTextViewText(R.id.autofill_title, displayTitle)
                    setTextViewText(R.id.autofill_subtitle, "🔐 $displaySub")
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && inlinePresentation != null) {
                    datasetBuilder.setValue(detector.totp!!.id, afVal, fieldRemoteViews, inlinePresentation)
                } else {
                    datasetBuilder.setValue(detector.totp!!.id, afVal, fieldRemoteViews)
                }

                responseBuilder.addDataset(datasetBuilder.build())
            }
        }

        // ── 1. LOGIN CREDENTIALS AUTOFILL (Only when username or password input is present) ──
        val hasDirectLoginFields = detector.username != null || detector.password != null
        if (hasDirectLoginFields && passwords.isNotEmpty()) {
            val matchingPasswords = passwords.filter { pwd ->
                val cleanWeb = cleanDomain(pwd.website)
                val domainRoot = extractDomainRoot(pwd.website)
                val nick = pwd.nickname.lowercase().trim()

                // Check webDomain (if inside browser like Chrome, Firefox, or WebView)
                val webMatch = detector.webDomains.any { dom ->
                    cleanWeb.isNotEmpty() && (
                        dom == cleanWeb ||
                        dom.endsWith(".$cleanWeb") ||
                        cleanWeb.endsWith(".$dom") ||
                        (domainRoot.length >= 3 && dom.contains(domainRoot))
                    )
                }

                // Check package name (e.g. in.amazon.mShop.android.shopping contains "amazon")
                val pkgMatch = targetPackage.isNotEmpty() && (
                    (domainRoot.length >= 3 && targetPackage.contains(domainRoot)) ||
                    (nick.length >= 3 && targetPackage.contains(nick))
                )

                webMatch || pkgMatch
            }.let { filtered ->
                if (filtered.isEmpty()) passwords else filtered
            }

            for (pwd in matchingPasswords) {
                val datasetBuilder = Dataset.Builder()
                val displayTitle = if (pwd.nickname.isNotEmpty()) pwd.nickname else pwd.website.ifEmpty { "Login" }
                val displaySub = if (pwd.username.isNotEmpty()) pwd.username else "Password"

                var inlinePresentation: InlinePresentation? = null
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && specs != null && specs.isNotEmpty()) {
                    try {
                        val spec = specs[0]
                        val emptyIntent = PendingIntent.getActivity(
                            applicationContext,
                            0,
                            Intent(),
                            PendingIntent.FLAG_IMMUTABLE
                        )
                        val contentBuilder = InlineSuggestionUi.newContentBuilder(emptyIntent)
                            .setTitle(displayTitle)
                            .setContentDescription(displayTitle)
                            .setSubtitle(displaySub)

                        val slice = contentBuilder.build().slice
                        inlinePresentation = InlinePresentation(slice, spec, false)
                    } catch (_: Exception) {}
                }

                fun applyLoginField(field: FieldInfo?, value: String) {
                    if (field == null || value.isEmpty()) return
                    val afVal = AutofillValue.forText(value)
                    val fieldRemoteViews = RemoteViews(packageName, R.layout.autofill_dropdown_item).apply {
                        setTextViewText(R.id.autofill_title, displayTitle)
                        setTextViewText(R.id.autofill_subtitle, "👤 $displaySub")
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && inlinePresentation != null) {
                        datasetBuilder.setValue(field.id, afVal, fieldRemoteViews, inlinePresentation)
                    } else {
                        datasetBuilder.setValue(field.id, afVal, fieldRemoteViews)
                    }
                }

                applyLoginField(detector.username, pwd.username)
                applyLoginField(detector.password, pwd.password)

                responseBuilder.addDataset(datasetBuilder.build())
            }
        }

        // ── 2. PAYMENT CARDS AUTOFILL ──
        if (hasCardFields && cards.isNotEmpty()) {
            for (card in cards) {
                val datasetBuilder = Dataset.Builder()
                val last4 = if (card.cardNumber.length >= 4) card.cardNumber.takeLast(4) else card.cardNumber
                val sub = if (card.expiry.isNotEmpty()) "•••• $last4  |  Exp: ${card.expiry}" else "•••• $last4"

                var inlinePresentation: InlinePresentation? = null
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && specs != null && specs.isNotEmpty()) {
                    try {
                        val spec = specs[0]
                        val emptyIntent = PendingIntent.getActivity(
                            applicationContext,
                            0,
                            Intent(),
                            PendingIntent.FLAG_IMMUTABLE
                        )
                        val contentBuilder = InlineSuggestionUi.newContentBuilder(emptyIntent)
                            .setTitle(card.nickname)
                            .setContentDescription(card.nickname)
                            .setSubtitle("•••• $last4")

                        val slice = contentBuilder.build().slice
                        inlinePresentation = InlinePresentation(slice, spec, false)
                    } catch (_: Exception) {}
                }

                val expiryParts = card.expiry.split('/')
                val expiryMonth = if (expiryParts.isNotEmpty()) expiryParts[0].trim() else ""
                val expiryYear = if (expiryParts.size > 1) expiryParts[1].trim() else ""

                fun applyField(field: FieldInfo?, value: String, isM: Boolean = false, isY: Boolean = false) {
                    if (field == null || value.isEmpty()) return
                    val afVal = getAutofillValue(field, value, isM, isY) ?: return
                    val fieldRemoteViews = RemoteViews(packageName, R.layout.autofill_dropdown_item).apply {
                        setTextViewText(R.id.autofill_title, card.nickname)
                        setTextViewText(R.id.autofill_subtitle, sub)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && inlinePresentation != null) {
                        datasetBuilder.setValue(field.id, afVal, fieldRemoteViews, inlinePresentation)
                    } else {
                        datasetBuilder.setValue(field.id, afVal, fieldRemoteViews)
                    }
                }

                applyField(detector.cardNumber, card.cardNumber)
                applyField(detector.holder, card.cardHolder)
                applyField(detector.expiry, card.expiry)
                applyField(detector.expiryMonth, expiryMonth, isM = true)
                applyField(detector.expiryYear, expiryYear, isY = true)
                applyField(detector.cvv, card.cvv)

                responseBuilder.addDataset(datasetBuilder.build())
            }
        }

        callback.onSuccess(responseBuilder.build())
    }

    private fun getAutofillValue(
        field: FieldInfo,
        textVal: String,
        isMonth: Boolean = false,
        isYear: Boolean = false
    ): AutofillValue? {
        if (field.type == 3 /* AUTOFILL_TYPE_LIST */ && field.options != null && field.options.isNotEmpty()) {
            val cleanText = textVal.trim()
            val numVal = cleanText.toIntOrNull()

            for (i in field.options.indices) {
                val opt = field.options[i].toString().trim().lowercase()
                if (opt.equals(cleanText, ignoreCase = true)) {
                    return AutofillValue.forList(i)
                }
                if (isMonth && numVal != null && numVal in 1..12) {
                    val sNames = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
                    val fNames = listOf("january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december")
                    val s = sNames[numVal - 1]
                    val f = fNames[numVal - 1]
                    val num2 = String.format("%02d", numVal)
                    val num1 = numVal.toString()
                    if (opt.contains(s) || opt.contains(f) || opt == num1 || opt == num2 || opt.startsWith(num2) || opt.startsWith(num1)) {
                        return AutofillValue.forList(i)
                    }
                }
                if (isYear && cleanText.isNotEmpty()) {
                    val y2 = if (cleanText.length >= 2) cleanText.takeLast(2) else cleanText
                    val y4 = if (cleanText.length == 2) "20$cleanText" else cleanText
                    if (opt == y4 || opt == y2 || opt.contains(y4) || opt.contains(y2)) {
                        return AutofillValue.forList(i)
                    }
                }
            }
            return null
        } else {
            return AutofillValue.forText(textVal)
        }
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        callback.onSuccess()
    }

    private fun cleanDomain(url: String): String {
        var str = url.trim().lowercase()
        str = str.replace(Regex("^[a-zA-Z]+://"), "")
        str = str.split("/")[0].split("?")[0].split("#")[0].split(":")[0]
        return str.removePrefix("www.")
    }

    private fun extractDomainRoot(domainOrUrl: String): String {
        val clean = cleanDomain(domainOrUrl)
        val parts = clean.split(".")
        return if (parts.isNotEmpty()) parts[0] else clean
    }

    private class FieldInfo(
        val id: AutofillId,
        val type: Int,
        val options: Array<CharSequence>? = null
    )

    private class AutofillFieldDetector {
        var cardNumber: FieldInfo? = null
        var expiry: FieldInfo? = null
        var expiryMonth: FieldInfo? = null
        var expiryYear: FieldInfo? = null
        var cvv: FieldInfo? = null
        var holder: FieldInfo? = null

        var username: FieldInfo? = null
        var password: FieldInfo? = null
        var totp: FieldInfo? = null
        var focusedField: FieldInfo? = null
        val webDomains = mutableSetOf<String>()

        fun traverse(node: AssistStructure.ViewNode) {
            val domain = node.webDomain?.lowercase()?.trim()
            if (!domain.isNullOrBlank()) {
                val clean = domain.replace(Regex("^[a-zA-Z]+://"), "").split("/")[0].split(":")[0].removePrefix("www.")
                webDomains.add(clean)
            }

            val hints = node.autofillHints?.map { it.lowercase() } ?: emptyList()
            val hintText = node.hint?.toString()?.lowercase() ?: ""
            val idEntry = node.idEntry?.lowercase() ?: ""
            val text = node.text?.toString()?.lowercase() ?: ""
            val contentDesc = node.contentDescription?.toString()?.lowercase() ?: ""
            val className = node.className?.lowercase() ?: ""

            val htmlTag = try { node.htmlInfo?.tag?.lowercase() ?: "" } catch (_: Throwable) { "" }
            val htmlAttrs = try {
                node.htmlInfo?.attributes?.joinToString(" ") { "${it.first}=${it.second}" }?.lowercase() ?: ""
            } catch (_: Throwable) {
                ""
            }

            val raw = "$hintText $idEntry $text $contentDesc $className $htmlTag $htmlAttrs".lowercase()
            val norm = raw.replace('_', ' ').replace('-', ' ').replace('/', ' ').replace('.', ' ')
            val afId = node.autofillId
            val fieldInfo = if (afId != null) FieldInfo(afId, node.autofillType, node.autofillOptions) else null

            if (fieldInfo != null) {
                if (node.isFocused) {
                    focusedField = fieldInfo
                }

                // 1. 2FA / TOTP / One-Time Passcode Detection
                val isTotp = hints.any {
                    it.contains("one-time-code") || it.contains("otp") || it.contains("2fa") ||
                    it.contains("totp") || it.contains("verification") || it.contains("passcode")
                } || raw.contains("one-time-code") || raw.contains("onetimecode") ||
                     raw.contains("totp") || raw.contains("2fa") || raw.contains("mfa") ||
                     raw.contains("otp") || raw.contains("authenticator") ||
                     raw.contains("verification_code") || raw.contains("verification-code") ||
                     raw.contains("verificationcode") || raw.contains("auth_code") ||
                     raw.contains("auth-code") || norm.contains("verification code") ||
                     norm.contains("two factor") || norm.contains("2 step") || norm.contains("two step") ||
                     ((norm.contains("security code") || norm.contains("passcode") || norm.contains("code")) &&
                      !norm.contains("card") && !norm.contains("cvv") && !norm.contains("payment") && !norm.contains("credit") && !norm.contains("debit"))

                // 2. Password detection
                val isPassword = !isTotp && (hints.any { it.contains("password") } ||
                        (node.inputType and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT &&
                                (node.inputType and InputType.TYPE_MASK_VARIATION == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                                 node.inputType and InputType.TYPE_MASK_VARIATION == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                                 node.inputType and InputType.TYPE_MASK_VARIATION == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)) ||
                        idEntry.contains("password") || idEntry.contains("pwd") || idEntry.contains("pass") ||
                        raw.contains("password") || raw.contains("passwd"))

                // 3. CVV detection (Strictly for card payment fields, NEVER for 2FA / OTP!)
                val isCvv = !isTotp && !isPassword && (hints.any {
                    it.contains("creditcardsecuritycode") || it.contains("csc") || it.contains("cvv") || it.contains("cvc")
                } || raw.contains("cvv") || raw.contains("cvc") || raw.contains("cvn") ||
                     raw.contains("cid") || raw.contains("csc") || raw.contains("card_cvv") ||
                     raw.contains("card-cvv") ||
                     ((norm.contains("security code") || norm.contains("sec code") || norm.contains("card verification")) &&
                      (norm.contains("card") || norm.contains("payment") || norm.contains("credit") || norm.contains("debit"))))

                if (isTotp) {
                    if (totp == null || node.isFocused) totp = fieldInfo
                } else if (isCvv) {
                    if (cvv == null || node.isFocused) cvv = fieldInfo
                } else if (isPassword) {
                    if (password == null || node.isFocused) password = fieldInfo
                }
                // 3. Expiry Month
                else if (hints.any { it.contains("expirationmonth") || it.contains("exp-month") || it.contains("exp_month") } ||
                    raw.contains("exp_month") || raw.contains("exp-month") || raw.contains("expmonth") ||
                    raw.contains("expiry_month") || raw.contains("expiry-month") || raw.contains("expirymonth") ||
                    norm.contains("exp month") || norm.contains("expiry month") || norm.contains("expiration month") ||
                    (hintText.trim() == "mm" && (norm.contains("exp") || norm.contains("card") || norm.contains("valid"))) ||
                    (idEntry == "month" && (norm.contains("exp") || norm.contains("card") || norm.contains("valid")))
                ) {
                    if (expiryMonth == null || node.isFocused) expiryMonth = fieldInfo
                }
                // 4. Expiry Year
                else if (hints.any { it.contains("expirationyear") || it.contains("exp-year") || it.contains("exp_year") } ||
                    raw.contains("exp_year") || raw.contains("exp-year") || raw.contains("expyear") ||
                    raw.contains("expiry_year") || raw.contains("expiry-year") || raw.contains("expiryyear") ||
                    norm.contains("exp year") || norm.contains("expiry year") || norm.contains("expiration year") ||
                    ((hintText.trim() == "yy" || hintText.trim() == "yyyy") && (norm.contains("exp") || norm.contains("card") || norm.contains("valid"))) ||
                    (idEntry == "year" && (norm.contains("exp") || norm.contains("card") || norm.contains("valid")))
                ) {
                    if (expiryYear == null || node.isFocused) expiryYear = fieldInfo
                }
                // 5. Expiry Date
                else if (hints.any {
                    it.contains("expirationdate") || it.contains("expiration") ||
                    it.contains("expiry") || it.contains("cc-exp") || it.contains("cc_exp")
                } || raw.contains("expiry") || raw.contains("expire") || raw.contains("expiration") ||
                     raw.contains("ccexp") || raw.contains("cc_exp") || raw.contains("cc-exp") ||
                     raw.contains("card_exp") || raw.contains("card-exp") || raw.contains("cardexp") ||
                     raw.contains("exp_date") || raw.contains("exp-date") || raw.contains("expdate") ||
                     norm.contains("exp date") || norm.contains("expiry date") || norm.contains("expiration date") ||
                     norm.contains("valid thru") || norm.contains("validthru") || norm.contains("valid till") ||
                     norm.contains("valid until") || norm.contains("validity") ||
                     raw.contains("mm/yy") || raw.contains("mm / yy") || raw.contains("mm-yy") ||
                     raw.contains("mm/yyyy") || raw.contains("mm / yyyy") || raw.contains("mmyy") ||
                     norm.contains("mm yy") || norm.contains("mm yyyy") ||
                     norm.contains("card exp") ||
                     (hintText.trim().startsWith("exp") && !hintText.contains("cvv"))
                ) {
                    if (expiry == null || node.isFocused) expiry = fieldInfo
                }
                // 6. Card Number
                else if (hints.any {
                    it.contains("creditcardnumber") || it.contains("cardnumber") ||
                    it.contains("cc-number") || it.contains("cc_number")
                } || raw.contains("card_number") || raw.contains("card-number") || raw.contains("cardnumber") ||
                     norm.contains("card number") || norm.contains("card no") ||
                     raw.contains("card_no") || raw.contains("card-no") || raw.contains("cardno") ||
                     raw.contains("cc_num") || raw.contains("cc-num") || raw.contains("ccnum") ||
                     raw.contains("cc_number") || raw.contains("cc-number") ||
                     raw.contains("card_num") || raw.contains("card-num") ||
                     norm.contains("credit card") || norm.contains("debit card") ||
                     (raw.contains("card") && (norm.contains("number") || norm.contains("digit") || norm.contains("no"))) ||
                     (raw.contains("pan") && (norm.contains("card") || norm.contains("credit") || norm.contains("payment"))) ||
                     norm.contains("16 digit")
                ) {
                    if (cardNumber == null || node.isFocused) cardNumber = fieldInfo
                }
                // 7. Cardholder Name
                else if (hints.any {
                    it.contains("creditcardholdername") || it.contains("holdername") || it.contains("cc-name")
                } || raw.contains("card_holder") || raw.contains("card-holder") || raw.contains("cardholder") ||
                     norm.contains("card holder") || norm.contains("holder name") ||
                     norm.contains("name on card")
                ) {
                    if (holder == null || node.isFocused) holder = fieldInfo
                }
                // 8. Username / Email / Login ID
                else if (hints.any {
                    it.contains("username") || it.contains("emailaddress") || it.contains("phone") || it.contains("email")
                } || (node.inputType and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT &&
                      node.inputType and InputType.TYPE_MASK_VARIATION == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS) ||
                    idEntry.contains("username") || idEntry.contains("email") || idEntry.contains("login") ||
                    idEntry.contains("user_id") || idEntry.contains("userid") || idEntry.contains("account") ||
                    raw.contains("username") || raw.contains("email") || raw.contains("user_name") ||
                    raw.contains("login_id") || raw.contains("userid") || raw.contains("user_id") ||
                    raw.contains("customer_id") || raw.contains("cust_id") ||
                    (hintText.contains("email") || hintText.contains("mobile") || hintText.contains("phone"))
                ) {
                    if (username == null || node.isFocused) username = fieldInfo
                }
            }

            for (i in 0 until node.childCount) {
                traverse(node.getChildAt(i))
            }
        }
    }
}
