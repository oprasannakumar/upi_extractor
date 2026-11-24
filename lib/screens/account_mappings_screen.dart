import 'package:flutter/material.dart';
import '../models/account_mapping.dart';
import '../services/mapping_service.dart';

class AccountMappingsScreen extends StatefulWidget {
  const AccountMappingsScreen({super.key});

  @override
  State<AccountMappingsScreen> createState() => _AccountMappingsScreenState();
}

class _AccountMappingsScreenState extends State<AccountMappingsScreen> {
  List<AccountMapping> _mappings = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _typeFilter = 'ALL'; // ALL, UPI, Credit

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final list = await MappingService.loadMappings();
    setState(() {
      _mappings = list;
      _isLoading = false;
    });
  }

  List<AccountMapping> get _filteredMappings {
    return _mappings.where((m) {
      final matchesSearch = m.accountDigits.contains(_searchQuery.trim()) ||
          m.accountName.toLowerCase().contains(_searchQuery.toLowerCase().trim());
      final matchesType = _typeFilter == 'ALL' || m.type.toUpperCase() == _typeFilter;
      return matchesSearch && matchesType;
    }).toList();
  }

  void _showAddOrEditDialog([AccountMapping? existing]) {
    final digitsCtrl = TextEditingController(text: existing?.accountDigits ?? '');
    final nameCtrl = TextEditingController(text: existing?.accountName ?? '');
    String selectedType = existing?.type ?? 'UPI';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(
                    existing == null ? Icons.add_card : Icons.edit,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(existing == null ? 'Add Mapping' : 'Edit Mapping'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configure how an account number maps to an Account Name and Type (UPI or Credit).',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: digitsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Account Digits / Suffix',
                        hintText: 'e.g. 9989 or 02',
                        prefixIcon: Icon(Icons.numbers),
                        border: OutlineInputBorder(),
                        helperText: 'Matched from masked a/c (e.g. XXXXXX9989)',
                      ),
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mapped Account Name',
                        hintText: 'e.g. SBI or ICICI Amazon',
                        prefixIcon: Icon(Icons.account_balance),
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Transaction Type:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'UPI',
                          label: Text('UPI'),
                          icon: Icon(Icons.account_balance_wallet_outlined),
                        ),
                        ButtonSegment<String>(
                          value: 'Credit',
                          label: Text('Credit'),
                          icon: Icon(Icons.credit_card_outlined),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setDialogState(() {
                          selectedType = newSelection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedType == 'UPI'
                          ? '• Maps to Bank Account (Savings / Salary via UPI)'
                          : '• Maps to RuPay Credit Card / Credit Line',
                      style: TextStyle(fontSize: 12, color: Colors.indigo.shade400),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final digits = digitsCtrl.text.trim();
                    final name = nameCtrl.text.trim();
                    if (digits.isEmpty || name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please fill all fields')),
                      );
                      return;
                    }
                    Navigator.pop(dialogCtx);
                    final newMapping = AccountMapping(
                      accountDigits: digits,
                      accountName: name,
                      type: selectedType,
                    );
                    await MappingService.addOrUpdateMapping(newMapping);
                    await _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Saved mapping: $digits -> $name ($selectedType)'),
                          backgroundColor: Colors.green.shade700,
                        ),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteMapping(AccountMapping mapping) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Mapping?'),
        content: Text(
          'Remove "${mapping.accountDigits} -> ${mapping.accountName} (${mapping.type})"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MappingService.deleteMapping(mapping.accountDigits);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted mapping for ${mapping.accountDigits}')),
        );
      }
    }
  }

  Future<void> _resetDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Defaults?'),
        content: const Text(
          'This will restore the 20 preconfigured bank and credit card mappings (SBI, ICICI Amazon, HDFC, Axis, etc.).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MappingService.resetToDefaults();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reset to default mappings successfully')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final upiCount = _mappings.where((m) => m.type.toUpperCase() == 'UPI').length;
    final creditCount = _mappings.where((m) => m.type.toUpperCase() == 'CREDIT').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Mappings'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'reset') _resetDefaults();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restore, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Reset to Defaults'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top Summary & Search Card
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      // Search Bar
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search digits or account name...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(() => _searchQuery = ''),
                                )
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                      const SizedBox(height: 10),
                      // Filter Chips
                      Row(
                        children: [
                          ChoiceChip(
                            label: Text('All (${_mappings.length})'),
                            selected: _typeFilter == 'ALL',
                            onSelected: (_) => setState(() => _typeFilter = 'ALL'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.account_balance_wallet_outlined, size: 16),
                                const SizedBox(width: 4),
                                Text('UPI ($upiCount)'),
                              ],
                            ),
                            selected: _typeFilter == 'UPI',
                            selectedColor: Colors.blue.shade100,
                            onSelected: (_) => setState(() => _typeFilter = 'UPI'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.credit_card_outlined, size: 16),
                                const SizedBox(width: 4),
                                Text('Credit ($creditCount)'),
                              ],
                            ),
                            selected: _typeFilter == 'CREDIT',
                            selectedColor: Colors.purple.shade100,
                            onSelected: (_) => setState(() => _typeFilter = 'CREDIT'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Mappings List
                Expanded(
                  child: _filteredMappings.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'No mappings configured yet'
                                    : 'No mappings matching "$_searchQuery"',
                                style: const TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.tonalIcon(
                                onPressed: () => _showAddOrEditDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Add First Mapping'),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                          itemCount: _filteredMappings.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final item = _filteredMappings[i];
                            final isCredit = item.type.toUpperCase() == 'CREDIT';

                            return Card(
                              elevation: 0.8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: isCredit
                                      ? Colors.purple.withValues(alpha: 0.2)
                                      : Colors.blue.withValues(alpha: 0.2),
                                ),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isCredit
                                        ? Colors.purple.withValues(alpha: 0.12)
                                        : Colors.blue.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    item.accountDigits,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      fontSize: 16,
                                      color: isCredit
                                          ? Colors.purple.shade800
                                          : Colors.blue.shade800,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  item.accountName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isCredit
                                            ? Colors.purple.shade50
                                            : Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isCredit
                                              ? Colors.purple.shade200
                                              : Colors.blue.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isCredit
                                                ? Icons.credit_card
                                                : Icons.account_balance_wallet,
                                            size: 13,
                                            color: isCredit
                                                ? Colors.purple.shade700
                                                : Colors.blue.shade700,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Type: ${item.type}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isCredit
                                                  ? Colors.purple.shade700
                                                  : Colors.blue.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      tooltip: 'Edit Mapping',
                                      onPressed: () => _showAddOrEditDialog(item),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                        color: Colors.red.shade400,
                                      ),
                                      tooltip: 'Delete Mapping',
                                      onPressed: () => _deleteMapping(item),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOrEditDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Mapping'),
      ),
    );
  }
}
