import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/batch_record.dart';
import '../models/upi_transaction.dart';
import '../services/google_sheets_service.dart';
import '../services/history_service.dart';
import '../widgets/google_sheets_sheet.dart';
import '../widgets/user_profile_avatar.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<BatchRecord> _batches = [];
  List<UpiTransaction> _singleHistory = [];
  bool _isLoading = true;
  String _activeTab = 'batches'; // 'batches' or 'single'
  DateTime? _filterDate;
  bool _isFetchingSheets = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final batches = await HistoryService.loadBatches();
    final singles = await HistoryService.loadHistory();
    setState(() {
      _batches = batches;
      _singleHistory = singles;
      _isLoading = false;
      // Default to singles if no batches exist
      if (_batches.isEmpty && _singleHistory.isNotEmpty) {
        _activeTab = 'single';
      }
    });
  }

  String _normalizeDate(String input) {
    final clean = input.replaceAll('/', '-').replaceAll('.', '-').trim();
    final parts = clean.split('-');
    if (parts.length == 3) {
      if (parts[0].length == 4) {
        return '${parts[2].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}-${parts[0]}';
      } else if (parts[2].length == 4) {
        return '${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}-${parts[2]}';
      }
    }
    return clean;
  }

  List<BatchRecord> get _filteredBatches {
    if (_filterDate == null) return _batches;
    final targetStr = DateFormat('dd-MM-yyyy').format(_filterDate!);
    return _batches.where((b) {
      return b.items.any((item) => _normalizeDate(item.date) == targetStr);
    }).toList();
  }

  List<UpiTransaction> get _filteredSingles {
    if (_filterDate == null) return _singleHistory;
    final targetStr = DateFormat('dd-MM-yyyy').format(_filterDate!);
    return _singleHistory.where((item) => _normalizeDate(item.date) == targetStr).toList();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _filterDate = picked;
      });
    }
  }

  Future<void> _fetchFromSheetsForDate() async {
    final targetDate = _filterDate ?? DateTime.now();
    final dateStr = DateFormat('dd-MM-yyyy').format(targetDate);

    final sheetsService = GoogleSheetsService.instance;
    await sheetsService.init();

    if (!sheetsService.isConnected) {
      if (mounted) {
        GoogleSheetsSheet.show(context);
      }
      return;
    }

    setState(() => _isFetchingSheets = true);

    try {
      final results = await sheetsService.fetchTransactionsByDate(dateStr);
      if (mounted) {
        setState(() => _isFetchingSheets = false);
        if (results.isNotEmpty) {
          final batch = BatchRecord(
            id: 'SHEET-${DateFormat('yyyyMMdd').format(targetDate)}-${DateTime.now().millisecondsSinceEpoch}',
            timestamp: targetDate,
            items: List.from(results),
          );
          await HistoryService.saveBatch(batch);
          setState(() {
            _filterDate = targetDate;
          });
          await _loadAll();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fetched ${results.length} transactions for $dateStr from "account ledger"!'),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No transactions found in "account ledger" for $dateStr'),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFetchingSheets = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching from Google Sheets: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _copyBatch(BatchRecord batch) {
    Clipboard.setData(ClipboardData(text: batch.toFormattedBatchText()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied all ${batch.count} transactions in batch format!'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copySingle(UpiTransaction tx) {
    Clipboard.setData(ClipboardData(text: tx.toFormattedString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied transaction details!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteBatch(int index) async {
    await HistoryService.deleteBatch(index);
    await _loadAll();
  }

  Future<void> _deleteSingle(int index) async {
    await HistoryService.deleteTransaction(index);
    await _loadAll();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History?'),
        content: Text(
          _activeTab == 'batches'
              ? 'This will delete all saved batch runs.'
              : 'This will delete all individual transaction history.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (_activeTab == 'batches') {
        await HistoryService.clearBatches();
      } else {
        await HistoryService.clearHistory();
      }
      await _loadAll();
    }
  }

  Future<void> _syncToSheets(List<UpiTransaction> txs) async {
    final sheetsService = GoogleSheetsService.instance;
    await sheetsService.init();

    if (!sheetsService.isConnected) {
      if (mounted) {
        GoogleSheetsSheet.show(context, pendingTransactions: txs);
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text('Syncing ${txs.length} transaction(s) to Google Sheets...'),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final res = await sheetsService.syncTransactions(txs);
    if (!mounted) return;

    if (res.success) {
      if (res.fetchedExistingCount > 0) {
        await _loadAll();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
          action: res.spreadsheetUrl != null
              ? SnackBarAction(
                  label: 'VIEW',
                  textColor: Colors.white,
                  onPressed: () async {
                    final uri = Uri.parse(res.spreadsheetUrl!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                )
              : null,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extraction History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear History',
            onPressed: _clearAll,
          ),
          const UserProfileAvatar(),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Segmented Tab Selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment<String>(
                        value: 'batches',
                        label: Text('Batches (${_batches.length})'),
                        icon: const Icon(Icons.collections_bookmark_outlined),
                      ),
                      ButtonSegment<String>(
                        value: 'single',
                        label: Text('All (${_singleHistory.length})'),
                        icon: const Icon(Icons.receipt_long_outlined),
                      ),
                    ],
                    selected: {_activeTab},
                    onSelectionChanged: (set) {
                      setState(() => _activeTab = set.first);
                    },
                  ),
                ),

                // Date Picker & Google Sheets Fetch Bar
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _pickDate,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: _filterDate != null ? Colors.green : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _filterDate != null
                                    ? DateFormat('dd-MM-yyyy').format(_filterDate!)
                                    : 'Select Date',
                                style: TextStyle(
                                  fontWeight: _filterDate != null ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 13,
                                  color: _filterDate != null ? Colors.green.shade800 : null,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 18),
                            ],
                          ),
                        ),
                      ),
                      if (_filterDate != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Clear Date Filter',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _filterDate = null),
                        ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: _isFetchingSheets ? null : _fetchFromSheetsForDate,
                        icon: _isFetchingSheets
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_download_outlined, size: 16),
                        label: Text(_isFetchingSheets ? 'Fetching...' : 'Fetch Sheet'),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: _activeTab == 'batches' ? _buildBatchesView() : _buildSingleView(),
                ),
              ],
            ),
    );
  }

  Widget _buildBatchesView() {
    final batches = _filteredBatches;
    if (batches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.collections_bookmark_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _filterDate != null
                  ? 'No batches found for ${DateFormat('dd-MM-yyyy').format(_filterDate!)}'
                  : 'No batch extractions saved yet',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              _filterDate != null
                  ? 'Tap "Fetch Sheet" to pull records from Google Sheets for this date'
                  : 'When you process multiple screenshots in Batch Mode,\nthey will automatically appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
      itemCount: batches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final batch = batches[i];
        final amountStr = batch.totalAmount % 1 == 0
            ? batch.totalAmount.toInt().toString()
            : batch.totalAmount.toStringAsFixed(2);
        final chargesStr = batch.totalCharges % 1 == 0
            ? batch.totalCharges.toInt().toString()
            : batch.totalCharges.toStringAsFixed(2);

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: CircleAvatar(
              backgroundColor: Colors.green.shade50,
              child: const Icon(Icons.inventory_2_outlined, color: Colors.green),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Batch #${_batches.length - i} • ${batch.count} Items',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '₹$amountStr',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${batch.formattedDate}${batch.totalCharges > 0 ? " • Charges: ₹$chargesStr" : ""}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(),
                    // Action Buttons for Batch
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            ),
                            icon: const Icon(Icons.copy_all, size: 16),
                            label: const Text('Copy All', overflow: TextOverflow.ellipsis),
                            onPressed: () => _copyBatch(batch),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.table_chart, size: 18, color: Colors.green),
                          tooltip: 'Sync Batch to Google Sheets',
                          onPressed: () => _syncToSheets(batch.items),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          tooltip: 'Delete Batch',
                          onPressed: () => _deleteBatch(i),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Itemized list preview
                    Container(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: batch.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (itemCtx, itemIdx) {
                          final item = batch.items[itemIdx];
                          final itemAmt = item.amount % 1 == 0
                              ? item.amount.toInt().toString()
                              : item.amount.toStringAsFixed(2);

                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${itemIdx + 1}. ${item.name}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item.date} • ${item.account} • ${item.category}\nRef: ${item.ref}',
                              style: const TextStyle(fontSize: 11),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹$itemAmt',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.red,
                                  ),
                                ),
                                if (item.charges > 0)
                                  Text(
                                    '+₹${item.charges % 1 == 0 ? item.charges.toInt() : item.charges} fee',
                                    style: const TextStyle(fontSize: 10, color: Colors.orange),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSingleView() {
    final singles = _filteredSingles;
    if (singles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _filterDate != null
                  ? 'No transactions found for ${DateFormat('dd-MM-yyyy').format(_filterDate!)}'
                  : 'No single extractions in history',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            if (_filterDate != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Tap "Fetch Sheet" to pull records from Google Sheets for this date',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
      itemCount: singles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final item = singles[i];
        final isOut = item.direction.contains('OUT');
        final itemAmt = item.amount % 1 == 0
            ? item.amount.toInt().toString()
            : item.amount.toStringAsFixed(2);

        return Card(
          elevation: 0.8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: isOut ? Colors.red.shade100 : Colors.green.shade100,
                            child: Icon(
                              isOut ? Icons.arrow_outward : Icons.arrow_downward,
                              size: 16,
                              color: isOut ? Colors.red.shade800 : Colors.green.shade800,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name.isNotEmpty ? item.name : 'Unknown Payee',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  '${item.date} • ${item.app}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '₹$itemAmt',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: isOut ? Colors.red.shade700 : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.account_balance, size: 14),
                            label: Text(
                              item.account,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.category, size: 14),
                            label: Text(
                              item.category,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.table_chart, size: 18, color: Colors.green),
                          tooltip: 'Sync to Sheets',
                          onPressed: () => _syncToSheets([item]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Copy details',
                          onPressed: () => _copySingle(item),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                          tooltip: 'Delete',
                          onPressed: () => _deleteSingle(i),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
