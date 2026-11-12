import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.closeDatabase();
  });

  test('financial savings goals can be created, updated and backed up', () async {
    await db.saveFinancialGoal(
      title: 'Dana Darurat',
      targetAmount: 10000000,
      savedAmount: 2500000,
      targetDate: DateTime(2027, 6, 1),
    );
    var goals = await db.watchFinancialGoals().first;
    expect(goals, hasLength(1));
    expect(goals.single.savedAmount, 2500000);

    await db.saveFinancialGoal(
      goalId: goals.single.id,
      title: 'Dana Darurat',
      targetAmount: 12000000,
      savedAmount: 3000000,
      targetDate: DateTime(2027, 8, 1),
    );
    goals = await db.watchFinancialGoals().first;
    expect(goals.single.targetAmount, 12000000);
    expect(goals.single.savedAmount, 3000000);

    final backup = await db.exportBackupJson();
    await db.deleteFinancialGoal(goals.single.id);
    await db.restoreBackupJson(backup);
    goals = await db.watchFinancialGoals().first;
    expect(goals, hasLength(1));
    expect(goals.single.title, 'Dana Darurat');
    expect(goals.single.targetAmount, 12000000);
  });

  test('goal contribution transfers funds and updates goal progress', () async {
    await db.addAccount('Operasional', 'Bank', 500000);
    await db.addAccount('Tabungan', 'Bank', 100000);
    final accounts = await db.watchAccounts().first;
    final source = accounts.firstWhere((a) => a.name == 'Operasional');
    final savings = accounts.firstWhere((a) => a.name == 'Tabungan');
    await db.saveFinancialGoal(
      title: 'Dana Darurat',
      targetAmount: 1000000,
      savedAmount: 0,
      targetDate: DateTime(2027, 6, 1),
    );
    final goal = (await db.watchFinancialGoals().first).single;

    await db.addGoalContribution(
      goalId: goal.id,
      fromAccountId: source.id,
      toAccountId: savings.id,
      amount: 250000,
      note: 'Setoran pertama',
    );

    expect(await db.balanceFor(source.id), 250000);
    expect(await db.balanceFor(savings.id), 350000);
    expect(await db.watchTotalBalance().first, 600000);
    expect((await db.watchFinancialGoals().first).single.savedAmount, 250000);
    expect((await db.watchGoalContributions(goal.id).first), hasLength(1));

    final contribution = (await db.watchGoalContributions(goal.id).first).single;
    await db.deleteTransaction(contribution.id);

    expect(await db.balanceFor(source.id), 500000);
    expect(await db.balanceFor(savings.id), 100000);
    expect((await db.watchFinancialGoals().first).single.savedAmount, 0);
    expect(await db.watchGoalContributions(goal.id).first, isEmpty);
  });

  test('goal contribution cannot exceed remaining target', () async {
    await db.addAccount('Operasional', 'Bank', 500000);
    await db.addAccount('Tabungan', 'Bank', 0);
    final accounts = await db.watchAccounts().first;
    await db.saveFinancialGoal(
      title: 'Laptop',
      targetAmount: 100000,
      savedAmount: 75000,
      targetDate: DateTime(2027, 1, 1),
    );
    final goal = (await db.watchFinancialGoals().first).single;

    await expectLater(
      db.addGoalContribution(
        goalId: goal.id,
        fromAccountId: accounts.first.id,
        toAccountId: accounts.last.id,
        amount: 30000,
      ),
      throwsArgumentError,
    );
    expect((await db.watchFinancialGoals().first).single.savedAmount, 75000);
    expect(await db.balanceFor(accounts.first.id), 500000);
  });

  test('all-account query retains archived accounts for historical reports', () async {
    await db.addAccount('Aktif', 'Bank', 100000);
    await db.addAccount('Arsip', 'Bank', 50000);
    final accounts = await db.getAllAccounts();
    final archived = accounts.singleWhere((account) => account.name == 'Arsip');

    await (db.update(db.accounts)
      ..where((account) => account.id.equals(archived.id)))
      .write(const AccountsCompanion(archived: Value(true)));

    expect(
      (await db.watchAccounts().first).map((account) => account.name),
      contains('Aktif'),
    );
    expect(
      (await db.watchAccounts().first).map((account) => account.name),
      isNot(contains('Arsip')),
    );
    expect(
      (await db.getAllAccounts()).map((account) => account.name),
      containsAll(['Aktif', 'Arsip']),
    );
  });

  test('income and expense update account balance', () async {
    await db.addAccount('BNI', 'Bank', 100000);
    final account = await db.watchAccounts().first;

    await db.addIncome(
      accountId: account.single.id,
      amount: 50000,
      title: 'Honor',
    );
    await db.addExpense(
      accountId: account.single.id,
      amount: 20000,
      title: 'Makan',
    );

    expect(await db.balanceFor(account.single.id), 130000);
  });

  test('transfer moves money without changing total balance', () async {
    await db.addAccount('BNI', 'Bank', 200000);
    await db.addAccount('ShopeePay', 'E-Wallet', 50000);
    final accounts = await db.watchAccounts().first;
    final bni = accounts.firstWhere((a) => a.name == 'BNI');
    final shopee = accounts.firstWhere((a) => a.name == 'ShopeePay');

    await db.createTransfer(
      fromAccountId: bni.id,
      toAccountId: shopee.id,
      amount: 75000,
      title: 'Top up',
    );

    expect(await db.balanceFor(bni.id), 125000);
    expect(await db.balanceFor(shopee.id), 125000);
    expect(await db.watchTotalBalance().first, 250000);
  });

  test('editing income updates ledger and account balance', () async {
    await db.addAccount('BNI', 'Bank', 100000);
    await db.addAccount('Tunai', 'Tunai', 0);
    final accounts = await db.watchAccounts().first;
    await db.addIncome(
      accountId: accounts.first.id,
      amount: 50000,
      title: 'Honor',
      category: 'Gaji',
    );
    final tx = (await db.watchTransactions().first).single;

    await db.updateTransaction(
      transactionId: tx.id,
      accountId: accounts.last.id,
      amount: 75000,
      title: 'Honor revisi',
      category: 'Bonus',
    );

    expect(await db.balanceFor(accounts.first.id), 100000);
    expect(await db.balanceFor(accounts.last.id), 75000);
    final updated = (await db.watchTransactions().first).single;
    expect(updated.title, 'Honor revisi');
    expect(updated.accountId, accounts.last.id);
    expect(updated.category, 'Bonus');
  });

  test('deleting expense restores account balance', () async {
    await db.addAccount('Tunai', 'Tunai', 100000);
    final account = (await db.watchAccounts().first).single;
    await db.addExpense(
      accountId: account.id,
      amount: 25000,
      title: 'Belanja',
    );
    final tx = (await db.watchTransactions().first).single;

    await db.deleteTransaction(tx.id);

    expect(await db.balanceFor(account.id), 100000);
    expect(await db.watchTransactions().first, isEmpty);
  });

  test('account balance stream updates after income, expense and transfer', () async {
    await db.addAccount('BNI', 'Bank', 200000);
    await db.addAccount('Tunai', 'Tunai', 50000);
    final accounts = await db.watchAccounts().first;
    final bni = accounts.firstWhere((account) => account.name == 'BNI');
    final cash = accounts.firstWhere((account) => account.name == 'Tunai');

    final balances = StreamIterator(db.watchAccountBalance(bni.id));
    expect(await balances.moveNext(), isTrue);
    expect(balances.current, 200000);

    await db.addIncome(
      accountId: bni.id,
      amount: 40000,
      title: 'Honor',
    );
    expect(await balances.moveNext(), isTrue);
    expect(balances.current, 240000);

    await db.addExpense(
      accountId: bni.id,
      amount: 10000,
      title: 'Makan',
    );
    expect(await balances.moveNext(), isTrue);
    expect(balances.current, 230000);

    await db.createTransfer(
      fromAccountId: bni.id,
      toAccountId: cash.id,
      amount: 30000,
      title: 'Tarik tunai',
    );
    expect(await balances.moveNext(), isTrue);
    expect(balances.current, 200000);
    await balances.cancel();
    expect(await db.balanceFor(bni.id), 200000);
    expect(await db.balanceFor(cash.id), 80000);
    expect(await db.watchTotalBalance().first, 280000);
  });

  test('deleting transfer removes both ledger entries', () async {
    await db.addAccount('BNI', 'Bank', 100000);
    await db.addAccount('Tunai', 'Tunai', 0);
    final accounts = await db.watchAccounts().first;
    await db.createTransfer(
      fromAccountId: accounts.first.id,
      toAccountId: accounts.last.id,
      amount: 30000,
      title: 'Pindah uang',
    );
    final tx = (await db.watchTransactions().first).single;

    await db.deleteTransaction(tx.id);

    expect(await db.balanceFor(accounts.first.id), 100000);
    expect(await db.balanceFor(accounts.last.id), 0);
    expect(await db.watchTransactions().first, isEmpty);
  });

  test('monthly budget can be created and updated', () async {
    final november = DateTime(2026, 11, 1);
    await db.saveBudget(
      category: 'Makanan',
      monthlyLimit: 1000000,
      month: november,
    );
    var budgets = await db.watchBudgetsForMonth(november).first;
    expect(budgets, hasLength(1));
    expect(budgets.single.monthlyLimit, 1000000);

    await db.saveBudget(
      category: 'Makanan',
      monthlyLimit: 1250000,
      month: DateTime(2026, 11, 20),
    );
    budgets = await db.watchBudgetsForMonth(november).first;
    expect(budgets, hasLength(1));
    expect(budgets.single.monthlyLimit, 1250000);
    expect(await db.watchBudgetsForMonth(DateTime(2026, 12)).first, isEmpty);
  });

  test('monthly budget can be deleted', () async {
    final month = DateTime(2026, 11);
    await db.saveBudget(
      category: 'Transportasi',
      monthlyLimit: 500000,
      month: month,
    );
    final budget = (await db.watchBudgetsForMonth(month).first).single;

    await db.deleteBudget(budget.id);

    expect(await db.watchBudgetsForMonth(month).first, isEmpty);
  });

  test('paying a bill records expense and creates next monthly bill', () async {
    await db.addAccount('Bank', 'Bank', 500000);
    final account = (await db.watchAccounts().first).single;
    final due = DateTime(2026, 11, 30);

    await db.addBill(
      title: 'Internet',
      category: 'Tagihan',
      amount: 150000,
      dueDate: due,
      isMonthly: true,
    );
    final bill = (await db.watchBills().first).single;

    await db.markBillPaid(
      billId: bill.id,
      accountId: account.id,
    );

    expect(await db.balanceFor(account.id), 350000);
    final transactions = await db.watchTransactions().first;
    expect(transactions, hasLength(1));
    expect(transactions.single.type, 'expense');
    expect(transactions.single.amount, 150000);
    expect(transactions.single.title, 'Pembayaran: Internet');

    final bills = await db.watchBills().first;
    expect(bills, hasLength(2));
    expect(bills.where((item) => item.isPaid), hasLength(1));
    final nextBill = bills.singleWhere((item) => !item.isPaid);
    expect(nextBill.dueDate, DateTime(2026, 12, 30));
  });

  test('monthly bill clamps due date to last day of next month', () async {
    await db.addAccount('Bank', 'Bank', 500000);
    final account = (await db.watchAccounts().first).single;
    await db.addBill(
      title: 'Internet',
      category: 'Tagihan',
      amount: 100000,
      dueDate: DateTime(2026, 1, 31),
      isMonthly: true,
    );
    final bill = (await db.watchBills().first).single;

    await db.markBillPaid(billId: bill.id, accountId: account.id);

    final next = (await db.watchBills().first)
        .singleWhere((item) => !item.isPaid);
    expect(next.dueDate, DateTime(2026, 2, 28));
  });

  test('JSON backup restores accounts transactions budgets and bills', () async {
    await db.addAccount('Bank', 'Bank', 500000);
    final account = (await db.watchAccounts().first).single;
    await db.addIncome(
      accountId: account.id,
      amount: 200000,
      title: 'Gaji',
      category: 'Gaji',
    );
    await db.saveBudget(
      category: 'Makanan',
      monthlyLimit: 1000000,
      month: DateTime(2026, 11),
    );
    await db.addBill(
      title: 'Internet',
      category: 'Tagihan',
      amount: 150000,
      dueDate: DateTime(2026, 11, 30),
      isMonthly: true,
    );

    final backup = await db.exportBackupJson();
    await db.restoreBackupJson(backup);

    final restoredAccount = (await db.watchAccounts().first).single;
    expect(restoredAccount.name, 'Bank');
    expect(await db.balanceFor(restoredAccount.id), 700000);
    expect((await db.watchTransactions().first), hasLength(1));
    expect((await db.watchBudgetsForMonth(DateTime(2026, 11)).first), hasLength(1));
    expect((await db.watchBills().first), hasLength(1));
  });

  test('invalid backup format is rejected without replacing existing data', () async {
    await db.addAccount('Cash', 'Cash', 100000);

    await expectLater(
      db.restoreBackupJson('{"format":"unknown","version":1}'),
      throwsFormatException,
    );

    expect((await db.watchAccounts().first).single.name, 'Cash');
    expect(await db.watchTotalBalance().first, 100000);
  });


  test('debt partial payments reduce remaining balance and update cash ledger', () async {
    await db.addAccount('Bank', 'Bank', 500000);
    final account = (await db.watchAccounts().first).single;
    await db.addDebt(
      direction: 'payable',
      partyName: 'Budi',
      title: 'Pinjaman',
      amount: 300000,
    );
    final debt = (await db.watchDebts().first).single;

    await db.addDebtPayment(debtId: debt.id, accountId: account.id, amount: 100000);
    expect(await db.debtRemaining(debt.id), 200000);
    expect(await db.balanceFor(account.id), 400000);

    await db.addDebtPayment(debtId: debt.id, accountId: account.id, amount: 200000);
    expect(await db.debtRemaining(debt.id), 0);
    expect(await db.balanceFor(account.id), 200000);
  });

  test('receivable payments increase account balance as income', () async {
    await db.addAccount('Bank', 'Bank', 100000);
    final account = (await db.watchAccounts().first).single;
    await db.addDebt(
      direction: 'receivable',
      partyName: 'Siti',
      title: 'Pinjaman teman',
      amount: 250000,
    );
    final debt = (await db.watchDebts().first).single;

    await db.addDebtPayment(debtId: debt.id, accountId: account.id, amount: 75000);

    expect(await db.debtRemaining(debt.id), 175000);
    expect(await db.balanceFor(account.id), 175000);
    final tx = (await db.watchTransactions().first).single;
    expect(tx.type, 'income');
    expect(tx.category, 'Piutang');
  });

  test('debt payment cannot exceed remaining amount', () async {
    await db.addAccount('Bank', 'Bank', 100000);
    final account = (await db.watchAccounts().first).single;
    await db.addDebt(
      direction: 'payable',
      partyName: 'Budi',
      title: 'Pinjaman',
      amount: 50000,
    );
    final debt = (await db.watchDebts().first).single;

    await expectLater(
      db.addDebtPayment(debtId: debt.id, accountId: account.id, amount: 60000),
      throwsArgumentError,
    );
    expect(await db.debtRemaining(debt.id), 50000);
    expect(await db.balanceFor(account.id), 100000);
  });

  test('backup restores debts and their payment history', () async {
    await db.addAccount('Bank', 'Bank', 500000);
    final account = (await db.watchAccounts().first).single;
    await db.addDebt(
      direction: 'payable',
      partyName: 'Budi',
      title: 'Pinjaman',
      amount: 300000,
    );
    final debt = (await db.watchDebts().first).single;
    await db.addDebtPayment(debtId: debt.id, accountId: account.id, amount: 50000);

    final backup = await db.exportBackupJson();
    await db.restoreBackupJson(backup);

    final restored = (await db.watchDebts().first).single;
    expect(restored.partyName, 'Budi');
    expect(await db.debtRemaining(restored.id), 250000);
    expect(await db.balanceFor(account.id), 450000);
  });


  test('recurring transactions catch up missed months exactly once', () async {
    await db.addAccount('Bank', 'Bank', 100000);
    final account = (await db.watchAccounts().first).single;
    await db.addRecurringTransaction(
      type: 'expense',
      accountId: account.id,
      amount: 10000,
      title: 'Internet',
      category: 'Tagihan',
      firstDueDate: DateTime(2026, 1, 31),
      endDate: DateTime(2026, 3, 31),
    );
    final firstRun = await db.processDueRecurringTransactions(throughDate: DateTime(2026, 4, 1));
    expect(firstRun, 3);
    expect(await db.balanceFor(account.id), 70000);
    final transactions = await db.watchTransactions().first;
    expect(transactions, hasLength(3));
    expect(transactions.map((t) => t.occurredAt).toSet(), {
      DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31),
    });
    final secondRun = await db.processDueRecurringTransactions(throughDate: DateTime(2026, 4, 1));
    expect(secondRun, 0);
    expect(await db.balanceFor(account.id), 70000);
    final schedule = (await db.watchRecurringTransactions().first).single;
    expect(schedule.isActive, isFalse);
  });

  test('recurring schedules are preserved in backup and restore', () async {
    await db.addAccount('Bank', 'Bank', 0);
    final account = (await db.watchAccounts().first).single;
    await db.addRecurringTransaction(
      type: 'income', accountId: account.id, amount: 250000,
      title: 'Gaji', category: 'Gaji', firstDueDate: DateTime(2026, 12, 1),
    );
    final backup = await db.exportBackupJson();
    await db.deleteRecurringTransaction((await db.watchRecurringTransactions().first).single.id);
    await db.restoreBackupJson(backup);
    final restored = (await db.watchRecurringTransactions().first).single;
    expect(restored.title, 'Gaji');
    expect(restored.type, 'income');
    expect(restored.amount, 250000);
    expect(restored.nextDueDate, DateTime(2026, 12, 1));
  });

  test('recurring schedule can be edited with a finite end date', () async {
    await db.addAccount('Bank', 'Bank', 100000);
    final account = (await db.watchAccounts().first).single;
    await db.addRecurringTransaction(
      type: 'expense',
      accountId: account.id,
      amount: 15000,
      title: 'Internet lama',
      firstDueDate: DateTime(2026, 12, 5),
    );
    final schedule = (await db.watchRecurringTransactions().first).single;

    await db.updateRecurringTransaction(
      id: schedule.id,
      type: 'income',
      accountId: account.id,
      amount: 500000,
      title: 'Honor',
      category: 'Gaji',
      nextDueDate: DateTime(2027, 1, 10),
      endDate: DateTime(2027, 3, 10),
    );

    final updated = (await db.watchRecurringTransactions().first).single;
    expect(updated.type, 'income');
    expect(updated.title, 'Honor');
    expect(updated.amount, 500000);
    expect(updated.nextDueDate, DateTime(2027, 1, 10));
    expect(updated.dayOfMonth, 10);
    expect(updated.endDate, DateTime(2027, 3, 10));
  });

  test('invalid amount is rejected', () async {
    await db.addAccount('Tunai', 'Tunai', 0);
    final account = (await db.watchAccounts().first).single;

    await expectLater(
      db.addExpense(accountId: account.id, amount: 0, title: 'Invalid'),
      throwsArgumentError,
    );
  });
}
