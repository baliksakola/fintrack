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

@DriftDatabase(tables: [Accounts, FinanceTransactions, LedgerEntries, Transfers])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static const _uuid = Uuid();

  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'fintrack.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('PRAGMA foreign_keys = ON');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

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
