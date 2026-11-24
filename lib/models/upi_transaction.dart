import 'dart:convert';
import 'dart:math';

class UpiTransaction {
  String date;
  String app;
  String name;
  String id;
  String msg;
  double amount;
  double charges;
  String direction;
  String type;
  String account;
  String category;
  String ref;
  String? rawText;
  DateTime timestamp;

  UpiTransaction({
    required this.date,
    required this.app,
    required this.name,
    required this.id,
    required this.msg,
    required this.amount,
    required this.charges,
    required this.direction,
    required this.type,
    required this.account,
    required this.category,
    String? ref,
    this.rawText,
    DateTime? timestamp,
  })  : timestamp = timestamp ?? DateTime.now(),
        ref = ref ?? generateRef(date, id);

  static String generateRef(String dateStr, String idStr) {
    String datePart = '20261122';
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      if (parts[2].length == 4) {
        datePart = '${parts[2]}${parts[1].padLeft(2, '0')}${parts[0].padLeft(2, '0')}';
      }
    }

    String suffix = '';
    if (idStr.isNotEmpty && idStr != 'N/A') {
      int hash = 5381;
      for (int i = 0; i < idStr.length; i++) {
        hash = ((hash << 5) + hash) + idStr.codeUnitAt(i);
      }
      hash = hash.abs();
      const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      for (int i = 0; i < 4; i++) {
        suffix += chars[(hash ~/ pow(36, i)) % chars.length];
      }
    } else {
      const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final rnd = Random();
      for (int i = 0; i < 4; i++) {
        suffix += chars[rnd.nextInt(chars.length)];
      }
    }

    return 'REF-$datePart-$suffix';
  }

  /// Format with optional batch index:
  /// --- Transaction 1 ---
  /// 📅 Date: 22-11-2026
  /// 📱 App: PhonePe
  /// 👤 Name: NAGARANI KONDURU
  /// 🆔 ID: T2611221930192121195449
  /// 📝 Msg: advance salary
  /// 💰 Amount: 500
  /// 💸 Charges: 0
  /// 📊 Direction: 🔴 OUT
  /// ⇄ Type: UPI
  /// 🏢 Account: SBI
  /// 🏷️ Category: Transfer to Others
  /// 🔗 Ref: REF-20261122-BUMM
  String toFormattedString({int? transactionIndex}) {
    final amountStr = amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(2);
    final chargesStr = charges % 1 == 0 ? charges.toInt().toString() : charges.toStringAsFixed(2);

    final displayMsg = msg.trim().isEmpty ? 'null' : msg.trim();

    final buffer = StringBuffer();
    if (transactionIndex != null) {
      buffer.writeln('--- Transaction $transactionIndex ---');
    }

    buffer.writeln('📅 Date: $date');
    buffer.writeln('📱 App: $app');
    buffer.writeln('👤 Name: $name');
    buffer.writeln('🆔 ID: $id');
    buffer.writeln('📝 Msg: $displayMsg');
    buffer.writeln('💰 Amount: $amountStr');
    buffer.writeln('💸 Charges: $chargesStr');
    buffer.writeln('📊 Direction: $cleanDirection');
    buffer.writeln('⇄ Type: $type');
    buffer.writeln('🏢 Account: $account');
    buffer.writeln('🏷️ Category: $category');
    buffer.write('🔗 Ref: $ref');

    return buffer.toString().trim();
  }

  /// Get direction as plain text ("OUT" or "IN") without emojis/balls
  String get cleanDirection {
    final s = direction.replaceAll(RegExp(r'[🔴🟢]'), '').trim();
    if (s.toUpperCase().contains('IN')) return 'IN';
    return 'OUT';
  }

  /// Exact 13 headers matching Google Sheets ledger:
  /// Date | app | Name | direction | Amount | Transaction ID | Status | Message | Mode | Account | Category | Reference | Charges
  static const List<String> sheetHeaders = [
    'Date',
    'app',
    'Name',
    'direction',
    'Amount',
    'Transaction ID',
    'Status',
    'Message',
    'Mode',
    'Account',
    'Category',
    'Reference',
    'Charges',
  ];

  /// Convert transaction to row values matching sheetHeaders
  List<dynamic> toSheetRow() {
    final amountVal = amount % 1 == 0 ? amount.toInt() : amount;
    final chargesVal = charges % 1 == 0 ? charges.toInt() : charges;
    final msgVal = msg.trim().isEmpty ? 'null' : msg.trim();
    return [
      date,
      app,
      name,
      cleanDirection,
      amountVal,
      id,
      'Success',
      msgVal,
      type,
      account,
      category,
      ref,
      chargesVal,
    ];
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'app': app,
      'name': name,
      'id': id,
      'msg': msg,
      'amount': amount,
      'charges': charges,
      'direction': direction,
      'type': type,
      'account': account,
      'category': category,
      'ref': ref,
      'rawText': rawText,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory UpiTransaction.fromMap(Map<String, dynamic> map) {
    final d = map['date'] ?? '';
    final i = map['id'] ?? '';
    return UpiTransaction(
      date: d,
      app: map['app'] ?? '',
      name: map['name'] ?? '',
      id: i,
      msg: map['msg'] ?? '',
      amount: (map['amount'] is num) ? (map['amount'] as num).toDouble() : 0.0,
      charges: (map['charges'] is num) ? (map['charges'] as num).toDouble() : 0.0,
      direction: (map['direction'] ?? 'OUT').toString().replaceAll(RegExp(r'[🔴🟢]'), '').trim(),
      type: map['type'] ?? 'UPI',
      account: map['account'] ?? '',
      category: map['category'] ?? 'Transfer to Others',
      ref: map['ref'] ?? generateRef(d, i),
      rawText: map['rawText'],
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory UpiTransaction.fromJson(String source) =>
      UpiTransaction.fromMap(json.decode(source));
}
