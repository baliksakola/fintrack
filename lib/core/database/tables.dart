import 'package:drift/drift.dart';

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get type => text()();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class FinanceTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // income / expense / transfer
  TextColumn get accountId => text().references(Accounts, #id)();
  IntColumn get amount => integer()();
  TextColumn get title => text()();
  TextColumn get category => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LedgerEntries extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().references(FinanceTransactions, #id)();
  TextColumn get accountId => text().references(Accounts, #id)();
  IntColumn get amountDelta => integer()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().references(FinanceTransactions, #id)();
  TextColumn get fromAccountId => text().references(Accounts, #id)();
  TextColumn get toAccountId => text().references(Accounts, #id)();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}


class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get category => text()();
  IntColumn get monthlyLimit => integer()();
  DateTimeColumn get month => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {category, month},
  ];
}


class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get category => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get dueDate => dateTime()();
  BoolColumn get isPaid => boolean().withDefault(const Constant(false))();
  BoolColumn get isMonthly => boolean().withDefault(const Constant(false))();
  DateTimeColumn get paidAt => dateTime().nullable()();
  DateTimeColumn get recurrenceEndDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}


class Debts extends Table {
  TextColumn get id => text()();
  TextColumn get direction => text()(); // payable / receivable
  TextColumn get partyName => text().withLength(min: 1, max: 100)();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  IntColumn get amount => integer()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class DebtPayments extends Table {
  TextColumn get id => text()();
  TextColumn get debtId => text().references(Debts, #id)();
  TextColumn get transactionId =>
      text().references(FinanceTransactions, #id)();
  IntColumn get amount => integer()();
  DateTimeColumn get paidAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class FinancialGoals extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  IntColumn get targetAmount => integer()();
  IntColumn get savedAmount => integer().withDefault(const Constant(0))();
  DateTimeColumn get targetDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}


class RecurringTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // income / expense
  TextColumn get accountId => text().references(Accounts, #id)();
  IntColumn get amount => integer()();
  TextColumn get title => text()();
  TextColumn get category => text().nullable()();
  DateTimeColumn get nextDueDate => dateTime()();
  IntColumn get dayOfMonth => integer()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}
