import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account_mapping.dart';

class MappingService {
  static const String _storageKey = 'saved_account_mappings_v1';

  // Default initial mappings based on user specifications
  static final List<AccountMapping> defaultMappings = [
    // Bank Accounts -> Type: UPI
    AccountMapping(accountDigits: '9989', accountName: 'SBI', type: 'UPI'),
    AccountMapping(accountDigits: '9658', accountName: 'FI', type: 'UPI'),
    AccountMapping(accountDigits: '4082', accountName: 'HDFC New', type: 'UPI'),
    AccountMapping(accountDigits: '6398', accountName: 'HDFC Old', type: 'UPI'),

    // Credit Cards -> Type: Credit
    AccountMapping(accountDigits: '02', accountName: 'ICICI Amazon', type: 'Credit'),
    AccountMapping(accountDigits: '49', accountName: 'HDFC PhonePe', type: 'Credit'),
    AccountMapping(accountDigits: '2220', accountName: 'Axis Flipkart', type: 'Credit'),
    AccountMapping(accountDigits: '6109', accountName: 'Axis MyZone', type: 'Credit'),
    AccountMapping(accountDigits: '6098', accountName: 'Axis Neo', type: 'Credit'),
    AccountMapping(accountDigits: '4179', accountName: 'HDFC Millennia', type: 'Credit'),
    AccountMapping(accountDigits: '24', accountName: 'HDFC Tata Neu', type: 'Credit'),
    AccountMapping(accountDigits: '6747', accountName: 'HSBC', type: 'Credit'),
    AccountMapping(accountDigits: '08', accountName: 'ICICI Coral', type: 'Credit'),
    AccountMapping(accountDigits: '0009', accountName: 'ICICI Expressions', type: 'Credit'),
    AccountMapping(accountDigits: '8398', accountName: 'IDFC First Millenia', type: 'Credit'),
    AccountMapping(accountDigits: '65', accountName: 'Kotak League', type: 'Credit'),
    AccountMapping(accountDigits: '1244', accountName: 'Kotak Image', type: 'Credit'),
    AccountMapping(accountDigits: '37', accountName: 'SBI BPCL', type: 'Credit'),
    AccountMapping(accountDigits: '2624', accountName: 'Standard Chartered', type: 'Credit'),
    AccountMapping(accountDigits: '4707', accountName: 'RBL', type: 'Credit'),
  ];

  static Future<List<AccountMapping>> loadMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final String? rawJson = prefs.getString(_storageKey);
    if (rawJson == null) {
      // First time launch: save defaults and return
      await saveMappings(defaultMappings);
      return List.from(defaultMappings);
    }

    try {
      final List<dynamic> list = json.decode(rawJson);
      return list.map((e) => AccountMapping.fromMap(e)).toList();
    } catch (_) {
      return List.from(defaultMappings);
    }
  }

  static Future<void> saveMappings(List<AccountMapping> mappings) async {
    final prefs = await SharedPreferences.getInstance();
    final String rawJson = json.encode(mappings.map((m) => m.toMap()).toList());
    await prefs.setString(_storageKey, rawJson);
  }

  static Future<void> addOrUpdateMapping(AccountMapping newMapping) async {
    final mappings = await loadMappings();
    final index = mappings.indexWhere(
      (m) => m.accountDigits.trim() == newMapping.accountDigits.trim(),
    );

    if (index >= 0) {
      mappings[index] = newMapping;
    } else {
      mappings.insert(0, newMapping);
    }
    await saveMappings(mappings);
  }

  static Future<void> deleteMapping(String digits) async {
    final mappings = await loadMappings();
    mappings.removeWhere((m) => m.accountDigits.trim() == digits.trim());
    await saveMappings(mappings);
  }

  static Future<void> resetToDefaults() async {
    await saveMappings(defaultMappings);
  }

  /// Match extracted masked number (e.g. "XXXXXX9989" or "9989")
  /// against registered mappings. Prefers exact match, then suffix match.
  static AccountMapping? matchAccount(String extractedDigits, List<AccountMapping> mappings) {
    if (extractedDigits.isEmpty) return null;

    // 1. Check exact match
    for (final m in mappings) {
      if (m.accountDigits == extractedDigits) {
        return m;
      }
    }

    // 2. Check if extracted string ends with mapped digits (longest suffix first)
    final sortedByLen = List<AccountMapping>.from(mappings)
      ..sort((a, b) => b.accountDigits.length.compareTo(a.accountDigits.length));

    for (final m in sortedByLen) {
      if (extractedDigits.endsWith(m.accountDigits)) {
        return m;
      }
    }

    return null;
  }
}
