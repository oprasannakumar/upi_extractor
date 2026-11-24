import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'screens/account_mappings_screen.dart';
import 'screens/batch_processing_screen.dart';
import 'screens/extractor_screen.dart';
import 'screens/history_screen.dart';
import 'services/google_sheets_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UpiExtractorApp());
  unawaited(GoogleSheetsService.instance.init());
}

class UpiExtractorApp extends StatelessWidget {
  const UpiExtractorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UPI Extractor',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1B5E20),
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  StreamSubscription? _intentSub;
  String? _sharedSinglePath;

  @override
  void initState() {
    super.initState();
    _initReceiveSharing();
  }

  void _initReceiveSharing() {
    // For sharing images while app is running in memory
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFiles(value);
      }
    }, onError: (err) {
      // Ignore sharing stream error
    });

    // For sharing images when app is launched from closed state
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFiles(value);
      }
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;

    final imagePaths = files
        .where((f) => f.path.isNotEmpty)
        .map((f) => f.path)
        .toList();

    if (imagePaths.isEmpty) return;

    if (imagePaths.length == 1) {
      setState(() {
        _sharedSinglePath = imagePaths.first;
        _currentIndex = 0; // Go to extractor tab
      });
    } else {
      // Open batch processing
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BatchProcessingScreen(initialImagePaths: imagePaths),
        ),
      );
    }
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      ExtractorScreen(
        key: ValueKey(_sharedSinglePath),
        sharedImagePath: _sharedSinglePath,
      ),
      const AccountMappingsScreen(),
      const HistoryScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Extract',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Mappings',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
