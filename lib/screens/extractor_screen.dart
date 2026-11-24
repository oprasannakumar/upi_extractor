import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/account_mapping.dart';
import '../models/upi_transaction.dart';
import '../services/ai_pipeline_service.dart';
import '../services/gemini_service.dart';
import '../services/google_sheets_service.dart';
import '../services/groq_service.dart';
import '../services/history_service.dart';
import '../services/mapping_service.dart';
import '../services/upi_extractor_service.dart';
import '../widgets/google_sheets_sheet.dart';
import '../widgets/user_profile_avatar.dart';
import 'batch_processing_screen.dart';

class ExtractorScreen extends StatefulWidget {
  final String? sharedImagePath;

  const ExtractorScreen({super.key, this.sharedImagePath});

  @override
  State<ExtractorScreen> createState() => _ExtractorScreenState();
}

class _ExtractorScreenState extends State<ExtractorScreen> {
  File? _imageFile;
  bool _isProcessing = false;
  UpiTransaction? _extractedTransaction;
  String? _errorMessage;
  String _engineMode = 'local'; // 'local', 'gemini', 'groq'
  String _geminiModel = GeminiService.defaultModel;
  String _groqModel = GroqService.defaultModel;
  String _currentPipelineStatus = '';
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initAndCheckShared();
  }

  Future<void> _initAndCheckShared() async {
    if (widget.sharedImagePath != null && widget.sharedImagePath!.isNotEmpty) {
      if (mounted) {
        _processFile(File(widget.sharedImagePath!));
      }
    } else {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait([
      GeminiService.getEngineMode(),
      GeminiService.getModel(),
      GroqService.getModel(),
    ]);
    if (mounted) {
      setState(() {
        _engineMode = results[0];
        _geminiModel = results[1];
        _groqModel = results[2];
      });
    }
  }

  Future<void> _processFile(File file) async {
    // Show loading state and image preview immediately without waiting for disk/settings
    setState(() {
      _imageFile = file;
      _isProcessing = true;
      _errorMessage = null;
      _extractedTransaction = null;
      _currentPipelineStatus = 'Starting extraction...';
    });

    final results = await Future.wait([
      GeminiService.getEngineMode(),
      GeminiService.getModel(),
      GroqService.getModel(),
      MappingService.loadMappings(),
    ]);

    final currentMode = results[0] as String;
    final currentGeminiModel = results[1] as String;
    final currentGroqModel = results[2] as String;
    final mappings = results[3] as List<AccountMapping>;

    if (mounted) {
      setState(() {
        _engineMode = currentMode;
        _geminiModel = currentGeminiModel;
        _groqModel = currentGroqModel;
      });
    }

    try {
      final result = await AiPipelineService.extractWithPipeline(
        file.path,
        mappings,
        onStepChange: (step) {
          if (mounted) {
            setState(() => _currentPipelineStatus = step);
          }
        },
      );

      setState(() {
        _extractedTransaction = result;
        _isProcessing = false;
      });

      await HistoryService.saveTransaction(result);

      if (GoogleSheetsService.instance.autoSync &&
          GoogleSheetsService.instance.isConnected) {
        _syncToSheets(result, isAuto: true);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Extraction Error: $e';
      });
    }
  }

  Future<void> _pickAndProcess(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile == null) return;
    _processFile(File(pickedFile.path));
  }

  Future<void> _syncToSheets(UpiTransaction tx, {bool isAuto = false}) async {
    final sheetsService = GoogleSheetsService.instance;
    await sheetsService.init();

    if (!sheetsService.isConnected) {
      if (!isAuto && mounted) {
        GoogleSheetsSheet.show(context, pendingTransactions: [tx]);
      }
      return;
    }

    if (!isAuto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 10),
              Text('Syncing to Google Sheets...'),
            ],
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final res = await sheetsService.syncTransactions([tx]);
    if (!mounted) return;

    if (res.success) {
      if (res.fetchedExistingCount > 0) {
        setState(() {});
        await HistoryService.saveTransaction(tx);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAuto ? 'Auto-synced to "account ledger" > "Details"!' : res.message),
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

  void _copyToClipboard() {
    if (_extractedTransaction == null) return;
    Clipboard.setData(ClipboardData(text: _extractedTransaction!.toFormattedString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Copied details to clipboard!'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSettingsDialog() async {
    final geminiKey = await GeminiService.getApiKey() ?? '';
    final groqKey = await GroqService.getApiKey() ?? '';
    final geminiModel = await GeminiService.getModel();
    final groqModel = await GroqService.getModel();

    final geminiKeyCtrl = TextEditingController(text: geminiKey);
    final groqKeyCtrl = TextEditingController(text: groqKey);
    final geminiModelCtrl = TextEditingController(text: geminiModel);
    final groqModelCtrl = TextEditingController(text: groqModel);

    String currentMode = _engineMode;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dCtx, setDState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.tune, color: Colors.green),
                  SizedBox(width: 8),
                  Text('AI Engine Settings'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose Extraction Engine:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'local',
                          label: Text('Local'),
                          icon: Icon(Icons.memory),
                        ),
                        ButtonSegment(
                          value: 'gemini',
                          label: Text('Gemini'),
                          icon: Icon(Icons.auto_awesome),
                        ),
                        ButtonSegment(
                          value: 'groq',
                          label: Text('Groq'),
                          icon: Icon(Icons.bolt),
                        ),
                      ],
                      selected: {currentMode},
                      onSelectionChanged: (set) {
                        setDState(() => currentMode = set.first);
                      },
                    ),
                    const SizedBox(height: 14),

                    if (currentMode == 'local')
                      const Text(
                        '• 100% offline, privacy-first, 0 ms latency\n• Uses on-device Google ML Kit OCR with layout anchoring',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),

                    if (currentMode == 'gemini') ...[
                      const Text(
                        'Google Gemini Multimodal AI',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: geminiModelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Gemini Model',
                          hintText: 'e.g. gemini-3.6-flash or gemini-2.0-flash',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: geminiKeyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Gemini API Key',
                          hintText: 'AIzaSy...',
                          border: OutlineInputBorder(),
                          helperText: 'Get free key from Google AI Studio',
                        ),
                      ),
                    ],

                    if (currentMode == 'groq') ...[
                      const Text(
                        'Groq Fast Inference (Qwen / Llama)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: groqModelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Groq Model',
                          hintText: 'qwen/qwen3.8-27b',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: groqKeyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Groq API Key',
                          hintText: 'gsk_...',
                          border: OutlineInputBorder(),
                          helperText: 'Get free key from console.groq.com',
                        ),
                      ),
                    ],
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
                    final nav = Navigator.of(ctx);
                    await GeminiService.saveEngineMode(currentMode);
                    if (currentMode == 'gemini') {
                      await GeminiService.saveApiKey(geminiKeyCtrl.text.trim());
                      await GeminiService.saveModel(geminiModelCtrl.text.trim());
                    } else if (currentMode == 'groq') {
                      await GroqService.saveApiKey(groqKeyCtrl.text.trim());
                      await GroqService.saveModel(groqModelCtrl.text.trim());
                    }

                    if (mounted) {
                      setState(() {
                        _engineMode = currentMode;
                        _geminiModel = geminiModelCtrl.text.trim();
                        _groqModel = groqModelCtrl.text.trim();
                      });
                    }
                    nav.pop();
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

  void _openEditDialog() {
    if (_extractedTransaction == null) return;
    final tx = _extractedTransaction!;

    final dateCtrl = TextEditingController(text: tx.date);
    final appCtrl = TextEditingController(text: tx.app);
    final nameCtrl = TextEditingController(text: tx.name);
    final idCtrl = TextEditingController(text: tx.id);
    final msgCtrl = TextEditingController(text: tx.msg);
    final amountCtrl = TextEditingController(
      text: tx.amount % 1 == 0 ? tx.amount.toInt().toString() : tx.amount.toString(),
    );
    final chargesCtrl = TextEditingController(
      text: tx.charges % 1 == 0 ? tx.charges.toInt().toString() : tx.charges.toString(),
    );
    final directionCtrl = TextEditingController(text: tx.direction);
    final typeCtrl = TextEditingController(text: tx.type);
    final accountCtrl = TextEditingController(text: tx.account);
    final categoryCtrl = TextEditingController(text: tx.category);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Edit Extracted Details',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                _buildEditField('📅 Date', dateCtrl),
                _buildEditField('📱 App', appCtrl),
                _buildEditField('👤 Name', nameCtrl),
                _buildEditField('🆔 ID', idCtrl),
                _buildEditField('📝 Msg', msgCtrl, onChanged: (newMsg) {
                  categoryCtrl.text = UpiExtractorService.categorizeByMessage(newMsg);
                }),
                _buildEditField('💰 Amount', amountCtrl, keyboardType: TextInputType.number),
                _buildEditField('💸 Charges', chargesCtrl, keyboardType: TextInputType.number),
                _buildEditField('📊 Direction', directionCtrl),
                _buildEditField('⇄ Type', typeCtrl),
                _buildEditField('🏢 Account', accountCtrl),
                _buildEditField('🏷️ Category', categoryCtrl),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        tx.date = dateCtrl.text.trim();
                        tx.app = appCtrl.text.trim();
                        tx.name = nameCtrl.text.trim();
                        tx.id = idCtrl.text.trim();
                        tx.msg = msgCtrl.text.trim();
                        tx.amount = double.tryParse(amountCtrl.text.trim()) ?? tx.amount;
                        tx.charges = double.tryParse(chargesCtrl.text.trim()) ?? tx.charges;
                        tx.direction = directionCtrl.text.trim();
                        tx.type = typeCtrl.text.trim();
                        tx.account = accountCtrl.text.trim();
                        tx.category = categoryCtrl.text.trim();
                      });
                      Navigator.pop(ctx);
                      _copyToClipboard();
                    },
                    child: const Text('Save & Copy'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    void Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color bannerColor;
    IconData bannerIcon;
    String bannerTitle;

    if (_engineMode == 'gemini') {
      bannerColor = Colors.purple;
      bannerIcon = Icons.auto_awesome;
      bannerTitle = 'Engine: Gemini ($geminiModelShort)';
    } else if (_engineMode == 'groq') {
      bannerColor = Colors.deepOrange;
      bannerIcon = Icons.bolt;
      bannerTitle = 'Engine: Groq ($_groqModel)';
    } else {
      bannerColor = Colors.green.shade800;
      bannerIcon = Icons.memory;
      bannerTitle = 'Engine: Local On-Device AI (100% Offline & Private)';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('UPI Extractor'),
        actions: [
          IconButton(
            tooltip: 'AI Engine Settings',
            icon: Icon(
              _engineMode == 'gemini'
                  ? Icons.auto_awesome
                  : (_engineMode == 'groq' ? Icons.bolt : Icons.memory),
              color: bannerColor,
            ),
            onPressed: _showSettingsDialog,
          ),
          const UserProfileAvatar(),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: bannerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(bannerIcon, size: 16, color: bannerColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bannerTitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: bannerColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: _showSettingsDialog,
                    child: const Text(
                      'Change',
                      style: TextStyle(fontSize: 12, decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Pick Actions Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                            onPressed: _isProcessing ? null : () => _pickAndProcess(ImageSource.gallery),
                            icon: const Icon(Icons.photo),
                            label: const Text('Pick Image'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isProcessing ? null : () => _pickAndProcess(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          tooltip: 'Capture Photo',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Batch Processing Button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BatchProcessingScreen()),
                        );
                      },
                      icon: const Icon(Icons.collections_bookmark_outlined),
                      label: const Center(child: Text('Batch Process Multiple Screenshots')),
                    ),
                  ],
                ),
              ),
            ),

            if (_imageFile != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 180,
                  width: double.infinity,
                  color: Colors.black12,
                  child: Image.file(_imageFile!, fit: BoxFit.cover),
                ),
              ),
            ],

            if (_isProcessing) ...[
              const SizedBox(height: 40),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(
                      _currentPipelineStatus.isNotEmpty
                          ? _currentPipelineStatus
                          : 'Extracting Details with $bannerTitle...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 20),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade900)),
                ),
              ),
            ],

            // Extracted Results Card
            if (_extractedTransaction != null && !_isProcessing) ...[
              const SizedBox(height: 20),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.receipt_long, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'Extracted Details',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit Values',
                                onPressed: _openEditDialog,
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copy All',
                                onPressed: _copyToClipboard,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Formatted Mono Output Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: SelectableText(
                          _extractedTransaction!.toFormattedString(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            height: 1.55,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      // Primary Copy Button - Full Width & Clean
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _copyToClipboard,
                          icon: const Icon(Icons.copy_all),
                          label: const Text(
                            'Copy Output',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Secondary Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => _syncToSheets(_extractedTransaction!),
                              icon: const Icon(Icons.table_chart_outlined, size: 18),
                              label: const Text('Sync to Sheets'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _openEditDialog,
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit Values'),
                            ),
                          ),
                        ],
                      ),
                      if (_extractedTransaction?.rawText != null) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                builder: (ctx) => Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Raw Detected AI / OCR Text',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(height: 10),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: SelectableText(
                                            _extractedTransaction!.rawText!,
                                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.visibility_outlined, size: 16),
                            label: const Text('View Raw OCR / AI Response', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  String get geminiModelShort {
    return _geminiModel.replaceAll('gemini-', '');
  }
}
