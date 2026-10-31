package com.example.card_vault

data class AutofillCard(
    val nickname: String,
    val bankName: String,
    val cardNumber: String,
    val expiry: String,
    val cvv: String,
    val cardHolder: String
)

data class AutofillPassword(
    val nickname: String,
    val website: String,
    val username: String,
    val password: String
)

object AutofillBridge {
    @Volatile
    var isUnlocked: Boolean = false
        private set

    private val _cards = mutableListOf<AutofillCard>()
    private val _passwords = mutableListOf<AutofillPassword>()

    @Synchronized
    fun sync(unlocked: Boolean, rawCards: List<Map<String, Any?>>?, rawPasswords: List<Map<String, Any?>>? = null) {
        isUnlocked = unlocked
        _cards.clear()
        _passwords.clear()
        if (unlocked) {
            if (rawCards != null) {
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
            if (rawPasswords != null) {
                for (map in rawPasswords) {
                    val nickname = map["nickname"] as? String ?: ""
                    val website = map["website"] as? String ?: ""
                    val username = map["username"] as? String ?: ""
                    val password = map["password"] as? String ?: ""
                    if (username.isNotEmpty() || password.isNotEmpty()) {
                        _passwords.add(AutofillPassword(nickname, website, username, password))
                    }
                }
            }
        }
    }

    @Synchronized
    fun getCards(): List<AutofillCard> {
        return if (isUnlocked) _cards.toList() else emptyList()
    }

    @Synchronized
    fun getPasswords(): List<AutofillPassword> {
        return if (isUnlocked) _passwords.toList() else emptyList()
    }

    @Synchronized
    fun clear() {
        isUnlocked = false
        _cards.clear()
        _passwords.clear()
    }
}
