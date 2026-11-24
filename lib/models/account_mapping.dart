import 'dart:convert';

class AccountMapping {
  final String accountDigits; // e.g. "9989", "02"
  final String accountName;   // e.g. "SBI", "ICICI Amazon"
  final String type;          // "UPI" or "Credit" (or custom)

  AccountMapping({
    required this.accountDigits,
    required this.accountName,
    required this.type,
  });

  Map<String, dynamic> toMap() {
    return {
      'accountDigits': accountDigits,
      'accountName': accountName,
      'type': type,
    };
  }

  factory AccountMapping.fromMap(Map<String, dynamic> map) {
    return AccountMapping(
      accountDigits: map['accountDigits'] ?? '',
      accountName: map['accountName'] ?? '',
      type: map['type'] ?? 'UPI',
    );
  }

  String toJson() => json.encode(toMap());

  factory AccountMapping.fromJson(String source) =>
      AccountMapping.fromMap(json.decode(source));

  AccountMapping copyWith({
    String? accountDigits,
    String? accountName,
    String? type,
  }) {
    return AccountMapping(
      accountDigits: accountDigits ?? this.accountDigits,
      accountName: accountName ?? this.accountName,
      type: type ?? this.type,
    );
  }
}
