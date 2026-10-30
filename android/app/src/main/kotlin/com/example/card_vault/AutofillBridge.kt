package com.example.card_vault

data class AutofillCard(
    val nickname: String,
    val bankName: String,
    val cardNumber: String,
    val expiry: String,
    val cvv: String,
    val cardHolder: String
)

object AutofillBridge {
    @Volatile
    var isUnlocked: Boolean = false
        private set

    private val _cards = mutableListOf<AutofillCard>()

    @Synchronized
    fun sync(unlocked: Boolean, rawCards: List<Map<String, Any?>>?) {
        isUnlocked = unlocked
        _cards.clear()
        if (unlocked && rawCards != null) {
            for (map in rawCards) {
                val nickname = map["nickname"] as? String ?: "Card"
                val bankName = map["bankName"] as? String ?: ""
                val cardNumber = (map["cardNumber"] as? String ?: "").replace(" ", "")
                val expiry = map["expiry"] as? String ?: ""
                val cvv = map["cvv"] as? String ?: ""
                val cardHolder = map["cardHolder"] as? String ?: ""
                if (cardNumber.isNotEmpty()) {
                    _cards.add(AutofillCard(nickname, bankName, cardNumber, expiry, cvv, cardHolder))
                }
            }
        }
    }

    @Synchronized
    fun getCards(): List<AutofillCard> {
        return if (isUnlocked) _cards.toList() else emptyList()
    }

    @Synchronized
    fun clear() {
        isUnlocked = false
        _cards.clear()
    }
}
