import 'package:flutter_test/flutter_test.dart';
import 'package:card_vault/services/bank_directory_service.dart';

void main() {
  group('BankDirectoryService Tests', () {
    test('Search for acronym PNB returns Punjab National Bank', () {
      final results = BankDirectoryService.search('pnb');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.name, 'Punjab National Bank');
      expect(results.first.displayName, 'Punjab National Bank (PNB)');
    });

    test('Search for acronym SBI returns State Bank of India', () {
      final results = BankDirectoryService.search('sbi');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.name, 'State Bank of India');
      expect(results.first.displayName, 'State Bank of India (SBI)');
    });

    test('Search for BOB returns Bank of Baroda', () {
      final results = BankDirectoryService.search('bob');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.name, 'Bank of Baroda');
    });

    test('Search for HDFC returns HDFC Bank', () {
      final results = BankDirectoryService.search('hdfc');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.name, 'HDFC Bank');
    });

    test('normalizeBankName converts abbreviations to canonical names', () {
      expect(BankDirectoryService.normalizeBankName('PNB'), 'Punjab National Bank');
      expect(BankDirectoryService.normalizeBankName('pnb'), 'Punjab National Bank');
      expect(BankDirectoryService.normalizeBankName('SBI'), 'State Bank of India');
      expect(BankDirectoryService.normalizeBankName('sbi'), 'State Bank of India');
      expect(BankDirectoryService.normalizeBankName('BOB'), 'Bank of Baroda');
      expect(BankDirectoryService.normalizeBankName('HDFC'), 'HDFC Bank');
      expect(BankDirectoryService.normalizeBankName('ICICI'), 'ICICI Bank');
      expect(BankDirectoryService.normalizeBankName('Custom Co-op Bank'), 'Custom Co-op Bank');
    });
  });
}
