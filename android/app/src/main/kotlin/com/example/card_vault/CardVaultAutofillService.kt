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
        // CATCH: Only work when CardVault is unlocked and active
        if (!AutofillBridge.isUnlocked) {
            callback.onSuccess(null)
            return
        }

        val cards = AutofillBridge.getCards()
        if (cards.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }

        val detector = CreditCardFieldDetector()
        for (i in 0 until structure.windowNodeCount) {
            val window = structure.getWindowNodeAt(i)
            detector.traverse(window.rootViewNode)
        }

        // If no credit card fields were found, do nothing
        if (detector.cardNumberId == null && detector.expiryId == null &&
            detector.expiryMonthId == null && detector.expiryYearId == null &&
            detector.cvvId == null
        ) {
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

        // Add a dataset for each card
        for (card in cards) {
            val datasetBuilder = Dataset.Builder()

            // Standard Dropdown RemoteViews
            val remoteViews = RemoteViews(packageName, R.layout.autofill_dropdown_item).apply {
                setTextViewText(R.id.autofill_title, card.nickname)
                val last4 = if (card.cardNumber.length >= 4) card.cardNumber.takeLast(4) else card.cardNumber
                val sub = if (card.expiry.isNotEmpty()) "•••• $last4  |  Exp: ${card.expiry}" else "•••• $last4"
                setTextViewText(R.id.autofill_subtitle, sub)
            }

            // Keyboard Inline Chip (Android 11+)
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

                    if (card.cardNumber.length >= 4) {
                        contentBuilder.setSubtitle("•••• ${card.cardNumber.takeLast(4)}")
                    }

                    val slice = contentBuilder.build().slice
                    inlinePresentation = InlinePresentation(slice, spec, false)
                    datasetBuilder.setInlinePresentation(inlinePresentation)
                } catch (e: Exception) {
                    // Fall back to dropdown presentation on any UI version mismatch
                }
            }

            // Parse expiry into MM and YY
            val expiryParts = card.expiry.split('/')
            val expiryMonth = if (expiryParts.isNotEmpty()) expiryParts[0].trim() else ""
            val expiryYear = if (expiryParts.size > 1) expiryParts[1].trim() else ""

            // Bind values and inline presentations to all detected fields
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
        // Vault items are managed inside the app only
        callback.onSuccess()
    }

    private class CreditCardFieldDetector {
        var cardNumberId: AutofillId? = null
        var expiryId: AutofillId? = null
        var expiryMonthId: AutofillId? = null
        var expiryYearId: AutofillId? = null
        var cvvId: AutofillId? = null
        var holderId: AutofillId? = null

        fun traverse(node: AssistStructure.ViewNode) {
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

            // Raw combined text from all sources
            val raw = "$hintText $idEntry $text $contentDesc $className $htmlAttrs".lowercase()
            // Normalized text with delimiters replaced by spaces for clean token matching
            val norm = raw.replace('_', ' ').replace('-', ' ').replace('/', ' ').replace('.', ' ')

            // ── 1. CVV / Security Code (Check first to avoid being swallowed) ──
            val isCvv = hints.any {
                it.contains("securitycode") || it.contains("csc") || it.contains("cvv") || it.contains("cvc")
            } || raw.contains("cvv") || raw.contains("cvc") || raw.contains("cvn") ||
                 raw.contains("cid") || raw.contains("csc") || raw.contains("security_code") ||
                 raw.contains("security-code") || norm.contains("security code") ||
                 norm.contains("sec code") || norm.contains("card verification") ||
                 norm.contains("verification code")

            if (isCvv) {
                if (cvvId == null || node.isFocused) cvvId = node.autofillId
            }
            // ── 2. Expiry Month (Separate Month field e.g. <select name="month"> or MM input) ──
            else if (hints.any { it.contains("expirationmonth") || it.contains("exp-month") || it.contains("exp_month") } ||
                raw.contains("exp_month") || raw.contains("exp-month") || raw.contains("expmonth") ||
                raw.contains("expiry_month") || raw.contains("expiry-month") || raw.contains("expirymonth") ||
                norm.contains("exp month") || norm.contains("expiry month") || norm.contains("expiration month") ||
                (hintText.trim() == "mm" && (norm.contains("exp") || norm.contains("card") || norm.contains("valid"))) ||
                (idEntry == "month" && (norm.contains("exp") || norm.contains("card") || norm.contains("valid")))
            ) {
                if (expiryMonthId == null || node.isFocused) expiryMonthId = node.autofillId
            }
            // ── 3. Expiry Year (Separate Year field e.g. <select name="year"> or YY input) ──
            else if (hints.any { it.contains("expirationyear") || it.contains("exp-year") || it.contains("exp_year") } ||
                raw.contains("exp_year") || raw.contains("exp-year") || raw.contains("expyear") ||
                raw.contains("expiry_year") || raw.contains("expiry-year") || raw.contains("expiryyear") ||
                norm.contains("exp year") || norm.contains("expiry year") || norm.contains("expiration year") ||
                ((hintText.trim() == "yy" || hintText.trim() == "yyyy") && (norm.contains("exp") || norm.contains("card") || norm.contains("valid"))) ||
                (idEntry == "year" && (norm.contains("exp") || norm.contains("card") || norm.contains("valid")))
            ) {
                if (expiryYearId == null || node.isFocused) expiryYearId = node.autofillId
            }
            // ── 4. Expiry Date (Full MM/YY Field - Single unified date) ──
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
            // ── 5. Card Number ──
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
            // ── 6. Cardholder Name ──
            else if (hints.any {
                it.contains("creditcardholdername") || it.contains("holdername") || it.contains("cc-name")
            } || raw.contains("card_holder") || raw.contains("card-holder") || raw.contains("cardholder") ||
                 norm.contains("card holder") || norm.contains("holder name") ||
                 norm.contains("name on card")
            ) {
                if (holderId == null || node.isFocused) holderId = node.autofillId
            }

            for (i in 0 until node.childCount) {
                traverse(node.getChildAt(i))
            }
        }
    }
}
