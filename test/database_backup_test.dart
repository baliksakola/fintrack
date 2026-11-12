import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.closeDatabase();
  });

  test('restoring a backup replaces existing financial goals', () async {
    await database.addAccount('Tunai', 'cash', 0);
    await database.saveFinancialGoal(
      title: 'Dana darurat',
      targetAmount: 1000000,
      savedAmount: 250000,
      targetDate: DateTime(2027, 12, 31),
    );

    final backup = await database.exportBackupJson();

    await database.saveFinancialGoal(
      title: 'Target yang tidak ada di backup',
      targetAmount: 500000,
      savedAmount: 0,
      targetDate: DateTime(2027, 6, 30),
    );

    await database.restoreBackupJson(backup);

    final goals = await database.watchFinancialGoals().first;
    expect(goals, hasLength(1));
    expect(goals.single.title, 'Dana darurat');
    expect(goals.single.savedAmount, 250000);
  });

  test('restoring the same backup twice does not duplicate financial goals', () async {
    await database.addAccount('Tunai', 'cash', 0);
    await database.saveFinancialGoal(
      title: 'Dana pendidikan',
      targetAmount: 2000000,
      savedAmount: 500000,
      targetDate: DateTime(2028, 6, 30),
    );

    final backup = await database.exportBackupJson();

    await database.restoreBackupJson(backup);
    await database.restoreBackupJson(backup);

    final goals = await database.watchFinancialGoals().first;
    expect(goals, hasLength(1));
    expect(goals.single.title, 'Dana pendidikan');
  });
  test('monthly recurring transactions catch up and clamp month-end dates', () async {
    await database.addAccount('Tunai', 'cash', 0);
    final account = (await database.watchAccounts().first).single;

    await database.addRecurringTransaction(
      type: 'expense',
      accountId: account.id,
      amount: 10000,
      title: 'Tagihan bulanan',
      firstDueDate: DateTime(2026, 10, 31),
      endDate: DateTime(2026, 12, 31),
    );

    final created = await database.processDueRecurringTransactions(
      throughDate: DateTime(2026, 12, 31),
    );

    expect(created, 3);
    final transactions = await database.watchTransactions().first;
    expect(transactions, hasLength(3));
    expect(
      transactions.map((item) => item.occurredAt.day).toSet(),
      {30, 31},
    );
    expect(await database.balanceFor(account.id), -30000);

    final schedules = await database.watchRecurringTransactions().first;
    expect(schedules, hasLength(1));
    expect(schedules.single.isActive, isFalse);
    expect(schedules.single.nextDueDate, DateTime(2027, 1, 31));
  });

  test('concurrent recurring processing does not duplicate transactions', () async {
    await database.addAccount('Tunai', 'cash', 0);
    final account = (await database.watchAccounts().first).single;

    await database.addRecurringTransaction(
      type: 'expense',
      accountId: account.id,
      amount: 15000,
      title: 'Internet',
      firstDueDate: DateTime(2026, 11, 1),
    );

    final results = await Future.wait([
      database.processDueRecurringTransactions(
        throughDate: DateTime(2026, 11, 12),
      ),
      database.processDueRecurringTransactions(
        throughDate: DateTime(2026, 11, 12),
      ),
    ]);

    expect(results.fold<int>(0, (total, count) => total + count), 1);
    expect(await database.watchTransactions().first, hasLength(1));
    expect(await database.balanceFor(account.id), -15000);
  });

  test('debt payment transactions cannot be edited or deleted directly', () async {
    await database.addAccount('Tunai', 'cash', 100000);
    final account = (await database.watchAccounts().first).single;
    await database.addDebt(
      direction: 'payable',
      partyName: 'Penyedia',
      title: 'Utang barang',
      amount: 50000,
    );
    final debt = (await database.watchDebts().first).single;

    await database.addDebtPayment(
      debtId: debt.id,
      accountId: account.id,
      amount: 20000,
    );
    final paymentTransaction =
        (await database.watchTransactions().first).single;

    expect(
      () => database.updateTransaction(
        transactionId: paymentTransaction.id,
        accountId: account.id,
        amount: 10000,
        title: 'Diubah',
      ),
      throwsStateError,
    );
    expect(
      () => database.deleteTransaction(paymentTransaction.id),
      throwsStateError,
    );

    expect(await database.debtRemaining(debt.id), 30000);
    expect(await database.balanceFor(account.id), 80000);
    expect(await database.watchTransactions().first, hasLength(1));
  });

}
