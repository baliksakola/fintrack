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

  test('invalid amount is rejected', () async {
    await db.addAccount('Tunai', 'Tunai', 0);
    final account = (await db.watchAccounts().first).single;

    await expectLater(
      db.addExpense(accountId: account.id, amount: 0, title: 'Invalid'),
      throwsArgumentError,
    );
  });
}
