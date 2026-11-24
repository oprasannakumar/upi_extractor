import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import '../models/account_mapping.dart';
import '../models/category_mapping.dart';
import '../models/upi_transaction.dart';
import 'category_mapping_service.dart';
import 'mapping_service.dart';

class UpiExtractorService {
  /// Local on-device OCR using Google ML Kit
  static Future<UpiTransaction> extractFromImage(
    String imagePath,
    List<AccountMapping> currentMappings, {
    List<CategoryMapping>? categoryMappings,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      return parseRecognizedText(
        recognizedText.text,
        currentMappings,
        categoryMappings: categoryMappings,
      );
    } finally {
      await textRecognizer.close();
    }
  }

  /// Pure deterministic parsing engine for UPI text
  static UpiTransaction parseRecognizedText(
    String rawText,
    List<AccountMapping> mappings, {
    List<CategoryMapping>? categoryMappings,
  }) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final lowerText = rawText.toLowerCase();

    // 1. Detect App
    String app = "UPI";
    if (lowerText.contains('phonepe') || lowerText.contains('@ybl') || lowerText.contains('@ibl')) {
      app = "PhonePe";
    } else if (lowerText.contains('google pay') || lowerText.contains('gpay') || lowerText.contains('@ok')) {
      app = "Google Pay";
    } else if (lowerText.contains('paytm')) {
      app = "Paytm";
    } else if (lowerText.contains('cred')) {
      app = "CRED";
    } else if (lowerText.contains('bhim')) {
      app = "BHIM";
    } else if (lowerText.contains('amazon pay') || lowerText.contains('@apl')) {
      app = "Amazon Pay";
    }

    // 2. Detect Direction
    String direction = "OUT";
    if (lowerText.contains('received from') ||
        lowerText.contains('credited to') ||
        lowerText.contains('received successfully')) {
      direction = "IN";
    } else if (lowerText.contains('paid to') ||
        lowerText.contains('debited from') ||
        lowerText.contains('payment to') ||
        lowerText.contains('recharge successful') ||
        lowerText.contains('mobile recharged') ||
        lowerText.contains('bill paid') ||
        lowerText.contains('transfer to')) {
      direction = "OUT";
    }

    // 3. Extract Account Number Digits (needed for amount extraction as well)
    String extractedAccDigits = "";
    final maskedAccRegex = RegExp(r'[xX*]{2,}(\d{2,4})');
    final maskedMatch = maskedAccRegex.firstMatch(rawText);
    if (maskedMatch != null) {
      extractedAccDigits = maskedMatch.group(1)!;
    } else {
      int debitIndex = lines.indexWhere((l) => l.toLowerCase().contains('debited from'));
      if (debitIndex != -1 && debitIndex + 1 < lines.length) {
        final lineAfter = lines[debitIndex + 1];
        final numMatch = RegExp(r'(\d{2,4})').firstMatch(lineAfter);
        if (numMatch != null) {
          extractedAccDigits = numMatch.group(1)!;
        }
      }
    }

    // 4. Extract Charges & Fees
    double charges = 0.0;
    double baseRechargeAmount = 0.0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();

      // Check base amount if itemized (e.g. Recharge Amount + ₹548)
      if (lower.contains('recharge amount') ||
          lower.contains('bill amount') ||
          lower.contains('order amount') ||
          lower.contains('base amount')) {
        final m = RegExp(r'[₹\u20B9\+\s]*([0-9,]+(?:\.[0-9]{1,2})?)').firstMatch(line);
        if (m != null) {
          final val = double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
          if (val > 0) baseRechargeAmount = val;
        } else if (i + 1 < lines.length) {
          final mNext = RegExp(r'([0-9,]+(?:\.[0-9]{1,2})?)').firstMatch(lines[i + 1]);
          if (mNext != null) {
            final val = double.tryParse(mNext.group(1)!.replaceAll(',', '')) ?? 0;
            if (val > 0) baseRechargeAmount = val;
          }
        }
      }

      // Check fees / charges (Service fee, Convenience fee, Platform fee, GST)
      if (lower.contains('fee') ||
          lower.contains('convenience') ||
          lower.contains('service charge') ||
          lower.contains('platform fee')) {
        // Find number on this line
        final m = RegExp(r'(?:[\+\₹\u20B9\s]|^)([0-9]+(?:\.[0-9]{1,2})?)\b').allMatches(line);
        for (final match in m) {
          final val = double.tryParse(match.group(1)!) ?? 0;
          if (val > 0 && val < 500) {
            charges += val;
            break;
          }
        }
      }
    }

    // 5. Extract Amount (Multi-tier resilient engine)
    double amount = baseRechargeAmount > 0
        ? baseRechargeAmount
        : _extractAmount(lines, rawText, extractedAccDigits);

    // 6. Extract Date
    String date = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final dateNamedMonthRegex = RegExp(
      r'(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4})',
      caseSensitive: false,
    );
    final matchNamed = dateNamedMonthRegex.firstMatch(rawText);
    if (matchNamed != null) {
      try {
        final parsed = DateFormat('d MMM yyyy').parseLoose(matchNamed.group(1)!);
        date = DateFormat('dd-MM-yyyy').format(parsed);
      } catch (_) {
        date = matchNamed.group(1)!;
      }
    } else {
      final dateNumericRegex = RegExp(r'(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})');
      final matchNumeric = dateNumericRegex.firstMatch(rawText);
      if (matchNumeric != null) {
        String day = matchNumeric.group(1)!.padLeft(2, '0');
        String month = matchNumeric.group(2)!.padLeft(2, '0');
        String year = matchNumeric.group(3)!;
        if (year.length == 2) year = '20$year';
        date = '$day-$month-$year';
      }
    }

    // 7. Extract Payee / Service Name
    String name = "";

    // Priority A: Mobile Recharged / Bill Paid
    int rechargeIndex = lines.indexWhere((l) =>
        l.toLowerCase().contains('mobile recharged') ||
        l.toLowerCase().contains('recharge for') ||
        l.toLowerCase().contains('bill paid to'));
    if (rechargeIndex != -1 && rechargeIndex + 1 < lines.length) {
      String candidate = lines[rechargeIndex + 1];
      candidate = _cleanNameCandidate(candidate);
      if (candidate.isNotEmpty) {
        name = candidate;
      }
    }

    // Priority B: Official Banking Name
    if (name.isEmpty) {
      final bankingNameRegex = RegExp(
        r'Banking Name\s*[:\-]?\s*([A-Za-z\s\.\-_]+)',
        caseSensitive: false,
      );
      final bnMatch = bankingNameRegex.firstMatch(rawText);
      if (bnMatch != null) {
        final bn = bnMatch.group(1)!.trim();
        if (_isValidPersonName(bn)) {
          name = bn;
        }
      }
    }

    // Priority C: Name right above UPI ID (...7459@ybl)
    if (name.isEmpty) {
      int upiIndex = lines.indexWhere((l) => l.contains('@') && !l.contains(' '));
      if (upiIndex == -1) {
        upiIndex = lines.indexWhere((l) => l.contains('@'));
      }
      if (upiIndex > 0) {
        String candidate = lines[upiIndex - 1];
        candidate = _cleanNameCandidate(candidate);
        if (_isValidPersonName(candidate)) {
          name = candidate;
        }
      }
    }

    // Priority D: Lines after "Paid to"
    if (name.isEmpty) {
      int paidToIndex = lines.indexWhere((l) {
        final lower = l.toLowerCase();
        return lower == 'paid to' || lower.startsWith('paid to') || lower == 'transfer to';
      });

      if (paidToIndex != -1) {
        for (int i = paidToIndex + 1; i < lines.length && i <= paidToIndex + 4; i++) {
          final line = lines[i];
          final cleaned = _cleanNameCandidate(line);
          if (_isValidPersonName(cleaned)) {
            name = cleaned;
            break;
          }
        }
      }
    }

    // Priority E: Uppercase candidate
    if (name.isEmpty) {
      for (final line in lines) {
        if (line.toUpperCase() == line &&
            line.length >= 4 &&
            line.length <= 35 &&
            _isValidPersonName(line)) {
          name = line;
          break;
        }
      }
    }

    // 8. Extract Transaction ID (Supports T... and NB... and numeric UTR)
    String id = "";
    final phonePeIdRegex = RegExp(r'((?:NB|T)\d{18,25})');
    final phonePeMatch = phonePeIdRegex.firstMatch(rawText);
    if (phonePeMatch != null) {
      id = phonePeMatch.group(1)!;
    } else {
      int tidIndex = lines.indexWhere((l) => l.toLowerCase().contains('transaction id'));
      if (tidIndex != -1 && tidIndex + 1 < lines.length) {
        final tidCandidate = lines[tidIndex + 1].replaceAll(' ', '');
        if (RegExp(r'^[A-Za-z0-9]{12,30}$').hasMatch(tidCandidate)) {
          id = tidCandidate;
        }
      }
    }

    if (id.isEmpty) {
      final utrRegex = RegExp(r'UTR[:\s]+(\d{12})', caseSensitive: false);
      final utrMatch = utrRegex.firstMatch(rawText);
      if (utrMatch != null) {
        id = utrMatch.group(1)!;
      }
    }

    // 9. Extract Message (Msg)
    String msg = "";
    int msgIndex = lines.indexWhere((l) => l.toLowerCase() == 'message' || l.toLowerCase() == 'note');
    if (msgIndex != -1 && msgIndex + 1 < lines.length) {
      final candidateMsg = lines[msgIndex + 1];
      if (!candidateMsg.toLowerCase().contains('transaction') &&
          !candidateMsg.toLowerCase().contains('debited') &&
          !candidateMsg.toLowerCase().contains('paid to')) {
        msg = candidateMsg;
      }
    }

    // If no msg, check if it's a mobile recharge
    if (msg.isEmpty && lowerText.contains('recharge')) {
      msg = "Mobile Recharge";
    }

    // 10. Map Account and Type
    String account = "Other Account";
    String type = "UPI";

    if (extractedAccDigits.isNotEmpty) {
      final matchedMapping = MappingService.matchAccount(extractedAccDigits, mappings);
      if (matchedMapping != null) {
        account = matchedMapping.accountName;
        type = matchedMapping.type;
      } else {
        account = "Account ending in $extractedAccDigits";
        type = "UPI";
      }
    }

    // 11. Categorize based on Msg & Payee Name
    final category = categorizeByMessage(msg, name: name, mappings: categoryMappings);

    return UpiTransaction(
      date: date,
      app: app,
      name: name.isNotEmpty ? name : "N/A",
      id: id.isNotEmpty ? id : "N/A",
      msg: msg,
      amount: amount,
      charges: charges,
      direction: direction,
      type: type,
      account: account,
      category: category,
      rawText: rawText,
    );
  }

  /// Multi-tier robust amount extractor
  static double _extractAmount(List<String> lines, String rawText, String accDigits) {
    // Tier 1: Look for amount on the "Debited from" or masked account line (e.g. XXXXXX9989 ₹500 or XXXXXX9989 500)
    int debitLineIdx = lines.indexWhere((l) =>
        l.contains('XXXXXX') ||
        l.contains('xxxxxx') ||
        (accDigits.isNotEmpty && l.contains(accDigits) && (l.contains('X') || l.contains('x') || l.contains('*'))));

    if (debitLineIdx != -1) {
      for (int i = debitLineIdx; i <= debitLineIdx + 1 && i < lines.length; i++) {
        final line = lines[i];
        String cleaned = line;
        if (accDigits.isNotEmpty) {
          cleaned = cleaned.replaceAll(accDigits, '');
        }
        cleaned = cleaned.replaceAll(RegExp(r'[xX*]{2,}'), '');

        final numMatch = RegExp(r'([0-9]{1,3}(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)')
            .allMatches(cleaned);
        for (final m in numMatch) {
          final val = double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
          if (val > 0 && val < 10000000) {
            return val;
          }
        }
      }
    }

    // Tier 2: Look for currency symbols (including common OCR misrecognitions of ₹: F, ?, *, =, ~)
    final currencyRegex = RegExp(
      r'(?:[₹\u20B9]|INR|Rs\.?|Re\.?|[F\?\*=\~])\s*([0-9]{1,3}(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );

    final List<double> candidateAmounts = [];
    for (final line in lines) {
      if (line.contains('KB/s') ||
          line.contains('MB/s') ||
          line.contains('5G') ||
          line.contains('4G') ||
          (line.contains('%') && !line.contains('₹')) ||
          line.contains('VoLTE')) {
        continue;
      }

      final matches = currencyRegex.allMatches(line);
      for (final m in matches) {
        final val = double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
        if (val > 0 && val < 10000000) {
          candidateAmounts.add(val);
        }
      }
    }

    if (candidateAmounts.isNotEmpty) {
      final Map<double, int> freq = {};
      for (final a in candidateAmounts) {
        freq[a] = (freq[a] ?? 0) + 1;
      }
      final sorted = freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return sorted.first.key;
    }

    // Tier 3: Look for standalone numbers on the Payee line
    int paidToIndex = lines.indexWhere((l) => l.toLowerCase().startsWith('paid to'));
    if (paidToIndex != -1 && paidToIndex + 1 < lines.length) {
      final payeeLine = lines[paidToIndex + 1];
      final numMatches = RegExp(r'([0-9]{2,7}(?:\.[0-9]{1,2})?)').allMatches(payeeLine);
      for (final m in numMatches) {
        final val = double.tryParse(m.group(1)!) ?? 0;
        if (val > 0) return val;
      }
    }

    // Tier 4: Search all lines for standalone numbers between 10 and 1,000,000
    for (final line in lines) {
      if (line.contains('KB/s') ||
          line.contains('MB/s') ||
          line.contains('5G') ||
          line.contains('4G') ||
          line.contains('UTR') ||
          line.contains('ID') ||
          line.contains('PM') ||
          line.contains('AM')) {
        continue;
      }

      final standaloneMatch = RegExp(r'\b([0-9]{2,6}(?:\.[0-9]{1,2})?)\b').allMatches(line);
      for (final m in standaloneMatch) {
        final str = m.group(1)!;
        if (str == accDigits || str == '2024' || str == '2025' || str == '2026' || str == '2027') {
          continue;
        }
        final val = double.tryParse(str) ?? 0;
        if (val > 0) return val;
      }
    }

    return 0.0;
  }

  static String _cleanNameCandidate(String line) {
    String text = line.trim();
    text = text.replaceAll(RegExp(r'[₹\u20B9INRrs\.\s0-9,]+$'), '').trim();

    final parts = text.split(' ');
    if (parts.length > 1 && parts.first.length <= 2 && parts.first == parts.first.toUpperCase()) {
      text = parts.sublist(1).join(' ').trim();
    }

    return text;
  }

  static bool _isValidPersonName(String candidate) {
    final lower = candidate.toLowerCase().trim();
    if (lower.length < 3 || lower.length > 40) return false;

    if (lower.contains('am') || lower.contains('pm') || lower.contains(':')) return false;

    if (lower.contains('jan') ||
        lower.contains('feb') ||
        lower.contains('mar') ||
        lower.contains('apr') ||
        lower.contains('may') ||
        lower.contains('jun') ||
        lower.contains('jul') ||
        lower.contains('aug') ||
        lower.contains('sep') ||
        lower.contains('oct') ||
        lower.contains('nov') ||
        lower.contains('dec') ||
        lower.contains('202') ||
        lower.contains('203')) {
      return false;
    }

    if (lower.contains('transaction') ||
        lower.contains('successful') ||
        lower.contains('failed') ||
        lower.contains('transfer') ||
        lower.contains('details') ||
        lower.contains('paid to') ||
        lower.contains('debited') ||
        lower.contains('credited') ||
        lower.contains('message') ||
        lower.contains('view') ||
        lower.contains('history') ||
        lower.contains('split') ||
        lower.contains('share') ||
        lower.contains('receipt')) {
      return false;
    }

    final digitCount = candidate.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digitCount > 3) return false;

    return true;
  }

  static String categorizeByMessage(
    String msg, {
    String name = '',
    List<CategoryMapping>? mappings,
  }) {
    final cat = CategoryMappingService.categorize(msg, name: name, mappings: mappings);
    if (cat != 'Transfer to Others') return cat;
    return _oldCategorize(msg, name: name);
  }

  static String _oldCategorize(String msg, {String name = ''}) {
    final lowerMsg = msg.toLowerCase().trim();
    final lowerName = name.toLowerCase().trim();

    // 2. Advance Salary / Salary / Personal transfers
    if (lowerMsg.contains('advance salary') ||
        lowerMsg.contains('salary') ||
        lowerMsg.contains('advance') ||
        lowerMsg.contains('wage') ||
        lowerMsg.contains('paisa') ||
        lowerMsg.contains('money')) {
      return "Transfer to Others";
    }

    // 3. Fruits
    if (lowerMsg.contains('lemon') ||
        lowerMsg.contains('amla') ||
        lowerMsg.contains('usiri') ||
        lowerMsg.contains('apple') ||
        lowerMsg.contains('banana') ||
        lowerMsg.contains('ariti') ||
        lowerMsg.contains('mango') ||
        lowerMsg.contains('mamidi') ||
        lowerMsg.contains('orange') ||
        lowerMsg.contains('papaya') ||
        lowerMsg.contains('grapes') ||
        lowerMsg.contains('guava') ||
        lowerMsg.contains('sapota') ||
        lowerMsg.contains('fruit') ||
        lowerName.contains('fruit')) {
      return "Fruits";
    }

    // 4. Vegetables
    if (lowerMsg.contains('kothimera') ||
        lowerMsg.contains('coriander') ||
        lowerMsg.contains('carrot') ||
        lowerMsg.contains('beetroot') ||
        lowerMsg.contains('chamadumpa') ||
        lowerMsg.contains('keera') ||
        lowerMsg.contains('cucumber') ||
        lowerMsg.contains('beerak') ||
        lowerMsg.contains('bendi') ||
        lowerMsg.contains('bhindi') ||
        lowerMsg.contains('okra') ||
        lowerMsg.contains('capcicum') ||
        lowerMsg.contains('capsicum') ||
        lowerMsg.contains('dosakai') ||
        lowerMsg.contains('dosakaya') ||
        lowerMsg.contains('kandha') ||
        lowerMsg.contains('kanda') ||
        lowerMsg.contains('tomato') ||
        lowerMsg.contains('tamata') ||
        lowerMsg.contains('onion') ||
        lowerMsg.contains('ullipaya') ||
        lowerMsg.contains('potato') ||
        lowerMsg.contains('aloo') ||
        lowerMsg.contains('brinjal') ||
        lowerMsg.contains('vankaya') ||
        lowerMsg.contains('spinach') ||
        lowerMsg.contains('palak') ||
        lowerMsg.contains('mirchi') ||
        lowerMsg.contains('chilli') ||
        lowerMsg.contains('vegetable') ||
        lowerMsg.contains('veggie') ||
        lowerName.contains('vegetable') ||
        lowerName.contains('sabzi')) {
      return "Vegetables";
    }

    // 5. Dairy
    if (lowerMsg.contains('curd') ||
        lowerMsg.contains('curd packer') ||
        lowerMsg.contains('packer') ||
        lowerMsg.contains('milk') ||
        lowerMsg.contains('dairy') ||
        lowerMsg.contains('parlour') ||
        lowerMsg.contains('parlor') ||
        lowerMsg.contains('paneer') ||
        lowerMsg.contains('ghee') ||
        lowerMsg.contains('butter') ||
        lowerMsg.contains('lassi') ||
        lowerName.contains('milk') ||
        lowerName.contains('dairy')) {
      return "Dairy";
    }

    // 6. Food & Dining
    if (lowerMsg.contains('food') ||
        lowerMsg.contains('dinner') ||
        lowerMsg.contains('lunch') ||
        lowerMsg.contains('breakfast') ||
        lowerMsg.contains('swiggy') ||
        lowerMsg.contains('zomato') ||
        lowerMsg.contains('tea') ||
        lowerMsg.contains('chai') ||
        lowerMsg.contains('coffee') ||
        lowerMsg.contains('restaurant') ||
        lowerMsg.contains('cafe')) {
      return "Food & Dining";
    }

    // 7. Groceries
    if (lowerMsg.contains('grocer') ||
        lowerMsg.contains('blinkit') ||
        lowerMsg.contains('zepto') ||
        lowerMsg.contains('instamart') ||
        lowerMsg.contains('supermarket') ||
        lowerMsg.contains('mart')) {
      return "Groceries";
    }

    // 8. Housing & Rent
    if (lowerMsg.contains('rent') ||
        lowerMsg.contains('maintenance') ||
        lowerMsg.contains('pg') ||
        lowerMsg.contains('flat') ||
        lowerMsg.contains('house')) {
      return "Housing & Rent";
    }

    // 9. Fuel & Transport
    if (lowerMsg.contains('petrol') ||
        lowerMsg.contains('fuel') ||
        lowerMsg.contains('diesel') ||
        lowerMsg.contains('cng') ||
        lowerMsg.contains('auto') ||
        lowerMsg.contains('cab') ||
        lowerMsg.contains('uber') ||
        lowerMsg.contains('ola') ||
        lowerMsg.contains('rapido') ||
        lowerMsg.contains('toll')) {
      return "Fuel & Transport";
    }

    // 10. Shopping
    if (lowerMsg.contains('amazon') ||
        lowerMsg.contains('flipkart') ||
        lowerMsg.contains('myntra') ||
        lowerMsg.contains('meesho') ||
        lowerMsg.contains('shopping') ||
        lowerMsg.contains('clothes')) {
      return "Shopping";
    }

    // 11. Health & Medical
    if (lowerMsg.contains('doctor') ||
        lowerMsg.contains('medicine') ||
        lowerMsg.contains('pharmacy') ||
        lowerMsg.contains('hospital') ||
        lowerMsg.contains('lab') ||
        lowerMsg.contains('clinic')) {
      return "Health & Medical";
    }

    // 12. Financial & EMI
    if (lowerMsg.contains('emi') ||
        lowerMsg.contains('loan') ||
        lowerMsg.contains('credit card') ||
        lowerMsg.contains('card payment') ||
        lowerMsg.contains('mutual fund') ||
        lowerMsg.contains('investment')) {
      return "Financial & EMI";
    }

    return "Transfer to Others";
  }
}
