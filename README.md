# 📱 UPI Extractor

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An intelligent, high-performance Android mobile application built with Flutter to extract, organize, and synchronize financial transaction details from UPI payment receipts and screenshots (PhonePe, Google Pay, Paytm, BHIM, Amazon Pay) directly into Google Sheets.

Featuring a **3-tier hybrid AI/OCR architecture**, offline edge processing, direct system-level **Android Share Intent integration**, and automatic **Transaction ID deduplication** with Google Sheets ledger sync.

---

## 📥 Download Pre-built APKs

The latest release binaries are available directly in this repository:

| Binary | Target Architecture | Size | Recommended For | Direct Link |
|---|---|---|---|---|
| **`UpiExtractor-arm64.apk`** | `arm64-v8a` | **~31.3 MB** | **All modern Android smartphones** (Fastest loading & smallest download) | [Download ARM64 APK](apk/UpiExtractor-arm64.apk) |
| **`UpiExtractor.apk`** | Universal | **~83.6 MB** | Any Android device (Includes all architectures) | [Download Universal APK](apk/UpiExtractor.apk) |

---

## ✨ Key Features

### ⚡ 1. Direct System Share Intent (Instant Frame-0 Processing)
- Share screenshots directly from payment apps (PhonePe, GPay, Paytm) or your Photo Gallery without needing to launch the app manually.
- **Optimized Cold-Start**: Unblocked startup pipeline ensures instant UI rendering upon sharing, running settings reads and account mappings concurrently.

### 🤖 2. Triple-Engine Hybrid AI Pipeline
- **Groq Cloud AI (Default)**: Blazing-fast cloud extraction using high-efficiency open models (`qwen/qwen-2.5-32b`, `llama-3.3-70b-versatile`).
- **Google Gemini API**: Native multimodal vision extraction using `gemini-2.5-flash` for complex or blurry receipts.
- **Local ML Kit OCR (Offline Fallback)**: Full on-device text recognition using Google ML Kit Vision when working without internet connection.
- Automatic graceful fallback: If Cloud AI fails or is offline, the app transparently falls back to local OCR parsing.

### 💸 3. Itemized Fee & Charges Separation
- Accurately splits the **Base Purchase/Recharge Amount** from convenience fees, platform fees, and GST charges (e.g. mobile recharges, utility bill payments).
- Clean numerical formatting: Charges are recorded separately and added into the ledger.

### 📊 4. Smart Expense Categorization & Regional Terminology
- Auto-categorizes transactions using transaction messages, notes, and merchant names.
- Built-in recognition for Indian regional and Telugu grocery & vegetable terminology:
  - **Fruits**: Lemons, Amla, Apple, Banana, etc.
  - **Vegetables**: Kothimera, Carrot, Beetroot, Chamadumpa, Keera, Nethi Beerakaya, Bhendi, Capsicum, Dosakaya, etc.
  - **Dairy**: Milk parlours, curd packets, Vijaya / Heritage / Amul dairy.
  - **Bills & Utilities**: Mobile recharge, electricity, broadband, DTH.
  - **Transfers & Dining**: Advance salary, rent, restaurants, food delivery.

### 🏢 5. Masked Account Resolution & Mode Mapping
- Matches masked account numbers (`XXXXXX49`, `XXXXXX9989`) against user-defined account rules.
- Automatically maps accounts to custom names and payment instruments (e.g. `HDFC PhonePe (Credit Card)` vs `SBI Savings (UPI)`).

### 📑 6. Google Sheets Auto-Sync with Transaction ID Deduplication
- Directly connects via official Google OAuth2.
- Automatically locates or creates the spreadsheet named **`"account ledger"`** and the **`"Details"`** tab.
- **Smart Deduplication**: Checks Column F (`Transaction ID`) before appending. If the transaction already exists in the sheet, it fetches the existing record and updates local history instead of creating duplicate rows.
- Saves clean text direction (**`OUT`** / **`IN`**) without emoji noise.

### 🔄 7. Batch Extraction & Single Re-extraction
- Share multiple receipts at once to batch process large histories with live queue progression.
- Save entire batches into history and re-extract individual failed transactions without reprocessing the entire batch.

### 📅 8. Date-Filtered History & Direct Sheet Fetch
- Filter extraction history by date range or specific dates.
- Pull historical transactions directly from Google Sheets for any selected date to verify ledger parity.

### 🎨 9. Reactive Material 3 Dark/Light UI
- Dynamic AppBars with reactive Google Profile Avatar showing account photo or initials with real-time connection status.
- Ergonomic full-width **Copy Output** button and secondary action rows (**Sync to Sheets**, **Edit Values**).

---

## 📊 Google Sheets 13-Column Ledger Schema

The application structures and synchronizes every transaction to the `"account ledger"` > `"Details"` sheet using the following 13 columns:

| Col | Header | Description | Example |
|---|---|---|---|
| **A** | `Date` | Transaction date (`dd-MM-yyyy`) | `22-11-2026` |
| **B** | `app` | UPI Application name | `PhonePe` |
| **C** | `Name` | Payee / Recipient / Merchant name | `Airtel Prepaid` |
| **D** | `direction` | Payment direction (`OUT` or `IN`) | `OUT` |
| **E** | `Amount` | Base transaction amount | `548` |
| **F** | `Transaction ID`| Unique Bank / UPI Reference ID | `T2611221930192121195449` |
| **G** | `Status` | Transaction status | `Success` |
| **H** | `Message` | Note, memo, or payment description | `Mobile recharge` |
| **I** | `Mode` | Payment method / instrument type | `Credit` / `UPI` |
| **J** | `Account` | Resolved account or card name | `HDFC PhonePe` |
| **K** | `Category` | Categorization tag | `Bills & Utilities` |
| **L** | `Reference` | Generated unique reference code | `REF-20261122-BUMM` |
| **M** | `Charges` | Itemized extra charges/fees | `11.46` |

---

## 🏗️ Project Architecture

```
upi_extractor/
├── android/                     # Android native project files & manifest
│   ├── app/
│   │   ├── build.gradle.kts     # Native build config with R8 & ProGuard
│   │   ├── proguard-rules.pro   # Keep rules for Flutter, Google Sign-In & ML Kit
│   │   └── src/main/AndroidManifest.xml # Share Intent filters (SEND & SEND_MULTIPLE)
├── apk/                         # Release binaries
│   ├── UpiExtractor-arm64.apk   # Modern phone split APK (31.3 MB)
│   └── UpiExtractor.apk         # Universal release APK (83.6 MB)
├── lib/
│   ├── main.dart                # App entrypoint & ReceiveSharingIntent handler
│   ├── models/                  # Domain data models
│   │   ├── account_mapping.dart # Masked account pattern definitions
│   │   ├── batch_record.dart    # Multi-transaction batch history model
│   │   └── upi_transaction.dart # Core transaction model & sheet formatters
│   ├── screens/                 # Primary UI screens
│   │   ├── account_mappings_screen.dart # Custom account rules editor
│   │   ├── batch_processing_screen.dart # Multi-screenshot queue & re-extractor
│   │   ├── extractor_screen.dart        # Single extraction, preview & output
│   │   └── history_screen.dart          # Historical records & sheet fetch
│   ├── services/                # Business logic & APIs
│   │   ├── ai_pipeline_service.dart     # Engine routing (Groq -> Gemini -> ML Kit)
│   │   ├── gemini_service.dart          # Google Gemini multimodal vision service
│   │   ├── google_sheets_service.dart   # Sheets API, Drive API & auth management
│   │   ├── groq_service.dart            # Groq Cloud API LLM service
│   │   ├── history_service.dart         # Local storage for history & batches
│   │   ├── mapping_service.dart         # Account mapping persistence
│   │   └── upi_extractor_service.dart   # Offline OCR parser & categorization
│   └── widgets/                 # Reusable UI components
│       ├── google_sheets_sheet.dart     # Google account & sync modal bottom sheet
│       └── user_profile_avatar.dart     # Reactive avatar with live auth status
└── test/                        # Automated unit & widget tests
    ├── upi_extractor_test.dart  # Extraction, charge splitting & mapping tests
    └── widget_test.dart         # Navigation & launch tests
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (>= 3.13.5)
- [Android Studio / Android SDK](https://developer.android.com/studio) (compileSdk 37, minSdk 21)
- Java 17

### Installation
1. Clone this repository:
   ```bash
   git clone https://github.com/oprasannakumar/upi_extractor.git
   cd upi_extractor
   ```
2. Install Flutter packages:
   ```bash
   flutter pub get
   ```
3. Run tests to verify the setup:
   ```bash
   flutter test
   ```
4. Run on a connected Android device:
   ```bash
   flutter run --release
   ```

---

## 🛠️ Configuration

### 1. Groq & Gemini API Keys
In `lib/services/groq_service.dart` and `lib/services/gemini_service.dart`, configure your respective API keys or customize the model endpoints through the in-app settings menu.

### 2. Google Account & Sheets Setup
- The app uses `google_sign_in` and `googleapis` (Drive v3 and Sheets v4).
- Ensure your Google Cloud Project has the **Google Sheets API** and **Google Drive API** enabled.
- Add your Android app's package name (`com.example.upi_extractor`) and SHA-1 fingerprint in the Google Cloud Console Credentials page under OAuth 2.0 Client IDs.

---

## 📦 Building Production APKs

To compile optimized release APKs with native AOT compilation, R8 shrinking, and ProGuard optimization:

### Modern Architecture Split (Recommended: ~31 MB)
```bash
flutter build apk --release --split-per-abi
```
Output located at `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

### Universal APK (~83 MB)
```bash
flutter build apk --release
```
Output located at `build/app/outputs/flutter-apk/app-release.apk`.

---

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
