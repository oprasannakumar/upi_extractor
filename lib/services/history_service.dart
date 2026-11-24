import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/batch_record.dart';
import '../models/upi_transaction.dart';

class HistoryService {
  static const String _singleHistoryKey = 'saved_upi_history_v1';
  static const String _batchHistoryKey = 'saved_upi_batch_history_v1';

  // --- Single Transactions ---

  static Future<List<UpiTransaction>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_singleHistoryKey);
    if (raw == null) return [];

    try {
      final List<dynamic> list = json.decode(raw);
      return list.map((e) => UpiTransaction.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTransaction(UpiTransaction tx) async {
    final history = await loadHistory();
    history.insert(0, tx);
    // Keep last 150 entries
    if (history.length > 150) {
      history.removeRange(150, history.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_singleHistoryKey, json.encode(history.map((e) => e.toMap()).toList()));
  }

  static Future<void> deleteTransaction(int index) async {
    final history = await loadHistory();
    if (index >= 0 && index < history.length) {
      history.removeAt(index);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_singleHistoryKey, json.encode(history.map((e) => e.toMap()).toList()));
    }
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_singleHistoryKey);
  }

  // --- Batch Extractions ---

  static Future<List<BatchRecord>> loadBatches() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_batchHistoryKey);
    if (raw == null) return [];

    try {
      final List<dynamic> list = json.decode(raw);
      return list.map((e) => BatchRecord.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveBatch(BatchRecord batch) async {
    if (batch.items.isEmpty) return;
    final batches = await loadBatches();
    batches.insert(0, batch);
    // Keep last 50 batches
    if (batches.length > 50) {
      batches.removeRange(50, batches.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_batchHistoryKey, json.encode(batches.map((e) => e.toMap()).toList()));

    // Also persist all items individually to the single history
    for (final item in batch.items) {
      await saveTransaction(item);
    }
  }

  static Future<void> deleteBatch(int index) async {
    final batches = await loadBatches();
    if (index >= 0 && index < batches.length) {
      batches.removeAt(index);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_batchHistoryKey, json.encode(batches.map((e) => e.toMap()).toList()));
    }
  }

  static Future<void> clearBatches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_batchHistoryKey);
  }

  /// Load all transactions across single items and batches
  static Future<List<UpiTransaction>> getAllTransactions() async {
    final singleList = await loadHistory();
    return singleList;
  }
}
