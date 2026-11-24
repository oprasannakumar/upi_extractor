import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/upi_transaction.dart';

class SignInResult {
  final bool success;
  final GoogleSignInAccount? account;
  final String? errorMessage;

  const SignInResult({
    required this.success,
    this.account,
    this.errorMessage,
  });
}

class SyncResult {
  final bool success;
  final String message;
  final int count;
  final int newlySavedCount;
  final int fetchedExistingCount;
  final List<UpiTransaction> fetchedExisting;
  final List<UpiTransaction> newlySaved;
  final String? spreadsheetId;
  final String? spreadsheetUrl;

  const SyncResult({
    required this.success,
    required this.message,
    this.count = 0,
    this.newlySavedCount = 0,
    this.fetchedExistingCount = 0,
    this.fetchedExisting = const [],
    this.newlySaved = const [],
    this.spreadsheetId,
    this.spreadsheetUrl,
  });

  factory SyncResult.success({
    required int count,
    int newlySavedCount = 0,
    int fetchedExistingCount = 0,
    List<UpiTransaction> fetchedExisting = const [],
    List<UpiTransaction> newlySaved = const [],
    String? spreadsheetId,
    String? spreadsheetUrl,
    String? customMessage,
  }) {
    String msg;
    if (customMessage != null) {
      msg = customMessage;
    } else if (newlySavedCount > 0 && fetchedExistingCount > 0) {
      msg = 'Saved $newlySavedCount new transaction(s); $fetchedExistingCount already in Sheet (fetched)';
    } else if (fetchedExistingCount > 0) {
      msg = fetchedExistingCount == 1
          ? 'Transaction ID already in Sheet — fetched existing record!'
          : 'All $fetchedExistingCount transaction(s) already in Sheet — fetched existing records!';
    } else {
      msg = 'Successfully saved $newlySavedCount transaction(s) to "account ledger" > "Details"';
    }

    return SyncResult(
      success: true,
      message: msg,
      count: count,
      newlySavedCount: newlySavedCount,
      fetchedExistingCount: fetchedExistingCount,
      fetchedExisting: fetchedExisting,
      newlySaved: newlySaved,
      spreadsheetId: spreadsheetId,
      spreadsheetUrl: spreadsheetUrl,
    );
  }

  factory SyncResult.failure(String message) {
    return SyncResult(
      success: false,
      message: message,
    );
  }
}

class GoogleSheetsService extends ChangeNotifier {
  static final GoogleSheetsService instance = GoogleSheetsService._internal();
  GoogleSheetsService._internal();

  static const List<String> _scopes = [
    drive.DriveApi.driveFileScope,
    sheets.SheetsApi.spreadsheetsScope,
  ];

  static const String _prefKeyAutoSync = 'sheets_auto_sync';
  static const String _prefKeySpreadsheetId = 'sheets_spreadsheet_id';
  static const String _prefKeyUserEmail = 'sheets_user_email';
  static const String _prefKeyUserName = 'sheets_user_name';
  static const String _prefKeyUserPhoto = 'sheets_user_photo';

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: _scopes,
  );

  bool _initialized = false;
  GoogleSignInAccount? _currentUser;
  bool _autoSync = true;
  String? _spreadsheetId;
  String? _savedEmail;
  String? _savedName;
  String? _savedPhotoUrl;

  bool get isConnected => _currentUser != null || (_savedEmail != null && _savedEmail!.isNotEmpty);
  GoogleSignInAccount? get currentUser => _currentUser;
  String get userEmail => _currentUser?.email ?? _savedEmail ?? '';
  String get userName => _currentUser?.displayName ?? _savedName ?? '';
  String get userPhotoUrl => _currentUser?.photoUrl ?? _savedPhotoUrl ?? '';
  bool get autoSync => _autoSync;
  String? get spreadsheetId => _spreadsheetId;
  String? get spreadsheetUrl => _spreadsheetId != null
      ? 'https://docs.google.com/spreadsheets/d/$_spreadsheetId/edit'
      : null;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _autoSync = prefs.getBool(_prefKeyAutoSync) ?? true;
    _spreadsheetId = prefs.getString(_prefKeySpreadsheetId);
    _savedEmail = prefs.getString(_prefKeyUserEmail);
    _savedName = prefs.getString(_prefKeyUserName);
    _savedPhotoUrl = prefs.getString(_prefKeyUserPhoto);

    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        _savedEmail = _currentUser!.email;
        _savedName = _currentUser!.displayName;
        _savedPhotoUrl = _currentUser!.photoUrl;
        await prefs.setString(_prefKeyUserEmail, _savedEmail ?? '');
        await prefs.setString(_prefKeyUserName, _savedName ?? '');
        if (_savedPhotoUrl != null) {
          await prefs.setString(_prefKeyUserPhoto, _savedPhotoUrl!);
        }
      }
    } catch (e) {
      debugPrint('Google silent sign-in check: $e');
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setAutoSync(bool enabled) async {
    _autoSync = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyAutoSync, enabled);
  }

  Future<void> setSpreadsheetId(String? id) async {
    _spreadsheetId = id?.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_spreadsheetId != null && _spreadsheetId!.isNotEmpty) {
      await prefs.setString(_prefKeySpreadsheetId, _spreadsheetId!);
    } else {
      await prefs.remove(_prefKeySpreadsheetId);
    }
  }

  Future<SignInResult> signIn() async {
    try {
      await init();
      // Opens standard Android Google Play Services account chooser
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return const SignInResult(
          success: false,
          errorMessage: 'Sign-in was canceled',
        );
      }
      _currentUser = account;
      _savedEmail = account.email;
      _savedName = account.displayName;
      _savedPhotoUrl = account.photoUrl;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyUserEmail, _savedEmail ?? '');
      await prefs.setString(_prefKeyUserName, _savedName ?? '');
      if (_savedPhotoUrl != null) {
        await prefs.setString(_prefKeyUserPhoto, _savedPhotoUrl!);
      }
      return SignInResult(success: true, account: account);
    } catch (e) {
      debugPrint('Google Sign-in failed: $e');
      return SignInResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      _savedEmail = null;
      _savedName = null;
      _savedPhotoUrl = null;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyUserEmail);
      await prefs.remove(_prefKeyUserName);
      await prefs.remove(_prefKeyUserPhoto);
    } catch (e) {
      debugPrint('Google Sign-out failed: $e');
    }
  }

  /// Locate or create "account ledger" spreadsheet and ensure "Details" tab exists with headers
  Future<String> _ensureSpreadsheetAndSheet(sheets.SheetsApi sheetsApi, drive.DriveApi driveApi) async {
    String? targetId = _spreadsheetId;

    // 1. If we have a cached spreadsheet ID, verify it exists and is accessible
    if (targetId != null && targetId.isNotEmpty) {
      try {
        final existing = await driveApi.files.get(
          targetId,
          $fields: 'id, name, trashed',
        ) as drive.File;
        if (existing.trashed == true) {
          targetId = null;
        }
      } catch (e) {
        targetId = null;
      }
    }

    // 2. If no valid ID, search Google Drive for "account ledger"
    if (targetId == null) {
      try {
        const query = "name = 'account ledger' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false";
        final fileList = await driveApi.files.list(
          q: query,
          spaces: 'drive',
          $fields: 'files(id, name)',
        );
        if (fileList.files != null && fileList.files!.isNotEmpty) {
          targetId = fileList.files!.first.id;
        }
      } catch (e) {
        debugPrint('Drive search error: $e');
      }
    }

    // 3. If still not found, create new "account ledger" spreadsheet with "Details" sheet
    if (targetId == null) {
      final newSpreadsheet = sheets.Spreadsheet(
        properties: sheets.SpreadsheetProperties(title: 'account ledger'),
        sheets: [
          sheets.Sheet(
            properties: sheets.SheetProperties(
              title: 'Details',
              gridProperties: sheets.GridProperties(
                rowCount: 1000,
                columnCount: 15,
                frozenRowCount: 1,
              ),
            ),
          ),
        ],
      );
      final created = await sheetsApi.spreadsheets.create(newSpreadsheet);
      targetId = created.spreadsheetId;
      if (targetId == null) {
        throw Exception('Failed to create "account ledger" spreadsheet on Google Drive');
      }

      // Write headers to row 1
      await _writeHeaders(sheetsApi, targetId);
    } else {
      // 4. Spreadsheet exists: verify "Details" sheet exists
      final ss = await sheetsApi.spreadsheets.get(targetId);
      final hasDetails = ss.sheets?.any((s) => s.properties?.title == 'Details') ?? false;
      if (!hasDetails) {
        final addSheetReq = sheets.BatchUpdateSpreadsheetRequest(
          requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(
                  title: 'Details',
                  gridProperties: sheets.GridProperties(frozenRowCount: 1),
                ),
              ),
            ),
          ],
        );
        await sheetsApi.spreadsheets.batchUpdate(addSheetReq, targetId);
        await _writeHeaders(sheetsApi, targetId);
      } else {
        try {
          final headerCheck = await sheetsApi.spreadsheets.values.get(targetId, 'Details!A1:M1');
          if (headerCheck.values == null || headerCheck.values!.isEmpty || headerCheck.values![0].isEmpty) {
            await _writeHeaders(sheetsApi, targetId);
          }
        } catch (_) {
          await _writeHeaders(sheetsApi, targetId);
        }
      }
    }

    await setSpreadsheetId(targetId);
    return targetId;
  }

  /// Write the exact 13 headers to row 1 of 'Details' sheet
  Future<void> _writeHeaders(sheets.SheetsApi sheetsApi, String spreadsheetId) async {
    final headerRange = sheets.ValueRange(
      values: [UpiTransaction.sheetHeaders],
    );
    await sheetsApi.spreadsheets.values.update(
      headerRange,
      spreadsheetId,
      'Details!A1:M1',
      valueInputOption: 'USER_ENTERED',
    );
  }

  /// Converts a row of values from "Details" sheet into a UpiTransaction instance
  static UpiTransaction _rowToTransaction(List<dynamic> row, {String fallbackDate = ''}) {
    final dateStr = row.isNotEmpty ? row[0].toString().trim() : fallbackDate;
    final appStr = row.length > 1 ? row[1].toString().trim() : 'PhonePe';
    final nameStr = row.length > 2 ? row[2].toString().trim() : '';
    final rawDir = row.length > 3 ? row[3].toString().replaceAll(RegExp(r'[🔴🟢]'), '').trim() : 'OUT';
    final dirStr = rawDir.toUpperCase().contains('IN') ? 'IN' : 'OUT';
    final amtStr = row.length > 4 ? row[4].toString().replaceAll(',', '').trim() : '0';
    final idStr = row.length > 5 ? row[5].toString().trim() : '';
    final msgStr = row.length > 7 ? row[7].toString().trim() : '';
    final modeStr = row.length > 8 ? row[8].toString().trim() : 'UPI';
    final accountStr = row.length > 9 ? row[9].toString().trim() : '';
    final categoryStr = row.length > 10 ? row[10].toString().trim() : 'Transfer to Others';
    final refStr = row.length > 11 ? row[11].toString().trim() : '';
    final chargesStr = row.length > 12 ? row[12].toString().replaceAll(',', '').trim() : '0';

    final amount = double.tryParse(amtStr) ?? 0.0;
    final charges = double.tryParse(chargesStr) ?? 0.0;

    return UpiTransaction(
      date: dateStr,
      app: appStr,
      name: nameStr,
      id: idStr,
      msg: (msgStr == 'null' || msgStr == 'NULL') ? '' : msgStr,
      amount: amount,
      charges: charges,
      direction: dirStr,
      type: modeStr.isNotEmpty ? modeStr : 'UPI',
      account: accountStr,
      category: categoryStr,
      ref: refStr.isNotEmpty ? refStr : UpiTransaction.generateRef(dateStr, idStr),
    );
  }

  /// Sync transactions to Google Sheets:
  /// Before appending, checks whether transaction ID is already available in the sheet.
  /// If available -> fetches that one from the sheet.
  /// Else -> saves the new transaction into the sheet.
  Future<SyncResult> syncTransactions(List<UpiTransaction> transactions) async {
    if (transactions.isEmpty) {
      return SyncResult.success(count: 0, customMessage: 'No transactions to sync');
    }

    await init();

    if (!isConnected) {
      return SyncResult.failure(
        'Google Account is not connected. Please connect your Google account in Settings.',
      );
    }

    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) {
        final res = await signIn();
        if (!res.success) {
          throw Exception('Google Account authentication expired. Please reconnect.');
        }
      }
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) {
        throw Exception('Unable to acquire authenticated Google HTTP client');
      }

      final driveApi = drive.DriveApi(authClient);
      final sheetsApi = sheets.SheetsApi(authClient);

      // Ensure "account ledger" and "Details" tab
      final ssId = await _ensureSpreadsheetAndSheet(sheetsApi, driveApi);

      // 1. Fetch all existing rows to inspect Transaction IDs
      final existingResponse = await sheetsApi.spreadsheets.values.get(
        ssId,
        'Details!A2:M',
      );
      final existingRows = existingResponse.values ?? [];

      // Map existing records by normalized Transaction ID
      final Map<String, UpiTransaction> existingById = {};
      for (final row in existingRows) {
        if (row.length > 5) {
          final rowId = row[5]?.toString().trim() ?? '';
          if (rowId.isNotEmpty && rowId != 'N/A') {
            existingById[rowId.toLowerCase()] = _rowToTransaction(row);
          }
        }
      }

      final List<UpiTransaction> newlySaved = [];
      final List<UpiTransaction> fetchedExisting = [];

      for (final tx in transactions) {
        final normalizedId = tx.id.trim().toLowerCase();

        // Check if transaction ID already exists in sheets
        if (normalizedId.isNotEmpty && normalizedId != 'n/a' && existingById.containsKey(normalizedId)) {
          final fromSheet = existingById[normalizedId]!;
          fetchedExisting.add(fromSheet);

          // Update transaction fields with existing record from sheets
          tx.date = fromSheet.date;
          tx.app = fromSheet.app;
          tx.name = fromSheet.name;
          tx.amount = fromSheet.amount;
          tx.charges = fromSheet.charges;
          tx.direction = fromSheet.direction;
          tx.type = fromSheet.type;
          tx.account = fromSheet.account;
          tx.category = fromSheet.category;
          tx.ref = fromSheet.ref;
          tx.msg = fromSheet.msg;
        } else {
          // Not available in sheet -> proceed to save
          newlySaved.add(tx);
        }
      }

      // 2. If there are new transactions, append them to the sheet
      if (newlySaved.isNotEmpty) {
        final rowData = newlySaved.map((t) => t.toSheetRow()).toList();
        final appendBody = sheets.ValueRange(values: rowData);

        await sheetsApi.spreadsheets.values.append(
          appendBody,
          ssId,
          'Details!A:M',
          valueInputOption: 'USER_ENTERED',
          insertDataOption: 'INSERT_ROWS',
        );
      }

      final url = 'https://docs.google.com/spreadsheets/d/$ssId/edit';

      return SyncResult.success(
        count: transactions.length,
        newlySavedCount: newlySaved.length,
        fetchedExistingCount: fetchedExisting.length,
        fetchedExisting: fetchedExisting,
        newlySaved: newlySaved,
        spreadsheetId: ssId,
        spreadsheetUrl: url,
      );
    } catch (e) {
      debugPrint('Direct Google Sheets sync error: $e');
      return SyncResult.failure('Sheets sync error: $e');
    }
  }

  /// Fetch saved transactions from "account ledger" > "Details" based on selected date
  Future<List<UpiTransaction>> fetchTransactionsByDate(String targetDate) async {
    await init();
    if (!isConnected) {
      throw Exception('Google Account is not connected. Please connect first.');
    }

    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      final res = await signIn();
      if (!res.success) {
        throw Exception('Google Account authentication expired. Please reconnect.');
      }
    }
    final authClient = await _googleSignIn.authenticatedClient();
    if (authClient == null) {
      throw Exception('Unable to acquire authenticated Google HTTP client');
    }

    final driveApi = drive.DriveApi(authClient);
    final sheetsApi = sheets.SheetsApi(authClient);

    // Locate "account ledger" spreadsheet and "Details" sheet
    final ssId = await _ensureSpreadsheetAndSheet(sheetsApi, driveApi);

    // Fetch all values starting from row 2 (skipping header row)
    final response = await sheetsApi.spreadsheets.values.get(
      ssId,
      'Details!A2:M',
    );

    final rows = response.values;
    if (rows == null || rows.isEmpty) {
      return [];
    }

    final cleanTarget = _normalizeDate(targetDate);
    final List<UpiTransaction> results = [];

    for (final row in rows) {
      if (row.isEmpty) continue;

      final rowDateStr = row.isNotEmpty ? row[0].toString().trim() : '';
      if (cleanTarget.isNotEmpty && _normalizeDate(rowDateStr) != cleanTarget) {
        continue;
      }

      results.add(_rowToTransaction(row, fallbackDate: targetDate));
    }

    return results;
  }

  /// Normalizes date strings like "22-11-2026", "22/11/2026", "2026-11-22" into uniform "22-11-2026"
  static String _normalizeDate(String input) {
    final clean = input.replaceAll('/', '-').replaceAll('.', '-').trim();
    final parts = clean.split('-');
    if (parts.length == 3) {
      if (parts[0].length == 4) {
        // yyyy-MM-dd -> dd-MM-yyyy
        final y = parts[0];
        final m = parts[1].padLeft(2, '0');
        final d = parts[2].padLeft(2, '0');
        return '$d-$m-$y';
      } else if (parts[2].length == 4) {
        // dd-MM-yyyy
        final d = parts[0].padLeft(2, '0');
        final m = parts[1].padLeft(2, '0');
        final y = parts[2];
        return '$d-$m-$y';
      }
    }
    return clean;
  }
}
