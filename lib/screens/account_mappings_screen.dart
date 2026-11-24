import 'package:flutter/material.dart';
import '../models/account_mapping.dart';
import '../models/category_mapping.dart';
import '../services/category_mapping_service.dart';
import '../services/mapping_service.dart';
import '../widgets/user_profile_avatar.dart';

class AccountMappingsScreen extends StatefulWidget {
  const AccountMappingsScreen({super.key});

  @override
  State<AccountMappingsScreen> createState() => _AccountMappingsScreenState();
}

class _AccountMappingsScreenState extends State<AccountMappingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Account mappings state
  List<AccountMapping> _accountMappings = [];
  bool _isLoadingAccounts = true;
  String _accountSearchQuery = '';
  String _typeFilter = 'ALL'; // ALL, UPI, Credit

  // Category mappings state
  List<CategoryMapping> _categoryMappings = [];
  bool _isLoadingCategories = true;
  String _categorySearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadAccountData(),
      _loadCategoryData(),
    ]);
  }

  Future<void> _loadAccountData() async {
    setState(() => _isLoadingAccounts = true);
    final list = await MappingService.loadMappings();
    if (mounted) {
      setState(() {
        _accountMappings = list;
        _isLoadingAccounts = false;
      });
    }
  }

  Future<void> _loadCategoryData() async {
    setState(() => _isLoadingCategories = true);
    final list = await CategoryMappingService.loadMappings();
    if (mounted) {
      setState(() {
        _categoryMappings = list;
        _isLoadingCategories = false;
      });
    }
  }

  // ================= ACCOUNT MAPPINGS LOGIC =================

  List<AccountMapping> get _filteredAccountMappings {
    return _accountMappings.where((m) {
      final matchesSearch = m.accountDigits.contains(_accountSearchQuery.trim()) ||
          m.accountName.toLowerCase().contains(_accountSearchQuery.toLowerCase().trim());
      final matchesType = _typeFilter == 'ALL' || m.type.toUpperCase() == _typeFilter;
      return matchesSearch && matchesType;
    }).toList();
  }

  void _showAddOrEditAccountDialog([AccountMapping? existing]) {
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
                  Text(existing == null ? 'Add Account Mapping' : 'Edit Account Mapping'),
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
                        ButtonSegment(
                          value: 'UPI',
                          label: Text('UPI / Bank'),
                          icon: Icon(Icons.account_balance_wallet),
                        ),
                        ButtonSegment(
                          value: 'Credit',
                          label: Text('Credit Card'),
                          icon: Icon(Icons.credit_card),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setDialogState(() {
                          selectedType = newSelection.first;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final digits = digitsCtrl.text.trim();
                    final name = nameCtrl.text.trim();

                    if (digits.isEmpty || name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter both digits and account name')),
                      );
                      return;
                    }

                    Navigator.pop(ctx);
                    await MappingService.addOrUpdateMapping(
                      AccountMapping(
                        accountDigits: digits,
                        accountName: name,
                        type: selectedType,
                      ),
                    );
                    _loadAccountData();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            existing == null
                                ? 'Added mapping for "$digits" -> $name'
                                : 'Updated mapping for "$digits" -> $name',
                          ),
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

  void _deleteAccountMapping(AccountMapping mapping) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Mapping?'),
        content: Text(
          'Remove rule for digits "${mapping.accountDigits}" (${mapping.accountName})?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
      _loadAccountData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted mapping for ${mapping.accountDigits}')),
        );
      }
    }
  }

  // ================= CATEGORY MAPPINGS LOGIC =================

  List<CategoryMapping> get _filteredCategoryMappings {
    final query = _categorySearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _categoryMappings;

    return _categoryMappings.where((cat) {
      final matchesCategory = cat.category.toLowerCase().contains(query);
      final matchesKeywords = cat.keywords.any((k) => k.toLowerCase().contains(query));
      return matchesCategory || matchesKeywords;
    }).toList();
  }

  void _showAddOrEditCategoryDialog([CategoryMapping? existing]) {
    final categoryCtrl = TextEditingController(text: existing?.category ?? '');
    final keywordInputCtrl = TextEditingController();
    final List<String> currentKeywords = List.from(existing?.keywords ?? []);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            void addKeyword(String raw) {
              final parts = raw.split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty);
              for (final p in parts) {
                if (!currentKeywords.contains(p)) {
                  currentKeywords.add(p);
                }
              }
              keywordInputCtrl.clear();
              setDialogState(() {});
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(
                    existing == null ? Icons.category : Icons.edit_note,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      existing == null ? 'Add Category Mapping' : 'Edit Category Mapping',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Map keywords found in payment messages or merchant names to an expense category.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: categoryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Category Name',
                          hintText: 'e.g. Groceries, Fuel, Entertainment',
                          prefixIcon: Icon(Icons.label_outline),
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: keywordInputCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Add Keyword(s)',
                                hintText: 'e.g. tomato, petrol (comma-separated)',
                                prefixIcon: Icon(Icons.tag),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: (val) {
                                if (val.trim().isNotEmpty) {
                                  addKeyword(val);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: () {
                              if (keywordInputCtrl.text.trim().isNotEmpty) {
                                addKeyword(keywordInputCtrl.text);
                              }
                            },
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Keywords (${currentKeywords.length}):',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          if (currentKeywords.isNotEmpty)
                            TextButton(
                              onPressed: () => setDialogState(() => currentKeywords.clear()),
                              child: const Text('Clear All', style: TextStyle(fontSize: 12, color: Colors.red)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (currentKeywords.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text(
                              'No keywords added yet.\nType keywords above and tap Add.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                          ),
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: currentKeywords.map((k) {
                                return Chip(
                                  label: Text(k, style: const TextStyle(fontSize: 12)),
                                  deleteIcon: const Icon(Icons.close, size: 14),
                                  onDeleted: () {
                                    setDialogState(() {
                                      currentKeywords.remove(k);
                                    });
                                  },
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final catName = categoryCtrl.text.trim();
                    if (catName.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a category name')),
                      );
                      return;
                    }

                    if (keywordInputCtrl.text.trim().isNotEmpty) {
                      addKeyword(keywordInputCtrl.text);
                    }

                    if (currentKeywords.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please add at least one keyword for this category')),
                      );
                      return;
                    }

                    Navigator.pop(ctx);
                    await CategoryMappingService.addOrUpdateMapping(
                      CategoryMapping(
                        category: catName,
                        keywords: currentKeywords,
                      ),
                    );
                    _loadCategoryData();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            existing == null
                                ? 'Added category "$catName" with ${currentKeywords.length} keywords'
                                : 'Updated category "$catName" (${currentKeywords.length} keywords)',
                          ),
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

  void _deleteCategoryMapping(CategoryMapping mapping) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category Mapping?'),
        content: Text(
          'Remove category "${mapping.category}" and its ${mapping.keywords.length} mapped keywords?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CategoryMappingService.deleteMapping(mapping.category);
      _loadCategoryData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted category mapping for ${mapping.category}')),
        );
      }
    }
  }

  Future<void> _resetDefaults() async {
    final isCategoryTab = _tabController.index == 1;
    final title = isCategoryTab ? 'Reset Categories to Defaults?' : 'Reset Accounts to Defaults?';
    final content = isCategoryTab
        ? 'This will restore all standard category rules (Vegetables, Fruits, Dairy, Utilities, Food, Fuel, etc.) and discard custom categories.'
        : 'This will restore all default account number mappings (SBI, HDFC, ICICI, Axis, Kotak, etc.) and discard custom entries.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (isCategoryTab) {
        await CategoryMappingService.resetToDefaults();
        await _loadCategoryData();
      } else {
        await MappingService.resetToDefaults();
        await _loadAccountData();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCategoryTab
                  ? 'Reset categories to default rules successfully'
                  : 'Reset accounts to default mappings successfully',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final upiCount = _accountMappings.where((m) => m.type.toUpperCase() == 'UPI').length;
    final creditCount = _accountMappings.where((m) => m.type.toUpperCase() == 'CREDIT').length;
    final isCategoriesTab = _tabController.index == 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mappings'),
        actions: [
          const UserProfileAvatar(),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'reset') _resetDefaults();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    const Icon(Icons.restore, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(isCategoriesTab ? 'Reset Categories' : 'Reset Accounts'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.credit_card),
              text: 'Accounts (${_accountMappings.length})',
            ),
            Tab(
              icon: const Icon(Icons.category),
              text: 'Categories (${_categoryMappings.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ================= TAB 1: ACCOUNTS =================
          _isLoadingAccounts
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Top Search & Filter Bar
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Search digits or account name...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _accountSearchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () => setState(() => _accountSearchQuery = ''),
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
                            onChanged: (val) => setState(() => _accountSearchQuery = val),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              ChoiceChip(
                                label: Text('All (${_accountMappings.length})'),
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

                    // Accounts List
                    Expanded(
                      child: _filteredAccountMappings.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text(
                                    _accountSearchQuery.isEmpty
                                        ? 'No account mappings configured'
                                        : 'No account mappings matching "$_accountSearchQuery"',
                                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.tonalIcon(
                                    onPressed: () => _showAddOrEditAccountDialog(),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Account Mapping'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                              itemCount: _filteredAccountMappings.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final item = _filteredAccountMappings[i];
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
                                          onPressed: () => _showAddOrEditAccountDialog(item),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                            color: Colors.red.shade400,
                                          ),
                                          tooltip: 'Delete Mapping',
                                          onPressed: () => _deleteAccountMapping(item),
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

          // ================= TAB 2: CATEGORIES =================
          _isLoadingCategories
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Search Bar for Categories
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search category or keyword...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _categorySearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(() => _categorySearchQuery = ''),
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
                        onChanged: (val) => setState(() => _categorySearchQuery = val),
                      ),
                    ),

                    // Categories List
                    Expanded(
                      child: _filteredCategoryMappings.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text(
                                    _categorySearchQuery.isEmpty
                                        ? 'No category mappings configured'
                                        : 'No categories matching "$_categorySearchQuery"',
                                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.tonalIcon(
                                    onPressed: () => _showAddOrEditCategoryDialog(),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Category Mapping'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                              itemCount: _filteredCategoryMappings.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final cat = _filteredCategoryMappings[i];

                                return Card(
                                  elevation: 0.8,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Category Name Header + Actions
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.primaryContainer,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.label,
                                                size: 18,
                                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    cat.category,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${cat.keywords.length} keyword(s)',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, size: 20),
                                              tooltip: 'Edit Category',
                                              onPressed: () => _showAddOrEditCategoryDialog(cat),
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.delete_outline,
                                                size: 20,
                                                color: Colors.red.shade400,
                                              ),
                                              tooltip: 'Delete Category',
                                              onPressed: () => _deleteCategoryMapping(cat),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        // Keywords Chips
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: cat.keywords.map((keyword) {
                                            return Chip(
                                              label: Text(
                                                keyword,
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                              side: BorderSide.none,
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              visualDensity: VisualDensity.compact,
                                            );
                                          }).toList(),
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _showAddOrEditAccountDialog();
          } else {
            _showAddOrEditCategoryDialog();
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0 ? 'Add Account' : 'Add Category'),
      ),
    );
  }
}
