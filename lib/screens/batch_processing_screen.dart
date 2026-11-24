import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/batch_record.dart';
import '../models/upi_transaction.dart';
import '../services/ai_pipeline_service.dart';
import '../services/category_mapping_service.dart';
import '../services/google_sheets_service.dart';
import '../services/history_service.dart';
import '../services/mapping_service.dart';
import '../widgets/google_sheets_sheet.dart';
import '../widgets/user_profile_avatar.dart';

class BatchProcessingScreen extends StatefulWidget {
  final List<String>? initialImagePaths;

  const BatchProcessingScreen({super.key, this.initialImagePaths});

  @override
  State<BatchProcessingScreen> createState() => _BatchProcessingScreenState();
}

class _BatchProcessingScreenState extends State<BatchProcessingScreen> {
  final ImagePicker _picker = ImagePicker();
  List<String> _selectedPaths = [];
  final List<UpiTransaction> _processedResults = [];
  final Set<int> _reextractingIndices = {};
  bool _isProcessing = false;
  int _currentIndex = 0;
  String _currentStatus = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePaths != null && widget.initialImagePaths!.isNotEmpty) {
      _selectedPaths = List.from(widget.initialImagePaths!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startProcessing();
      });
    }
  }

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedPaths = images.map((e) => e.path).toList();
        _processedResults.clear();
      });
      _startProcessing();
    }
  }

  Future<void> _startProcessing() async {
    if (_selectedPaths.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _currentIndex = 0;
      _processedResults.clear();
      _currentStatus = 'Loading mappings...';
    });

    final mappings = await MappingService.loadMappings();
    final categoryMappings = await CategoryMappingService.loadMappings();

    for (int i = 0; i < _selectedPaths.length; i++) {
      final path = _selectedPaths[i];
      setState(() {
        _currentIndex = i + 1;
        _currentStatus = 'Processing ${i + 1} of ${_selectedPaths.length}...';
      });

      try {
        final tx = await AiPipelineService.extractWithPipeline(
          path,
          mappings,
          categoryMappings: categoryMappings,
          onStepChange: (step) {
            setState(() {
              _currentStatus = 'Item ${i + 1}/${_selectedPaths.length}: $step';
            });
          },
        );

        _processedResults.add(tx);
      } catch (e) {
        // Continue processing remaining items
      }
    }

    setState(() {
      _isProcessing = false;
      _currentStatus = 'Completed ${_processedResults.length} screenshots';
    });

    if (_processedResults.isNotEmpty) {
      final batch = BatchRecord(
        id: 'BATCH-${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        items: List.from(_processedResults),
      );
      await HistoryService.saveBatch(batch);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.bookmark_added, color: Colors.white),
                const SizedBox(width: 8),
                Text('Saved batch of ${_processedResults.length} transactions to History!'),
              ],
            ),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Auto-sync batch to Google Sheets if enabled
      if (GoogleSheetsService.instance.autoSync &&
          GoogleSheetsService.instance.isConnected) {
        _syncBatchToSheets(_processedResults, isAuto: true);
      }
    }
  }

  Future<void> _syncBatchToSheets(List<UpiTransaction> txs, {bool isAuto = false}) async {
    final sheetsService = GoogleSheetsService.instance;
    await sheetsService.init();

    if (!sheetsService.isConnected) {
      if (!isAuto && mounted) {
        GoogleSheetsSheet.show(context, pendingTransactions: txs);
      }
      return;
    }

    if (!isAuto && mounted) {
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
              Text('Syncing ${txs.length} transactions to Google Sheets...'),
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
        setState(() {});
        for (final item in txs) {
          await HistoryService.saveTransaction(item);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAuto ? 'Auto-synced ${txs.length} items to "account ledger" > "Details"!' : res.message),
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
    } else if (!isAuto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _reextractItem(int index) async {
    if (index >= _selectedPaths.length) return;
    final path = _selectedPaths[index];

    setState(() {
      _reextractingIndices.add(index);
    });

    final mappings = await MappingService.loadMappings();
    final categoryMappings = await CategoryMappingService.loadMappings();

    try {
      final updatedTx = await AiPipelineService.extractWithPipeline(
        path,
        mappings,
        categoryMappings: categoryMappings,
      );

      setState(() {
        _processedResults[index] = updatedTx;
        _reextractingIndices.remove(index);
      });

      await HistoryService.saveTransaction(updatedTx);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Re-extracted Transaction #${index + 1} successfully!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _reextractingIndices.remove(index);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Re-extraction failed: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _copyAllFormatted() {
    if (_processedResults.isEmpty) return;
    final buffer = StringBuffer();
    for (int i = 0; i < _processedResults.length; i++) {
      buffer.writeln(_processedResults[i].toFormattedString(transactionIndex: i + 1));
      if (i < _processedResults.length - 1) {
        buffer.writeln(); // double newline
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied all ${_processedResults.length} transactions in batch format!'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double totalAmount = _processedResults.fold(0, (sum, item) => sum + item.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Screenshot Processing'),
        actions: [
          const UserProfileAvatar(),
          if (_processedResults.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copy All Formatted',
              onPressed: _copyAllFormatted,
            ),
        ],
      ),
      body: Column(
        children: [
          // Action Bar Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isProcessing ? null : _pickImages,
                        icon: const Icon(Icons.collections),
                        label: const Text('Select Multiple Screenshots'),
                      ),
                    ),
                  ],
                ),
                if (_isProcessing) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: _selectedPaths.isNotEmpty ? _currentIndex / _selectedPaths.length : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentStatus,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ],
                if (_processedResults.isNotEmpty && !_isProcessing) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatChip(
                        Icons.receipt,
                        '${_processedResults.length} Items',
                        Colors.blue,
                      ),
                      _buildStatChip(
                        Icons.currency_rupee,
                        'Total: ₹${totalAmount.toStringAsFixed(0)}',
                        Colors.green,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Results List
          Expanded(
            child: _processedResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'Select multiple UPI screenshots\nto extract all in one click',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: _processedResults.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final item = _processedResults[i];
                      return Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ExpansionTile(
                          shape: const Border(),
                          collapsedShape: const Border(),
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade50,
                            child: Text(
                              '#${i + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item.name.isNotEmpty ? item.name : 'Unknown Payee',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '₹${item.amount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${item.date} • ${item.account} (${item.type})',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: SelectableText(
                                      item.toFormattedString(transactionIndex: i + 1),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        icon: _reextractingIndices.contains(i)
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.refresh, size: 16),
                                        label: Text(
                                          _reextractingIndices.contains(i)
                                              ? 'Refetching...'
                                              : 'Re-extract',
                                        ),
                                        onPressed: _reextractingIndices.contains(i) || _isProcessing
                                            ? null
                                            : () => _reextractItem(i),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        icon: const Icon(Icons.table_chart, size: 16),
                                        label: const Text('Sync'),
                                        onPressed: () => _syncBatchToSheets([item]),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        icon: const Icon(Icons.copy, size: 16),
                                        label: const Text('Copy Item'),
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(
                                              text: item.toFormattedString(transactionIndex: i + 1),
                                            ),
                                          );
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Copied Transaction #${i + 1} details!'),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _processedResults.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, -3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _copyAllFormatted,
                      icon: const Icon(Icons.copy_all),
                      label: Text('Copy All (${_processedResults.length})'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () => _syncBatchToSheets(_processedResults),
                      icon: const Icon(Icons.table_chart, size: 18),
                      label: const Text('Sync Sheets'),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildStatChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
