import 'dart:io';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'tables.dart';

part 'app_database.g.dart';

final databaseProvider = Provider<AppDatabase>((ref) =>
    throw UnimplementedError('Database provider not initialized'));

@DriftDatabase(tables: [Accounts, FinanceTransactions, LedgerEntries, Transfers, Budgets, Bills])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static const _uuid = Uuid();

  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'fintrack.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(budgets);
      }
      if (from < 3) {
        await m.createTable(bills);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  Stream<List<Bill>> watchBills() =>
      (select(bills)..orderBy([
        (b) => OrderingTerm.asc(b.isPaid),
        (b) => OrderingTerm.asc(b.dueDate),
      ])).watch();

  Future<void> addBill({
    required String title,
    required String category,
    required int amount,
    required DateTime dueDate,
    required bool isMonthly,
  }) async {
    if (title.trim().isEmpty || category.trim().isEmpty || amount <= 0) {
      throw ArgumentError('Data tagihan tidak valid.');
    }
    await into(bills).insert(BillsCompanion.insert(
      id: _uuid.v4(),
      title: title.trim(),
      category: category.trim(),
      amount: amount,
      dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
      isMonthly: Value(isMonthly),
      createdAt: DateTime.now(),
    ));
  }

  Future<void> markBillPaid({
    required String billId,
    required String accountId,
  }) async {
    final bill = await (select(bills)..where((b) => b.id.equals(billId)))
        .getSingleOrNull();
    if (bill == null) throw StateError('Tagihan tidak ditemukan.');
    if (bill.isPaid) throw StateError('Tagihan sudah ditandai lunas.');
    final account = await (select(accounts)..where((a) =>
      a.id.equals(accountId) & a.archived.equals(false))).getSingleOrNull();
    if (account == null) throw StateError('Rekening tidak ditemukan.');

    final now = DateTime.now();
    final transactionId = _uuid.v4();
    await transaction(() async {
      await into(financeTransactions).insert(FinanceTransactionsCompanion.insert(
        id: transactionId,
        type: 'expense',
        accountId: accountId,
        amount: bill.amount,
        title: 'Pembayaran: ${bill.title}',
        category: Value(bill.category),
        occurredAt: now,
        createdAt: now,
      ));
      await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
        id: _uuid.v4(),
        transactionId: transactionId,
        accountId: accountId,
        amountDelta: -bill.amount,
        createdAt: now,
      ));
      await (update(bills)..where((b) => b.id.equals(billId))).write(
        BillsCompanion(isPaid: const Value(true), paidAt: Value(now)),
      );

      if (bill.isMonthly) {
        final nextMonth = DateTime(bill.dueDate.year, bill.dueDate.month + 1);
        final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
        final nextDueDate = DateTime(
          nextMonth.year,
          nextMonth.month,
          bill.dueDate.day > lastDay ? lastDay : bill.dueDate.day,
        );
        await into(bills).insert(BillsCompanion.insert(
          id: _uuid.v4(),
          title: bill.title,
          category: bill.category,
          amount: bill.amount,
          dueDate: nextDueDate,
          isMonthly: const Value(true),
          createdAt: now,
        ));
      }
    });
  }

  Future<void> deleteBill(String billId) =>
      (delete(bills)..where((b) => b.id.equals(billId))).go();

  Stream<List<Budget>> watchBudgetsForMonth(DateTime month) {
    final monthStart = DateTime(month.year, month.month);
    return (select(budgets)
      ..where((b) => b.month.equals(monthStart))
      ..orderBy([(b) => OrderingTerm.asc(b.category)])).watch();
  }

  Future<void> saveBudget({
    required String category,
    required int monthlyLimit,
    required DateTime month,
  }) async {
    if (category.trim().isEmpty || monthlyLimit <= 0) {
      throw ArgumentError('Kategori dan batas anggaran harus valid.');
    }
    final monthStart = DateTime(month.year, month.month);
    final existing = await (select(budgets)
      ..where((b) => b.category.equals(category.trim()) & b.month.equals(monthStart)))
      .getSingleOrNull();
    if (existing == null) {
      await into(budgets).insert(BudgetsCompanion.insert(
        id: _uuid.v4(),
        category: category.trim(),
        monthlyLimit: monthlyLimit,
        month: monthStart,
        createdAt: DateTime.now(),
      ));
    } else {
      await (update(budgets)..where((b) => b.id.equals(existing.id))).write(
        BudgetsCompanion(monthlyLimit: Value(monthlyLimit)),
      );
    }
  }

  Future<void> deleteBudget(String budgetId) =>
      (delete(budgets)..where((b) => b.id.equals(budgetId))).go();

  Future<void> addAccount(String name, String type, int openingBalance) async {
    if (name.trim().isEmpty || openingBalance < 0) {
      throw ArgumentError('Data rekening tidak valid.');
    }
    await into(accounts).insert(AccountsCompanion.insert(
      id: _uuid.v4(), name: name.trim(), type: type,
      openingBalance: Value(openingBalance), createdAt: DateTime.now(),
    ));
  }

  Stream<List<Account>> watchAccounts() =>
      (select(accounts)..where((a) => a.archived.equals(false))
        ..orderBy([(a) => OrderingTerm.asc(a.name)])).watch();

  Stream<int> watchTotalBalance() => customSelect(
    'SELECT COALESCE((SELECT SUM(opening_balance) FROM accounts WHERE archived = 0), 0) + '
    'COALESCE((SELECT SUM(amount_delta) FROM ledger_entries), 0) AS total',
    readsFrom: {accounts, ledgerEntries},
  ).watch().map((rows) => rows.first.read<int>('total'));

  Stream<List<FinanceTransaction>> watchTransactions() =>
      (select(financeTransactions)..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])).watch();

  Future<void> addIncome({
    required String accountId, required int amount,
    required String title, String? category,
  }) => _addTransaction('income', accountId, amount, title, category);

  Future<void> addExpense({
    required String accountId, required int amount,
    required String title, String? category,
  }) => _addTransaction('expense', accountId, amount, title, category);

  Future<void> _addTransaction(
    String type, String accountId, int amount, String title, String? category,
  ) async {
    if (amount <= 0 || title.trim().isEmpty) {
      throw ArgumentError('Nominal dan deskripsi wajib valid.');
    }
    final account = await (select(accounts)
      ..where((a) => a.id.equals(accountId) & a.archived.equals(false)))
      .getSingleOrNull();
    if (account == null) throw StateError('Rekening tidak ditemukan.');
    final id = _uuid.v4();
    final now = DateTime.now();
    final delta = type == 'income' ? amount : -amount;
    await transaction(() async {
      await into(financeTransactions).insert(FinanceTransactionsCompanion.insert(
        id: id, type: type, accountId: accountId, amount: amount,
        title: title.trim(), category: Value(category),
        occurredAt: now, createdAt: now,
      ));
      await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
        id: _uuid.v4(), transactionId: id, accountId: accountId,
        amountDelta: delta, createdAt: now,
      ));
    });
  }

  Future<void> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int amount,
    required String title,
  }) async {
    if (amount <= 0 || title.trim().isEmpty || fromAccountId == toAccountId) {
      throw ArgumentError('Data transfer tidak valid.');
    }
    final from = await (select(accounts)..where((a) =>
      a.id.equals(fromAccountId) & a.archived.equals(false))).getSingleOrNull();
    final to = await (select(accounts)..where((a) =>
      a.id.equals(toAccountId) & a.archived.equals(false))).getSingleOrNull();
    if (from == null || to == null) throw StateError('Rekening tidak ditemukan.');
    final id = _uuid.v4();
    final now = DateTime.now();
    await transaction(() async {
      await into(financeTransactions).insert(FinanceTransactionsCompanion.insert(
        id: id, type: 'transfer', accountId: fromAccountId, amount: amount,
        title: title.trim(), occurredAt: now, createdAt: now,
      ));
      await into(transfers).insert(TransfersCompanion.insert(
        id: _uuid.v4(), transactionId: id, fromAccountId: fromAccountId,
        toAccountId: toAccountId, createdAt: now,
      ));
      await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
        id: _uuid.v4(), transactionId: id, accountId: fromAccountId,
        amountDelta: -amount, createdAt: now,
      ));
      await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
        id: _uuid.v4(), transactionId: id, accountId: toAccountId,
        amountDelta: amount, createdAt: now,
      ));
    });
  }

  Future<void> updateTransaction({
    required String transactionId,
    required String accountId,
    required int amount,
    required String title,
    String? category,
  }) async {
    if (amount <= 0 || title.trim().isEmpty) {
      throw ArgumentError('Nominal dan deskripsi wajib valid.');
    }
    final current = await (select(financeTransactions)
      ..where((t) => t.id.equals(transactionId))).getSingleOrNull();
    if (current == null) throw StateError('Transaksi tidak ditemukan.');
    if (current.type == 'transfer') {
      throw StateError('Transaksi transfer belum dapat diedit.');
    }
    final account = await (select(accounts)..where((a) =>
      a.id.equals(accountId) & a.archived.equals(false))).getSingleOrNull();
    if (account == null) throw StateError('Rekening tidak ditemukan.');
    final delta = current.type == 'income' ? amount : -amount;
    await transaction(() async {
      await (delete(ledgerEntries)
        ..where((entry) => entry.transactionId.equals(transactionId))).go();
      await (update(financeTransactions)
        ..where((t) => t.id.equals(transactionId))).write(
          FinanceTransactionsCompanion(
            accountId: Value(accountId),
            amount: Value(amount),
            title: Value(title.trim()),
            category: Value(category),
          ),
        );
      await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
        id: _uuid.v4(),
        transactionId: transactionId,
        accountId: accountId,
        amountDelta: delta,
        createdAt: DateTime.now(),
      ));
    });
  }

  Future<void> deleteTransaction(String transactionId) async {
    final current = await (select(financeTransactions)
      ..where((t) => t.id.equals(transactionId))).getSingleOrNull();
    if (current == null) throw StateError('Transaksi tidak ditemukan.');
    await transaction(() async {
      await (delete(ledgerEntries)
        ..where((entry) => entry.transactionId.equals(transactionId))).go();
      await (delete(transfers)
        ..where((transfer) => transfer.transactionId.equals(transactionId))).go();
      await (delete(financeTransactions)
        ..where((t) => t.id.equals(transactionId))).go();
    });
  }

  Future<int> balanceFor(String accountId) async {
    final account = await (select(accounts)
      ..where((a) => a.id.equals(accountId))).getSingle();
    final total = await customSelect(
      'SELECT COALESCE(SUM(amount_delta), 0) AS total FROM ledger_entries WHERE account_id = ?',
      variables: [Variable.withString(accountId)],
      readsFrom: {ledgerEntries},
    ).getSingle();
    return account.openingBalance + total.read<int>('total');
  }

  Future<String> exportBackupJson() async {
    final backup = <String, dynamic>{
      'format': 'fintrack-backup',
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'accounts': (await select(accounts).get()).map((row) => {
        'id': row.id, 'name': row.name, 'type': row.type,
        'openingBalance': row.openingBalance, 'archived': row.archived,
        'createdAt': row.createdAt.toIso8601String(),
      }).toList(),
      'financeTransactions': (await select(financeTransactions).get()).map((row) => {
        'id': row.id, 'type': row.type, 'accountId': row.accountId,
        'amount': row.amount, 'title': row.title, 'category': row.category,
        'occurredAt': row.occurredAt.toIso8601String(),
        'createdAt': row.createdAt.toIso8601String(),
      }).toList(),
      'ledgerEntries': (await select(ledgerEntries).get()).map((row) => {
        'id': row.id, 'transactionId': row.transactionId,
        'accountId': row.accountId, 'amountDelta': row.amountDelta,
        'createdAt': row.createdAt.toIso8601String(),
      }).toList(),
      'transfers': (await select(transfers).get()).map((row) => {
        'id': row.id, 'transactionId': row.transactionId,
        'fromAccountId': row.fromAccountId, 'toAccountId': row.toAccountId,
        'createdAt': row.createdAt.toIso8601String(),
      }).toList(),
      'budgets': (await select(budgets).get()).map((row) => {
        'id': row.id, 'category': row.category,
        'monthlyLimit': row.monthlyLimit,
        'month': row.month.toIso8601String(),
        'createdAt': row.createdAt.toIso8601String(),
      }).toList(),
      'bills': (await select(bills).get()).map((row) => {
        'id': row.id, 'title': row.title, 'category': row.category,
        'amount': row.amount, 'dueDate': row.dueDate.toIso8601String(),
        'isPaid': row.isPaid, 'isMonthly': row.isMonthly,
        'paidAt': row.paidAt?.toIso8601String(),
        'createdAt': row.createdAt.toIso8601String(),
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  Future<void> restoreBackupJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'fintrack-backup' ||
        decoded['version'] != 1) {
      throw const FormatException('Format backup FinTrack tidak dikenali.');
    }

    List<Map<String, dynamic>> rows(String key) {
      final value = decoded[key];
      if (value is! List) throw FormatException('Data $key tidak valid.');
      return value.map((item) {
        if (item is! Map) throw FormatException('Baris $key tidak valid.');
        return Map<String, dynamic>.from(item);
      }).toList();
    }

    final accountRows = rows('accounts');
    final transactionRows = rows('financeTransactions');
    final ledgerRows = rows('ledgerEntries');
    final transferRows = rows('transfers');
    final budgetRows = rows('budgets');
    final billRows = rows('bills');

    DateTime date(Map<String, dynamic> row, String key) {
      final value = row[key];
      if (value is! String) throw FormatException('Tanggal $key tidak valid.');
      return DateTime.parse(value);
    }

    String string(Map<String, dynamic> row, String key) {
      final value = row[key];
      if (value is! String) throw FormatException('Kolom $key tidak valid.');
      return value;
    }

    int integer(Map<String, dynamic> row, String key) {
      final value = row[key];
      if (value is! int) throw FormatException('Kolom $key tidak valid.');
      return value;
    }

    bool boolean(Map<String, dynamic> row, String key) {
      final value = row[key];
      if (value is! bool) throw FormatException('Kolom $key tidak valid.');
      return value;
    }

    await transaction(() async {
      await delete(ledgerEntries).go();
      await delete(transfers).go();
      await delete(financeTransactions).go();
      await delete(budgets).go();
      await delete(bills).go();
      await delete(accounts).go();

      for (final row in accountRows) {
        await into(accounts).insert(AccountsCompanion.insert(
          id: string(row, 'id'), name: string(row, 'name'),
          type: string(row, 'type'),
          openingBalance: Value(integer(row, 'openingBalance')),
          archived: Value(boolean(row, 'archived')),
          createdAt: date(row, 'createdAt'),
        ));
      }
      for (final row in transactionRows) {
        final category = row['category'];
        await into(financeTransactions).insert(FinanceTransactionsCompanion.insert(
          id: string(row, 'id'), type: string(row, 'type'),
          accountId: string(row, 'accountId'), amount: integer(row, 'amount'),
          title: string(row, 'title'),
          category: Value(category is String ? category : null),
          occurredAt: date(row, 'occurredAt'), createdAt: date(row, 'createdAt'),
        ));
      }
      for (final row in ledgerRows) {
        await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
          id: string(row, 'id'),
          transactionId: string(row, 'transactionId'),
          accountId: string(row, 'accountId'),
          amountDelta: integer(row, 'amountDelta'),
          createdAt: date(row, 'createdAt'),
        ));
      }
      for (final row in transferRows) {
        await into(transfers).insert(TransfersCompanion.insert(
          id: string(row, 'id'),
          transactionId: string(row, 'transactionId'),
          fromAccountId: string(row, 'fromAccountId'),
          toAccountId: string(row, 'toAccountId'),
          createdAt: date(row, 'createdAt'),
        ));
      }
      for (final row in budgetRows) {
        await into(budgets).insert(BudgetsCompanion.insert(
          id: string(row, 'id'), category: string(row, 'category'),
          monthlyLimit: integer(row, 'monthlyLimit'),
          month: date(row, 'month'), createdAt: date(row, 'createdAt'),
        ));
      }
      for (final row in billRows) {
        final paidAt = row['paidAt'];
        await into(bills).insert(BillsCompanion.insert(
          id: string(row, 'id'), title: string(row, 'title'),
          category: string(row, 'category'), amount: integer(row, 'amount'),
          dueDate: date(row, 'dueDate'),
          isPaid: Value(boolean(row, 'isPaid')),
          isMonthly: Value(boolean(row, 'isMonthly')),
          paidAt: Value(paidAt is String ? DateTime.parse(paidAt) : null),
          createdAt: date(row, 'createdAt'),
        ));
      }
    });
  }

  Future<void> closeDatabase() => close();
}
