import 'dart:convert';
import 'package:intl/intl.dart';
import 'upi_transaction.dart';

class BatchRecord {
  final String id;
  final DateTime timestamp;
  final List<UpiTransaction> items;

  BatchRecord({
    required this.id,
    required this.timestamp,
    required this.items,
  });

  double get totalAmount => items.fold(0.0, (sum, item) => sum + item.amount);
  double get totalCharges => items.fold(0.0, (sum, item) => sum + item.charges);
  int get count => items.length;

  String get formattedDate => DateFormat('dd MMM yyyy, hh:mm a').format(timestamp);

  /// Generates the exact multi-transaction batch format:
  /// --- Transaction 1 ---
  /// 📅 Date: ...
  /// ...
  /// 🔗 Ref: ...
  ///
  /// --- Transaction 2 ---
  /// ...
  String toFormattedBatchText() {
    final buffer = StringBuffer();
    for (int i = 0; i < items.length; i++) {
      buffer.writeln(items[i].toFormattedString(transactionIndex: i + 1));
      if (i < items.length - 1) {
        buffer.writeln(); // double newline
      }
    }
    return buffer.toString().trim();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'items': items.map((e) => e.toMap()).toList(),
    };
  }

  factory BatchRecord.fromMap(Map<String, dynamic> map) {
    final rawList = map['items'] as List? ?? [];
    return BatchRecord(
      id: map['id'] ?? 'BATCH-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp']) ?? DateTime.now()
          : DateTime.now(),
      items: rawList.map((e) => UpiTransaction.fromMap(e)).toList(),
    );
  }

  String toJson() => json.encode(toMap());

  factory BatchRecord.fromJson(String source) =>
      BatchRecord.fromMap(json.decode(source));
}
