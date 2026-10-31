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
        // CATCH: Only work when CardVault is unlocked and active in RAM
        if (!AutofillBridge.isUnlocked) {
            callback.onSuccess(null)
            return
        }

        val cards = AutofillBridge.getCards()
        val passwords = AutofillBridge.getPasswords()
        if (cards.isEmpty() && passwords.isEmpty()) {
            callback.onSuccess(null)
            return
        }

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

        val hasCardFields = detector.cardNumberId != null || detector.expiryId != null ||
                detector.expiryMonthId != null || detector.expiryYearId != null || detector.cvvId != null
        val hasLoginFields = detector.usernameId != null || detector.passwordId != null

        if (!hasCardFields && !hasLoginFields) {
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

        // ── 1. LOGIN CREDENTIALS AUTOFILL ──
        if (hasLoginFields && passwords.isNotEmpty()) {
            val matchingPasswords = passwords.filter { pwd ->
                val cleanWeb = cleanDomain(pwd.website)
                val domainRoot = extractDomainRoot(pwd.website)
                val nick = pwd.nickname.lowercase().trim()

                // Check webDomain (if inside browser like Chrome or WebView)
                val webMatch = detector.webDomains.any { dom ->
                    cleanWeb.isNotEmpty() && (dom == cleanWeb || dom.endsWith(".$cleanWeb") || cleanWeb.endsWith(".$dom"))
                }

                // Check package name (e.g. in.amazon.mShop.android.shopping contains "amazon")
                val pkgMatch = targetPackage.isNotEmpty() && (
                    (domainRoot.length >= 3 && targetPackage.contains(domainRoot)) ||
                    (nick.length >= 3 && targetPackage.contains(nick))
                )

                webMatch || pkgMatch
            }.let { filtered ->
                // If strict match didn't find anything, show all saved credentials
                if (filtered.isEmpty()) passwords else filtered
            }

            for (pwd in matchingPasswords) {
                val datasetBuilder = Dataset.Builder()
                val displayTitle = if (pwd.nickname.isNotEmpty()) pwd.nickname else pwd.website.ifEmpty { "Login" }
                val displaySub = if (pwd.username.isNotEmpty()) pwd.username else "Password"

                val remoteViews = RemoteViews(packageName, R.layout.autofill_dropdown_item).apply {
                    setTextViewText(R.id.autofill_title, displayTitle)
                    setTextViewText(R.id.autofill_subtitle, "👤 $displaySub")
                }

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
                        datasetBuilder.setInlinePresentation(inlinePresentation)
                    } catch (_: Exception) {}
                }

                detector.usernameId?.let { uId ->
                    if (pwd.username.isNotEmpty()) {
                        addFieldValue(datasetBuilder, uId, pwd.username, remoteViews, inlinePresentation)
                    }
                }
                detector.passwordId?.let { pId ->
                    if (pwd.password.isNotEmpty()) {
                        addFieldValue(datasetBuilder, pId, pwd.password, remoteViews, inlinePresentation)
                    }
                }

                responseBuilder.addDataset(datasetBuilder.build())
            }
        }

        // ── 2. PAYMENT CARDS AUTOFILL ──
        if (hasCardFields && cards.isNotEmpty()) {
            for (card in cards) {
                val datasetBuilder = Dataset.Builder()
                val last4 = if (card.cardNumber.length >= 4) card.cardNumber.takeLast(4) else card.cardNumber
                val sub = if (card.expiry.isNotEmpty()) "•••• $last4  |  Exp: ${card.expiry}" else "•••• $last4"

                val remoteViews = RemoteViews(packageName, R.layout.autofill_dropdown_item).apply {
                    setTextViewText(R.id.autofill_title, card.nickname)
                    setTextViewText(R.id.autofill_subtitle, sub)
                }

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
                        datasetBuilder.setInlinePresentation(inlinePresentation)
                    } catch (_: Exception) {}
                }

                val expiryParts = card.expiry.split('/')
                val expiryMonth = if (expiryParts.isNotEmpty()) expiryParts[0].trim() else ""
                val expiryYear = if (expiryParts.size > 1) expiryParts[1].trim() else ""

                detector.cardNumberId?.let { id ->
                    addFieldValue(datasetBuilder, id, card.cardNumber, remoteViews, inlinePresentation)
                }
                detector.expiryId?.let { id ->
                    addFieldValue(datasetBuilder, id, card.expiry, remoteViews, inlinePresentation)
                }
                detector.expiryMonthId?.let { id ->
                    if (expiryMonth.isNotEmpty()) {
                        addFieldValue(datasetBuilder, id, expiryMonth, remoteViews, inlinePresentation)
                    }
                }
                detector.expiryYearId?.let { id ->
                    if (expiryYear.isNotEmpty()) {
                        addFieldValue(datasetBuilder, id, expiryYear, remoteViews, inlinePresentation)
                    }
                }
                detector.cvvId?.let { id ->
                    addFieldValue(datasetBuilder, id, card.cvv, remoteViews, inlinePresentation)
                }
                detector.holderId?.let { id ->
                    if (card.cardHolder.isNotEmpty()) {
                        addFieldValue(datasetBuilder, id, card.cardHolder, remoteViews, inlinePresentation)
                    }
                }

                responseBuilder.addDataset(datasetBuilder.build())
            }
        }

        callback.onSuccess(responseBuilder.build())
    }

    private fun addFieldValue(
        datasetBuilder: Dataset.Builder,
        id: AutofillId,
        value: String,
        remoteViews: RemoteViews,
        inlinePresentation: InlinePresentation?
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && inlinePresentation != null) {
            datasetBuilder.setValue(id, AutofillValue.forText(value), remoteViews, inlinePresentation)
        } else {
            datasetBuilder.setValue(id, AutofillValue.forText(value), remoteViews)
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

    private class AutofillFieldDetector {
        var cardNumberId: AutofillId? = null
        var expiryId: AutofillId? = null
        var expiryMonthId: AutofillId? = null
        var expiryYearId: AutofillId? = null
        var cvvId: AutofillId? = null
        var holderId: AutofillId? = null

        var usernameId: AutofillId? = null
        var passwordId: AutofillId? = null
        val webDomains = mutableSetOf<String>()

        fun traverse(node: AssistStructure.ViewNode) {
            val domain = node.webDomain?.lowercase()?.trim()
            if (!domain.isNullOrBlank()) {
                webDomains.add(domain.removePrefix("www."))
            }

            val hints = node.autofillHints?.map { it.lowercase() } ?: emptyList()
            val hintText = node.hint?.toString()?.lowercase() ?: ""
            val idEntry = node.idEntry?.lowercase() ?: ""
            val text = node.text?.toString()?.lowercase() ?: ""
            val contentDesc = node.contentDescription?.toString()?.lowercase() ?: ""
            val className = node.className?.lowercase() ?: ""

            val htmlAttrs = try {
                node.htmlInfo?.attributes?.joinToString(" ") { "${it.first}=${it.second}" }?.lowercase() ?: ""
            } catch (e: Throwable) {
                ""
            }

            val raw = "$hintText $idEntry $text $contentDesc $className $htmlAttrs".lowercase()
            val norm = raw.replace('_', ' ').replace('-', ' ').replace('/', ' ').replace('.', ' ')

            // 1. Password detection
            val isPassword = hints.any { it.contains("password") } ||
                    (node.inputType and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT &&
                            (node.inputType and InputType.TYPE_MASK_VARIATION == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                             node.inputType and InputType.TYPE_MASK_VARIATION == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                             node.inputType and InputType.TYPE_MASK_VARIATION == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD)) ||
                    idEntry.contains("password") || idEntry.contains("pwd") || idEntry.contains("pass") ||
                    raw.contains("password") || raw.contains("passwd")

            // 2. CVV detection
            val isCvv = hints.any {
                it.contains("securitycode") || it.contains("csc") || it.contains("cvv") || it.contains("cvc")
            } || raw.contains("cvv") || raw.contains("cvc") || raw.contains("cvn") ||
                 raw.contains("cid") || raw.contains("csc") || raw.contains("security_code") ||
                 raw.contains("security-code") || norm.contains("security code") ||
                 norm.contains("sec code") || norm.contains("card verification") ||
                 norm.contains("verification code")

            if (isCvv) {
                if (cvvId == null || node.isFocused) cvvId = node.autofillId
            } else if (isPassword) {
                if (passwordId == null || node.isFocused) passwordId = node.autofillId
            }
            // 3. Expiry Month
            else if (hints.any { it.contains("expirationmonth") || it.contains("exp-month") || it.contains("exp_month") } ||
                raw.contains("exp_month") || raw.contains("exp-month") || raw.contains("expmonth") ||
                raw.contains("expiry_month") || raw.contains("expiry-month") || raw.contains("expirymonth") ||
                norm.contains("exp month") || norm.contains("expiry month") || norm.contains("expiration month") ||
                (hintText.trim() == "mm" && (norm.contains("exp") || norm.contains("card") || norm.contains("valid"))) ||
                (idEntry == "month" && (norm.contains("exp") || norm.contains("card") || norm.contains("valid")))
            ) {
                if (expiryMonthId == null || node.isFocused) expiryMonthId = node.autofillId
            }
            // 4. Expiry Year
            else if (hints.any { it.contains("expirationyear") || it.contains("exp-year") || it.contains("exp_year") } ||
                raw.contains("exp_year") || raw.contains("exp-year") || raw.contains("expyear") ||
                raw.contains("expiry_year") || raw.contains("expiry-year") || raw.contains("expiryyear") ||
                norm.contains("exp year") || norm.contains("expiry year") || norm.contains("expiration year") ||
                ((hintText.trim() == "yy" || hintText.trim() == "yyyy") && (norm.contains("exp") || norm.contains("card") || norm.contains("valid"))) ||
                (idEntry == "year" && (norm.contains("exp") || norm.contains("card") || norm.contains("valid")))
            ) {
                if (expiryYearId == null || node.isFocused) expiryYearId = node.autofillId
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
                if (expiryId == null || node.isFocused) expiryId = node.autofillId
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
                 norm.contains("credit card") || norm.contains("debit card") ||
                 (raw.contains("pan") && (norm.contains("card") || norm.contains("credit") || norm.contains("payment"))) ||
                 norm.contains("16 digit")
            ) {
                if (cardNumberId == null || node.isFocused) cardNumberId = node.autofillId
            }
            // 7. Cardholder Name
            else if (hints.any {
                it.contains("creditcardholdername") || it.contains("holdername") || it.contains("cc-name")
            } || raw.contains("card_holder") || raw.contains("card-holder") || raw.contains("cardholder") ||
                 norm.contains("card holder") || norm.contains("holder name") ||
                 norm.contains("name on card")
            ) {
                if (holderId == null || node.isFocused) holderId = node.autofillId
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
                if (usernameId == null || node.isFocused) usernameId = node.autofillId
            }

            for (i in 0 until node.childCount) {
                traverse(node.getChildAt(i))
            }
        }
    }
}
