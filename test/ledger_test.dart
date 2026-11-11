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

  test('invalid amount is rejected', () async {
    await db.addAccount('Tunai', 'Tunai', 0);
    final account = (await db.watchAccounts().first).single;

    await expectLater(
      db.addExpense(accountId: account.id, amount: 0, title: 'Invalid'),
      throwsArgumentError,
    );
  });
}
