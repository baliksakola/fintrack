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

@DriftDatabase(tables: [Accounts, FinanceTransactions, LedgerEntries, Transfers, Budgets, Bills, Debts, DebtPayments, FinancialGoals, RecurringTransactions])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static const _uuid = Uuid();

  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'fintrack.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  @override
  int get schemaVersion => 8;

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
      if (from < 4) {
        await m.createTable(debts);
        await m.createTable(debtPayments);
      }
      if (from < 5) {
        await m.addColumn(bills, bills.recurrenceEndDate);
      }
      if (from < 6) {
        await m.createTable(financialGoals);
      }
      if (from < 8) {
        final existingRecurringTable = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'recurring_transactions'",
        ).get();
        if (existingRecurringTable.isEmpty) {
          await m.createTable(recurringTransactions);
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );


  Stream<List<Debt>> watchDebts() =>
      (select(debts)..orderBy([
        (d) => OrderingTerm.asc(d.dueDate),
        (d) => OrderingTerm.desc(d.createdAt),
      ])).watch();

  Future<void> addDebt({
    required String direction,
    required String partyName,
    required String title,
    required int amount,
    DateTime? dueDate,
    String? notes,
  }) async {
    if (!['payable', 'receivable'].contains(direction) ||
        partyName.trim().isEmpty || title.trim().isEmpty || amount <= 0) {
      throw ArgumentError('Data utang/piutang tidak valid.');
    }
    await into(debts).insert(DebtsCompanion.insert(
      id: _uuid.v4(),
      direction: direction,
      partyName: partyName.trim(),
      title: title.trim(),
      amount: amount,
      dueDate: Value(dueDate == null
          ? null
          : DateTime(dueDate.year, dueDate.month, dueDate.day)),
      notes: Value(notes?.trim().isEmpty == true ? null : notes?.trim()),
      createdAt: DateTime.now(),
    ));
  }

  Future<int> debtRemaining(String debtId) async {
    final debt = await (select(debts)..where((d) => d.id.equals(debtId)))
        .getSingleOrNull();
    if (debt == null) throw StateError('Data utang/piutang tidak ditemukan.');
    final paid = await (selectOnly(debtPayments)
      ..addColumns([debtPayments.amount.sum()])
      ..where(debtPayments.debtId.equals(debtId))).getSingle();
    return debt.amount - (paid.read(debtPayments.amount.sum()) ?? 0);
  }

  Future<void> addDebtPayment({
    required String debtId,
    required String accountId,
    required int amount,
  }) async {
    if (amount <= 0) throw ArgumentError('Nominal pembayaran harus lebih dari nol.');

    await transaction(() async {
      // Validate the outstanding amount inside the same transaction as the
      // payment insert, preventing concurrent payments from overpaying a debt.
      final debt = await (select(debts)..where((d) => d.id.equals(debtId)))
          .getSingleOrNull();
      if (debt == null) throw StateError('Data utang/piutang tidak ditemukan.');
      final account = await (select(accounts)..where((a) =>
        a.id.equals(accountId) & a.archived.equals(false))).getSingleOrNull();
      if (account == null) throw StateError('Rekening tidak ditemukan.');

      final paid = await (selectOnly(debtPayments)
        ..addColumns([debtPayments.amount.sum()])
        ..where(debtPayments.debtId.equals(debtId))).getSingle();
      final remaining = debt.amount - (paid.read(debtPayments.amount.sum()) ?? 0);
      if (amount > remaining) {
        throw ArgumentError('Pembayaran melebihi sisa kewajiban.');
      }

      final now = DateTime.now();
      final transactionId = _uuid.v4();
      final isReceivable = debt.direction == 'receivable';
      await into(financeTransactions).insert(FinanceTransactionsCompanion.insert(
        id: transactionId,
        type: isReceivable ? 'income' : 'expense',
        accountId: accountId,
        amount: amount,
        title: isReceivable
            ? 'Penerimaan piutang: ${debt.title}'
            : 'Pembayaran utang: ${debt.title}',
        category: Value(isReceivable ? 'Piutang' : 'Utang'),
        occurredAt: now,
        createdAt: now,
      ));
      await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
        id: _uuid.v4(),
        transactionId: transactionId,
        accountId: accountId,
        amountDelta: isReceivable ? amount : -amount,
        createdAt: now,
      ));
      await into(debtPayments).insert(DebtPaymentsCompanion.insert(
        id: _uuid.v4(),
        debtId: debtId,
        transactionId: transactionId,
        amount: amount,
        paidAt: now,
      ));
    });
  }

  Future<void> updateDebt({
    required String debtId,
    required String partyName,
    required String title,
    required int amount,
    DateTime? dueDate,
    String? notes,
  }) async {
    if (partyName.trim().isEmpty || title.trim().isEmpty || amount <= 0) {
      throw ArgumentError('Data utang/piutang tidak valid.');
    }
    final current = await (select(debts)..where((d) => d.id.equals(debtId))).getSingleOrNull();
    if (current == null) throw StateError('Data utang/piutang tidak ditemukan.');
    final paid = current.amount - await debtRemaining(debtId);
    if (amount < paid) {
      throw ArgumentError('Nominal baru tidak boleh lebih kecil dari total pembayaran yang sudah dilakukan.');
    }
    await (update(debts)..where((d) => d.id.equals(debtId))).write(
      DebtsCompanion(
        partyName: Value(partyName.trim()),
        title: Value(title.trim()),
        amount: Value(amount),
        dueDate: Value(dueDate == null ? null : DateTime(dueDate.year, dueDate.month, dueDate.day)),
        notes: Value(notes?.trim().isEmpty == true ? null : notes?.trim()),
      ),
    );
  }

  Future<void> deleteDebt(String debtId) async {
    final payments = await (select(debtPayments)
      ..where((p) => p.debtId.equals(debtId))).get();
    if (payments.isNotEmpty) {
      throw StateError('Data dengan riwayat pembayaran tidak dapat dihapus.');
    }
    await (delete(debts)..where((d) => d.id.equals(debtId))).go();
  }

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
    DateTime? repeatUntil,
  }) async {
    if (title.trim().isEmpty || category.trim().isEmpty || amount <= 0) throw ArgumentError('Data tagihan tidak valid.');
    final start = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final end = repeatUntil == null ? null : DateTime(repeatUntil.year, repeatUntil.month, repeatUntil.day);
    if (end != null && end.isBefore(start)) throw ArgumentError('Batas akhir pengulangan tidak boleh sebelum tanggal mulai.');
    if (end != null && !isMonthly) throw ArgumentError('Batas akhir hanya berlaku untuk tagihan bulanan.');
    final now = DateTime.now();
    DateTime occurrence(int year, int month, int day) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, day > lastDay ? lastDay : day);
    }
    await transaction(() async {
      var current = start;
      while (true) {
        if (end != null && current.isAfter(end)) break;
        await into(bills).insert(BillsCompanion.insert(
          id: _uuid.v4(), title: title.trim(), category: category.trim(), amount: amount,
          dueDate: current, isMonthly: Value(isMonthly), recurrenceEndDate: Value(end), createdAt: now,
        ));
        if (!isMonthly || end == null || (current.year == end.year && current.month == end.month)) break;
        current = occurrence(current.year, current.month + 1, start.day);
        if (current.isAfter(end)) break;
      }
    });
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

      if (bill.isMonthly && bill.recurrenceEndDate == null) {
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

  Future<void> updateBill({
    required String billId,
    required String title,
    required String category,
    required int amount,
    required DateTime dueDate,
  }) async {
    if (title.trim().isEmpty || category.trim().isEmpty || amount <= 0) {
      throw ArgumentError('Data tagihan tidak valid.');
    }
    final current = await (select(bills)..where((b) => b.id.equals(billId))).getSingleOrNull();
    if (current == null) throw StateError('Tagihan tidak ditemukan.');
    if (current.isPaid) throw StateError('Tagihan lunas tidak dapat diubah.');
    await (update(bills)..where((b) => b.id.equals(billId))).write(
      BillsCompanion(
        title: Value(title.trim()),
        category: Value(category.trim()),
        amount: Value(amount),
        dueDate: Value(DateTime(dueDate.year, dueDate.month, dueDate.day)),
      ),
    );
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
    'COALESCE((SELECT SUM(le.amount_delta) FROM ledger_entries le '
    'INNER JOIN accounts a ON a.id = le.account_id WHERE a.archived = 0), 0) AS total',
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



  Stream<List<RecurringTransaction>> watchRecurringTransactions() =>
      (select(recurringTransactions)
        ..orderBy([(r) => OrderingTerm.asc(r.nextDueDate)])).watch();

  Future<void> addRecurringTransaction({
    required String type,
    required String accountId,
    required int amount,
    required String title,
    String? category,
    required DateTime firstDueDate,
    DateTime? endDate,
  }) async {
    if (!['income', 'expense'].contains(type) || amount <= 0 || title.trim().isEmpty) {
      throw ArgumentError('Data transaksi berulang tidak valid.');
    }
    final account = await (select(accounts)
      ..where((a) => a.id.equals(accountId) & a.archived.equals(false)))
      .getSingleOrNull();
    if (account == null) throw StateError('Rekening tidak ditemukan.');
    final first = DateTime(firstDueDate.year, firstDueDate.month, firstDueDate.day);
    final end = endDate == null ? null : DateTime(endDate.year, endDate.month, endDate.day);
    if (end != null && end.isBefore(first)) {
      throw ArgumentError('Tanggal akhir tidak boleh sebelum tanggal mulai.');
    }
    await into(recurringTransactions).insert(RecurringTransactionsCompanion.insert(
      id: _uuid.v4(),
      type: type,
      accountId: accountId,
      amount: amount,
      title: title.trim(),
      category: Value(category?.trim().isEmpty == true ? null : category?.trim()),
      nextDueDate: first,
      dayOfMonth: first.day,
      endDate: Value(end),
      createdAt: DateTime.now(),
    ));
  }

  Future<void> updateRecurringTransaction({
    required String id,
    required String type,
    required String accountId,
    required int amount,
    required String title,
    String? category,
    required DateTime nextDueDate,
    DateTime? endDate,
  }) async {
    if (!['income', 'expense'].contains(type) || amount <= 0 || title.trim().isEmpty) {
      throw ArgumentError('Data transaksi berulang tidak valid.');
    }
    final existing = await (select(recurringTransactions)
      ..where((r) => r.id.equals(id))).getSingleOrNull();
    if (existing == null) throw StateError('Jadwal transaksi tidak ditemukan.');
    final account = await (select(accounts)
      ..where((a) => a.id.equals(accountId) & a.archived.equals(false)))
      .getSingleOrNull();
    if (account == null) throw StateError('Rekening tidak ditemukan.');
    final first = DateTime(nextDueDate.year, nextDueDate.month, nextDueDate.day);
    final end = endDate == null ? null : DateTime(endDate.year, endDate.month, endDate.day);
    if (end != null && end.isBefore(first)) {
      throw ArgumentError('Tanggal akhir tidak boleh sebelum jadwal berikutnya.');
    }
    await (update(recurringTransactions)
      ..where((r) => r.id.equals(id))).write(
        RecurringTransactionsCompanion(
          type: Value(type),
          accountId: Value(accountId),
          amount: Value(amount),
          title: Value(title.trim()),
          category: Value(category?.trim().isEmpty == true ? null : category?.trim()),
          nextDueDate: Value(first),
          dayOfMonth: Value(first.day),
          endDate: Value(end),
          isActive: const Value(true),
        ),
      );
  }

  Future<void> setRecurringTransactionActive(String id, bool active) async {
    final item = await (select(recurringTransactions)
      ..where((r) => r.id.equals(id))).getSingleOrNull();
    if (item == null) throw StateError('Jadwal transaksi tidak ditemukan.');
    await (update(recurringTransactions)..where((r) => r.id.equals(id)))
      .write(RecurringTransactionsCompanion(isActive: Value(active)));
  }

  Future<void> deleteRecurringTransaction(String id) =>
      (delete(recurringTransactions)..where((r) => r.id.equals(id))).go();

  Future<int> processDueRecurringTransactions({DateTime? throughDate}) async {
    final today = throughDate == null
        ? DateTime.now()
        : DateTime(throughDate.year, throughDate.month, throughDate.day);
    final schedules = await (select(recurringTransactions)
      ..where((r) => r.isActive.equals(true) & r.nextDueDate.isSmallerOrEqualValue(today))
      ..orderBy([(r) => OrderingTerm.asc(r.nextDueDate)])).get();
    var created = 0;

    for (final schedule in schedules) {
      await transaction(() async {
        // Re-read inside the write transaction so concurrent runs cannot
        // process the same due dates from a stale schedule snapshot.
        final current = await (select(recurringTransactions)
          ..where((r) => r.id.equals(schedule.id))).getSingleOrNull();
        if (current == null ||
            !current.isActive ||
            current.nextDueDate.isAfter(today)) {
          return;
        }

        final account = await (select(accounts)..where((a) =>
          a.id.equals(current.accountId) & a.archived.equals(false))).getSingleOrNull();
        if (account == null) {
          throw StateError('Rekening untuk jadwal "${current.title}" tidak tersedia atau diarsipkan.');
        }

        var due = current.nextDueDate;
        while (!due.isAfter(today) &&
            (current.endDate == null || !due.isAfter(current.endDate!))) {
          final transactionId = _uuid.v4();
          final delta = current.type == 'income' ? current.amount : -current.amount;
          final now = DateTime.now();
          await into(financeTransactions).insert(FinanceTransactionsCompanion.insert(
            id: transactionId,
            type: current.type,
            accountId: current.accountId,
            amount: current.amount,
            title: current.title,
            category: Value(current.category),
            occurredAt: due,
            createdAt: now,
          ));
          await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
            id: _uuid.v4(),
            transactionId: transactionId,
            accountId: current.accountId,
            amountDelta: delta,
            createdAt: now,
          ));
          created++;
          final nextMonth = DateTime(due.year, due.month + 1, 1);
          final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
          due = DateTime(nextMonth.year, nextMonth.month,
              current.dayOfMonth > lastDay ? lastDay : current.dayOfMonth);
        }

        final finished = current.endDate != null && due.isAfter(current.endDate!);
        await (update(recurringTransactions)
          ..where((r) => r.id.equals(current.id))).write(
            RecurringTransactionsCompanion(
              nextDueDate: Value(due),
              isActive: Value(!finished),
            ),
          );
      });
    }
    return created;
  }

  Stream<List<FinancialGoal>> watchFinancialGoals() =>
      (select(financialGoals)..orderBy([(g) => OrderingTerm.asc(g.targetDate)])).watch();

  Stream<List<FinanceTransaction>> watchGoalContributions(String goalId) =>
      (select(financeTransactions)
        ..where((t) => t.category.equals('goal:$goalId'))
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])).watch();

  Future<void> addGoalContribution({
    required String goalId,
    required String fromAccountId,
    required String toAccountId,
    required int amount,
    String? note,
  }) async {
    if (amount <= 0 || fromAccountId == toAccountId) {
      throw ArgumentError('Nominal dan rekening setoran tidak valid.');
    }

    await transaction(() async {
      // Re-read the goal and calculate its remaining amount within the
      // transaction so simultaneous contributions cannot exceed the target.
      final goal = await (select(financialGoals)
        ..where((g) => g.id.equals(goalId))).getSingleOrNull();
      if (goal == null) throw StateError('Target tabungan tidak ditemukan.');
      if (goal.savedAmount + amount > goal.targetAmount) {
        throw ArgumentError('Setoran melebihi sisa target tabungan.');
      }
      final from = await (select(accounts)..where((a) =>
        a.id.equals(fromAccountId) & a.archived.equals(false))).getSingleOrNull();
      final to = await (select(accounts)..where((a) =>
        a.id.equals(toAccountId) & a.archived.equals(false))).getSingleOrNull();
      if (from == null || to == null) throw StateError('Rekening tidak ditemukan.');

      final transactionId = _uuid.v4();
      final now = DateTime.now();
      final title = note?.trim().isNotEmpty == true
          ? 'Setoran ${goal.title}: ${note!.trim()}'
          : 'Setoran target: ${goal.title}';
      await into(financeTransactions).insert(FinanceTransactionsCompanion.insert(
        id: transactionId, type: 'transfer', accountId: fromAccountId,
        amount: amount, title: title, category: Value('goal:$goalId'),
        occurredAt: now, createdAt: now,
      ));
      await into(transfers).insert(TransfersCompanion.insert(
        id: _uuid.v4(), transactionId: transactionId,
        fromAccountId: fromAccountId, toAccountId: toAccountId, createdAt: now,
      ));
      await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
        id: _uuid.v4(), transactionId: transactionId,
        accountId: fromAccountId, amountDelta: -amount, createdAt: now,
      ));
      await into(ledgerEntries).insert(LedgerEntriesCompanion.insert(
        id: _uuid.v4(), transactionId: transactionId,
        accountId: toAccountId, amountDelta: amount, createdAt: now,
      ));
      await (update(financialGoals)..where((g) => g.id.equals(goalId))).write(
        FinancialGoalsCompanion(savedAmount: Value(goal.savedAmount + amount)),
      );
    });
  }


  Future<void> saveFinancialGoal({
    String? goalId,
    required String title,
    required int targetAmount,
    required int savedAmount,
    required DateTime targetDate,
  }) async {
    if (title.trim().isEmpty || targetAmount <= 0 || savedAmount < 0 || savedAmount > targetAmount) {
      throw ArgumentError('Data target tabungan tidak valid.');
    }
    final normalizedDate = DateTime(targetDate.year, targetDate.month, targetDate.day);
    if (goalId == null) {
      await into(financialGoals).insert(FinancialGoalsCompanion.insert(
        id: _uuid.v4(),
        title: title.trim(),
        targetAmount: targetAmount,
        savedAmount: Value(savedAmount),
        targetDate: normalizedDate,
        createdAt: DateTime.now(),
      ));
    } else {
      final existing = await (select(financialGoals)..where((g) => g.id.equals(goalId))).getSingleOrNull();
      if (existing == null) throw StateError('Target tabungan tidak ditemukan.');
      await (update(financialGoals)..where((g) => g.id.equals(goalId))).write(
        FinancialGoalsCompanion(
          title: Value(title.trim()),
          targetAmount: Value(targetAmount),
          savedAmount: Value(savedAmount),
          targetDate: Value(normalizedDate),
        ),
      );
    }
  }

  Future<void> deleteFinancialGoal(String goalId) async {
    final goal = await (select(financialGoals)
      ..where((g) => g.id.equals(goalId))).getSingleOrNull();
    if (goal == null) throw StateError('Target tabungan tidak ditemukan.');
    final contributions = await (select(financeTransactions)
      ..where((t) => t.category.equals('goal:$goalId'))).get();
    if (contributions.isNotEmpty) {
      throw StateError(
        'Target masih memiliki riwayat setoran. Hapus atau sesuaikan riwayat setoran terlebih dahulu.',
      );
    }
    await (delete(financialGoals)..where((g) => g.id.equals(goalId))).go();
  }

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
    String? category,
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
        title: title.trim(), category: Value(category),
        occurredAt: now, createdAt: now,
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
    final linkedDebtPayment = await (select(debtPayments)
      ..where((payment) => payment.transactionId.equals(transactionId)))
      .getSingleOrNull();
    if (linkedDebtPayment != null) {
      throw StateError('Transaksi pembayaran utang/piutang harus dikelola melalui menu utang/piutang.');
    }
    final account = await (select(accounts)..where((a) =>
      a.id.equals(accountId) & a.archived.equals(false))).getSingleOrNull();
    if (account == null) throw StateError('Rekening tidak ditemukan.');
    final delta = current.type == 'income' ? amount : -amount;
    await transaction(() async {
      final goalId = current.category?.startsWith('goal:') == true
          ? current.category!.substring(5)
          : null;
      if (goalId != null) {
        final goal = await (select(financialGoals)
          ..where((g) => g.id.equals(goalId))).getSingleOrNull();
        if (goal != null) {
          await (update(financialGoals)..where((g) => g.id.equals(goalId))).write(
            FinancialGoalsCompanion(
              savedAmount: Value((goal.savedAmount - current.amount).clamp(0, goal.targetAmount).toInt()),
            ),
          );
        }
      }
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
    final linkedDebtPayment = await (select(debtPayments)
      ..where((payment) => payment.transactionId.equals(transactionId)))
      .getSingleOrNull();
    if (linkedDebtPayment != null) {
      throw StateError('Transaksi pembayaran utang/piutang harus dikelola melalui menu utang/piutang.');
    }
    await transaction(() async {
      final goalId = current.category?.startsWith('goal:') == true
          ? current.category!.substring(5)
          : null;
      if (goalId != null) {
        final goal = await (select(financialGoals)
          ..where((g) => g.id.equals(goalId))).getSingleOrNull();
        if (goal != null) {
          await (update(financialGoals)..where((g) => g.id.equals(goalId))).write(
            FinancialGoalsCompanion(
              savedAmount: Value(
                (goal.savedAmount - current.amount).clamp(0, goal.targetAmount).toInt(),
              ),
            ),
          );
        }
      }
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
      'debts': (await select(debts).get()).map((row) => {
        'id': row.id, 'direction': row.direction,
        'partyName': row.partyName, 'title': row.title,
        'amount': row.amount, 'dueDate': row.dueDate?.toIso8601String(),
        'notes': row.notes, 'createdAt': row.createdAt.toIso8601String(),
      }).toList(),
      'financialGoals': (await select(financialGoals).get()).map((row) => {
        'id': row.id, 'title': row.title, 'targetAmount': row.targetAmount,
        'savedAmount': row.savedAmount, 'targetDate': row.targetDate.toIso8601String(),
        'createdAt': row.createdAt.toIso8601String(),
      }).toList(),
      'debtPayments': (await select(debtPayments).get()).map((row) => {
        'id': row.id, 'debtId': row.debtId,
        'transactionId': row.transactionId, 'amount': row.amount,
        'paidAt': row.paidAt.toIso8601String(),
      }).toList(),
      'recurringTransactions': (await select(recurringTransactions).get()).map((row) => {
        'id': row.id, 'type': row.type, 'accountId': row.accountId,
        'amount': row.amount, 'title': row.title, 'category': row.category,
        'nextDueDate': row.nextDueDate.toIso8601String(),
        'dayOfMonth': row.dayOfMonth, 'endDate': row.endDate?.toIso8601String(),
        'isActive': row.isActive, 'createdAt': row.createdAt.toIso8601String(),
      }).toList(),
      'bills': (await select(bills).get()).map((row) => {
        'id': row.id, 'title': row.title, 'category': row.category,
        'amount': row.amount, 'dueDate': row.dueDate.toIso8601String(),
        'isPaid': row.isPaid, 'isMonthly': row.isMonthly,
        'recurrenceEndDate': row.recurrenceEndDate?.toIso8601String(),
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
    final debtRows = decoded['debts'] is List ? rows('debts') : <Map<String, dynamic>>[];
    final debtPaymentRows = decoded['debtPayments'] is List ? rows('debtPayments') : <Map<String, dynamic>>[];
    final goalRows = decoded['financialGoals'] is List ? rows('financialGoals') : <Map<String, dynamic>>[];
    final recurringRows = decoded['recurringTransactions'] is List ? rows('recurringTransactions') : <Map<String, dynamic>>[];

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
      await delete(recurringTransactions).go();
      await delete(debtPayments).go();
      await delete(ledgerEntries).go();
      await delete(transfers).go();
      await delete(financeTransactions).go();
      await delete(debts).go();
      await delete(budgets).go();
      await delete(bills).go();
      await delete(financialGoals).go();
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
      for (final row in debtRows) {
        final dueDate = row['dueDate'];
        final notes = row['notes'];
        await into(debts).insert(DebtsCompanion.insert(
          id: string(row, 'id'),
          direction: string(row, 'direction'),
          partyName: string(row, 'partyName'),
          title: string(row, 'title'),
          amount: integer(row, 'amount'),
          dueDate: Value(dueDate is String ? DateTime.parse(dueDate) : null),
          notes: Value(notes is String ? notes : null),
          createdAt: date(row, 'createdAt'),
        ));
      }
      for (final row in goalRows) {
        await into(financialGoals).insert(FinancialGoalsCompanion.insert(
          id: string(row, 'id'), title: string(row, 'title'),
          targetAmount: integer(row, 'targetAmount'),
          savedAmount: Value(integer(row, 'savedAmount')),
          targetDate: date(row, 'targetDate'), createdAt: date(row, 'createdAt'),
        ));
      }
      for (final row in recurringRows) {
        final category = row['category'];
        final endDate = row['endDate'];
        await into(recurringTransactions).insert(RecurringTransactionsCompanion.insert(
          id: string(row, 'id'), type: string(row, 'type'),
          accountId: string(row, 'accountId'), amount: integer(row, 'amount'),
          title: string(row, 'title'), category: Value(category is String ? category : null),
          nextDueDate: date(row, 'nextDueDate'), dayOfMonth: integer(row, 'dayOfMonth'),
          endDate: Value(endDate is String ? DateTime.parse(endDate) : null),
          isActive: Value(boolean(row, 'isActive')), createdAt: date(row, 'createdAt'),
        ));
      }
      for (final row in debtPaymentRows) {
        await into(debtPayments).insert(DebtPaymentsCompanion.insert(
          id: string(row, 'id'),
          debtId: string(row, 'debtId'),
          transactionId: string(row, 'transactionId'),
          amount: integer(row, 'amount'),
          paidAt: date(row, 'paidAt'),
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
          recurrenceEndDate: Value(row['recurrenceEndDate'] is String ? DateTime.parse(row['recurrenceEndDate'] as String) : null),
          paidAt: Value(paidAt is String ? DateTime.parse(paidAt) : null),
          createdAt: date(row, 'createdAt'),
        ));
      }
    });
  }

  Future<void> closeDatabase() => close();
}
