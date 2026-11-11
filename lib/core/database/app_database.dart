import 'dart:io';
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

  Future<void> closeDatabase() => close();
}
