import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/upi_transaction.dart';
import '../services/google_sheets_service.dart';

class GoogleSheetsSheet extends StatefulWidget {
  final List<UpiTransaction>? pendingTransactionsToSync;

  const GoogleSheetsSheet({
    super.key,
    this.pendingTransactionsToSync,
  });

  static Future<void> show(
    BuildContext context, {
    List<UpiTransaction>? pendingTransactions,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GoogleSheetsSheet(pendingTransactionsToSync: pendingTransactions),
    );
  }

  @override
  State<GoogleSheetsSheet> createState() => _GoogleSheetsSheetState();
}

class _GoogleSheetsSheetState extends State<GoogleSheetsSheet> {
  final GoogleSheetsService _sheetsService = GoogleSheetsService.instance;
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _syncStatusMessage;
  String? _authErrorMessage;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    await _sheetsService.init();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _isLoading = true;
      _syncStatusMessage = null;
      _authErrorMessage = null;
    });

    final result = await _sheetsService.signIn();

    if (mounted) {
      setState(() => _isLoading = false);
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected as ${_sheetsService.userEmail}'),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (widget.pendingTransactionsToSync != null &&
            widget.pendingTransactionsToSync!.isNotEmpty) {
          _syncTransactions(widget.pendingTransactionsToSync!);
        }
      } else {
        setState(() {
          _authErrorMessage = result.errorMessage ?? 'Sign-in canceled';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_authErrorMessage!),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    setState(() => _isLoading = true);
    await _sheetsService.signOut();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _authErrorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected Google account'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _syncTransactions(List<UpiTransaction> txs) async {
    if (txs.isEmpty) return;

    setState(() {
      _isSyncing = true;
      _syncStatusMessage = 'Syncing ${txs.length} item(s) to "account ledger" > "Details"...';
    });

    final result = await _sheetsService.syncTransactions(txs);

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = result.success ? result.message : 'Sync Failed: ${result.message}';
      });

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            action: result.spreadsheetUrl != null
                ? SnackBarAction(
                    label: 'OPEN',
                    textColor: Colors.white,
                    onPressed: () => _openSpreadsheet(result.spreadsheetUrl!),
                  )
                : null,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openSpreadsheet(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Could not launch $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _sheetsService.isConnected;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.table_chart, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Google Sheets Sync',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Spreadsheet: "account ledger" > "Details"',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Pending Transactions Sync Banner
            if (widget.pendingTransactionsToSync != null &&
                widget.pendingTransactionsToSync!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pending_actions, color: Colors.blue, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.pendingTransactionsToSync!.length} transaction(s) ready to sync to Google Sheets.',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (isConnected)
                      FilledButton.tonal(
                        onPressed: _isSyncing
                            ? null
                            : () => _syncTransactions(widget.pendingTransactionsToSync!),
                        child: const Text('Sync Now'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // User Account Connection Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isConnected ? Colors.green.shade400 : theme.colorScheme.outlineVariant,
                  width: isConnected ? 1.5 : 1.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (isConnected) ...[
                      // User Profile: Picture + Name + Email
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (_sheetsService.userPhotoUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: Image.network(
                                _sheetsService.userPhotoUrl,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) => _buildAvatarFallback(),
                              ),
                            )
                          else
                            _buildAvatarFallback(),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_sheetsService.userName.isNotEmpty)
                                  Text(
                                    _sheetsService.userName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                Text(
                                  _sheetsService.userEmail,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.verified_user, color: Colors.green, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Connected & Authorized',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, color: Colors.red),
                            tooltip: 'Disconnect Account',
                            onPressed: _isLoading ? null : _handleSignOut,
                          ),
                        ],
                      ),
                    ] else ...[
                      // Disconnected State
                      Row(
                        children: [
                          const Icon(Icons.account_circle_outlined, size: 40, color: Colors.grey),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Google Account',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                Text(
                                  'Sign in to sync with "account ledger" on Google Drive',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isLoading ? null : _handleSignIn,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(_isLoading ? 'Connecting...' : 'Connect Google Account'),
                        ),
                      ),
                      if (_authErrorMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'Error: $_authErrorMessage',
                            style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Settings & Auto Sync
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-sync extractions', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Automatically append to "Details" sheet whenever an image or batch is extracted',
                style: TextStyle(fontSize: 12),
              ),
              value: _sheetsService.autoSync,
              onChanged: (val) async {
                await _sheetsService.setAutoSync(val);
                setState(() {});
              },
            ),

            if (_sheetsService.spreadsheetUrl != null) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _openSpreadsheet(_sheetsService.spreadsheetUrl!),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open "account ledger" in Google Sheets'),
              ),
            ],

            if (_isSyncing) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(color: Colors.green.shade700),
            ],

            if (_syncStatusMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _syncStatusMessage!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _syncStatusMessage!.startsWith('Sync Failed')
                      ? Colors.red
                      : Colors.green.shade800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return CircleAvatar(
      radius: 26,
      backgroundColor: Colors.green.shade100,
      child: Text(
        _sheetsService.userName.isNotEmpty
            ? _sheetsService.userName[0].toUpperCase()
            : 'G',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green.shade800),
      ),
    );
  }
}
