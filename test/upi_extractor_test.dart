import 'package:flutter_test/flutter_test.dart';
import 'package:upi_extractor/models/upi_transaction.dart';
import 'package:upi_extractor/services/mapping_service.dart';
import 'package:upi_extractor/services/upi_extractor_service.dart';

void main() {
  group('UPI Screenshot Extractor, Charges, Ref, and Categorization Tests', () {
    test('Extracts Airtel Prepaid mobile recharge receipt with itemized charges', () {
      const rechargeOcr = '''
2:34 9.50 KB/s 5G 5G 90%
Recharge successful
11:37 AM on 19 Nov 2026
Mobile recharged
Airtel Prepaid ₹559.46
8885817591
Plan details
Payment Details
Recharge Amount + ₹548
Service fee(inclusive of GST) + ₹5
Convenience fee(inclusive of GST) + ₹6.46
Total Amount ₹559.46
PhonePe Transaction ID
NB26111911361321896074802
Airtel Prepaid Reference ID
750322798
Debited from
653073XXXXXXXX49 ₹559.46
UTR: 248458488364
View History Recharge Again Split Expense Share Receipt
''';

      final mappings = MappingService.defaultMappings;
      final tx = UpiExtractorService.parseRecognizedText(rechargeOcr, mappings);

      expect(tx.date, '19-11-2026');
      expect(tx.app, 'PhonePe');
      expect(tx.name, 'Airtel Prepaid');
      expect(tx.id, 'NB26111911361321896074802');
      // Base recharge amount
      expect(tx.amount, 548.0);
      // Itemized charges: 5 + 6.46 = 11.46
      expect(tx.charges, 11.46);
      expect(tx.direction, 'OUT');
      // Account ending in 49 -> HDFC PhonePe (Credit)
      expect(tx.account, 'HDFC PhonePe');
      expect(tx.type, 'Credit');
      expect(tx.category, 'Bills & Utilities');
      expect(tx.ref.startsWith('REF-20261119-'), isTrue);

      final formatted = tx.toFormattedString(transactionIndex: 1);
      expect(formatted.contains('💰 Amount: 548'), isTrue);
      expect(formatted.contains('💸 Charges: 11.46'), isTrue);
      expect(formatted.contains('🏢 Account: HDFC PhonePe'), isTrue);
      expect(formatted.contains('⇄ Type: Credit'), isTrue);
    });

    test('Extracts standard PhonePe receipt without charges (Charges: 0)', () {
      const ocr = '''
9:57 62.5 KB/s 5G 5G 90%
Transaction Successful
Paid to
07:30 PM on 22 Nov 2026
NK NAGARANI KONDRU ₹500
......7459@ybl
Banking Name : Nagarani Kondru
Transfer Details
Message
advance salary
PhonePe Transaction ID
T2611221930192121195449
Debited from
XXXXXX9989 ₹500
UTR: 634956508906
''';

      final mappings = MappingService.defaultMappings;
      final tx = UpiExtractorService.parseRecognizedText(ocr, mappings);

      expect(tx.date, '22-11-2026');
      expect(tx.app, 'PhonePe');
      expect(tx.amount, 500.0);
      expect(tx.charges, 0.0);
      expect(tx.category, 'Transfer to Others');
      expect(tx.account, 'SBI');
      expect(tx.type, 'UPI');
    });

    test('Categorizes Fruits, Vegetables, and Dairy from Indian & Telugu terms', () {
      expect(UpiExtractorService.categorizeByMessage('Lemons'), 'Fruits');
      expect(UpiExtractorService.categorizeByMessage('Amla'), 'Fruits');
      expect(UpiExtractorService.categorizeByMessage('Kothimera'), 'Vegetables');
      expect(UpiExtractorService.categorizeByMessage('Carrot & beetroot'), 'Vegetables');
      expect(UpiExtractorService.categorizeByMessage('Chamadumpa & keera'), 'Vegetables');
      expect(UpiExtractorService.categorizeByMessage('Nethi beerak & bendi'), 'Vegetables');
      expect(UpiExtractorService.categorizeByMessage('Capcicum'), 'Vegetables');
      expect(UpiExtractorService.categorizeByMessage('Dosakai & kandha'), 'Vegetables');
      expect(UpiExtractorService.categorizeByMessage('Curd packer'), 'Dairy');
      expect(
        UpiExtractorService.categorizeByMessage('', name: 'GANESH MILK PARLOUR'),
        'Dairy',
      );
      expect(
        UpiExtractorService.categorizeByMessage('', name: 'TRINATH VEGETABLES'),
        'Vegetables',
      );
      expect(UpiExtractorService.categorizeByMessage('null'), 'Transfer to Others');
      expect(UpiExtractorService.categorizeByMessage('advance salary'), 'Transfer to Others');
    });

    test('Maps Account number to Credit Card when configured as Credit', () {
      const sampleCreditCardOcr = '''
Transaction Successful
Paid to Swiggy
Debited from
XXXXXX02 350
PhonePe Transaction ID
T2611221930192121190000
Message
dinner with team
''';

      final mappings = MappingService.defaultMappings;
      final tx = UpiExtractorService.parseRecognizedText(sampleCreditCardOcr, mappings);

      expect(tx.account, 'ICICI Amazon');
      expect(tx.type, 'Credit');
      expect(tx.category, 'Food & Dining');
      expect(tx.amount, 350.0);
    });

    test('Google Sheets 13 Headers and Row Mapping', () {
      expect(UpiTransaction.sheetHeaders, [
        'Date',
        'app',
        'Name',
        'direction',
        'Amount',
        'Transaction ID',
        'Status',
        'Message',
        'Mode',
        'Account',
        'Category',
        'Reference',
        'Charges',
      ]);

      final tx = UpiTransaction(
        date: '22-11-2026',
        app: 'PhonePe',
        name: 'NAGARANI KONDRU',
        id: 'T2611221930192121195449',
        msg: 'advance salary',
        amount: 500,
        charges: 0,
        direction: '🔴 OUT',
        type: 'UPI',
        account: 'SBI',
        category: 'Transfer to Others',
        ref: 'REF-20261122-BUMM',
      );

      final row = tx.toSheetRow();
      expect(row.length, 13);
      expect(row[0], '22-11-2026'); // Date
      expect(row[1], 'PhonePe'); // app
      expect(row[2], 'NAGARANI KONDRU'); // Name
      expect(row[3], 'OUT'); // direction (plain text without red/green balls)
      expect(row[4], 500); // Amount
      expect(row[5], 'T2611221930192121195449'); // Transaction ID
      expect(row[6], 'Success'); // Status
      expect(row[7], 'advance salary'); // Message
      expect(row[8], 'UPI'); // Mode
      expect(row[9], 'SBI'); // Account
      expect(row[10], 'Transfer to Others'); // Category
      expect(row[11], 'REF-20261122-BUMM'); // Reference
      expect(row[12], 0); // Charges
    });
  });
}
