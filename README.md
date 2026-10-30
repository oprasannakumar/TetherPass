# 🛡️ CardVault

> **Zero-Knowledge Payment Card & Bank Account Manager with Biometric Security and Real-Time Desktop Autofill Companion**

CardVault is a privacy-first, zero-knowledge vault for managing credit cards, debit cards, bank accounts (with multiple IFSC codes), and credentials. All data is encrypted locally on your device with AES-256-CBC and derived via PBKDF2 (10,000 rounds). 

CardVault includes a companion **Manifest V3 Browser Extension** for Windows, allowing seamless webpage autofill gated by real-time biometric authorization from your phone.

---

## 🚀 Key Features

### 📱 Android Mobile Application (Flutter)
- **Zero-Knowledge Encryption**: AES-256-CBC local encryption with user-controlled Master Password and Recovery Key.
- **Biometric Authentication**: Fingerprint / Face Unlock gating all access and operations.
- **Multi-Account NetBanking**: Add multiple bank account numbers and corresponding IFSC codes in a single form with swipe-to-delete.
- **Card Scanner & NFC**: Card number extraction via Google ML Kit OCR and contactless NFC reading.
- **Encrypted Google Drive Sync**: Automatic cloud sync using Google Drive's hidden `drive.appdata` folder.
- **Offline Backups**: Password-protected encrypted JSON exports (`card_vault_backup_v2.json`).
- **Native Android Autofill Service**: Autofills payment details directly across Android apps.
- **Interactive Spotlight Tour**: Step-by-step user walkthrough explaining all security controls.

### 💻 Windows Browser Extension (Chrome & Edge MV3)
- **Webpage Autofill**: Floating inline suggestion chips for Card Number, Expiry Date (MM/YY), CVV, Cardholder Name, Bank Account Numbers, IFSC codes, User IDs, and Passwords.
- **Real-Time Mobile Push Confirmation**: Clicking sync sends an instant confirmation pop-up directly to your phone.
- **Multi-Device Smart Routing**: If you use CardVault on multiple phones, choose which device receives the prompt, or broadcast to all with automatic conflict-free dismiss.
- **Volatile RAM Cache**: Plaintext passwords and cards are stored strictly in memory and wiped immediately when your mobile vault locks or expires.

---

## 🔒 Security Architecture

```
┌─────────────────────────────────┐               ┌─────────────────────────────────┐
│     Windows Browser Extension   │               │       CardVault Mobile App      │
│  - Volatile RAM Cache only      │               │  - Master Password + Biometrics │
│  - Manifest V3 Service Worker   │               │  - AES-256-CBC Zero-Knowledge   │
└────────────────┬────────────────┘               └────────────────┬────────────────┘
                 │                                                 │
                 │ 1. Request Sync ("PENDING")                     │
                 ├─────────────────────────┐     ┌─────────────────┤
                 │                         ▼     ▼                 │
                 │                   Google Drive                  │
                 │         (card_vault_access_request.json)        │
                 │                         ▲     │                 │
                 │ 4. Read Approval        │     │ 2. Detect Alert │
                 ├─────────────────────────┘     └─────────────────┤
                 │                                                 │
                 │                                3. Approve with  │
                 │                                   Fingerprint   │
                 ▼                                                 ▼
       [ Decrypt & Autofill ]                             [ Session Active ]
```

---

## 📂 Repository Structure

```text
card_vault/
├── android/                 # Native Android Gradle configuration & Autofill service
├── assets/                  # Offline BIN card identification database
├── lib/                     # Flutter architecture
│   ├── models/              # VaultItem, BankAccount, CardTier
│   ├── screens/             # Home, Unlock, Settings, Browser Extension, Onboarding
│   ├── services/            # Crypto, Database, Drive, Biometric Auth, Device Identity
│   └── widgets/             # Spotlight tour, custom credit card widgets
├── browser_extension/       # Manifest V3 Chrome / Edge Windows Companion
│   ├── icons/               # Extension icons
│   ├── manifest.json        # Manifest V3 config with OAuth2
│   ├── background.js        # RAM cache & mobile session manager
│   ├── content.js           # Floating inline autofill suggestion chips
│   ├── content.css          # Autofill chip styling
│   ├── crypto_utils.js      # Pure WebCrypto AES-256-CBC PBKDF2 decryption
│   ├── drive_client.js      # Google Drive API v3 client
│   ├── popup.html           # Modern extension popup interface
│   ├── popup.js             # Real-time push handshake controller
│   └── test_payment_page.html # Offline verification demo form
├── pubspec.yaml             # Flutter dependencies
└── README.md
```

---

## 🛠️ Getting Started

### 1. Mobile App Setup (Android)

**Prerequisites:**
- Flutter SDK (>= 3.0.0)
- Android SDK (API 34)
- JDK 17

**Build & Run:**
```bash
# Clone the repository
git clone https://github.com/oprasannakumar/CardVault.git
cd CardVault

# Install dependencies
flutter pub get

# Run on connected Android device
flutter run

# Build release APK
flutter build apk --release
```

### 2. Browser Extension Setup (Windows Chrome / Edge)

1. Open your browser and navigate to `chrome://extensions/` (or `edge://extensions/`).
2. Toggle **Developer mode** (top right) to **ON**.
3. Click **Load unpacked** and select the `browser_extension` folder inside this repository.
4. Pin the **CardVault** icon (`CV`) to your browser toolbar.

---

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.
