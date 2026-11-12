import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xls;
import 'package:pdf/widgets.dart' as pw;
import 'package:fintrack/core/backup/backup_crypto.dart';
import 'package:fintrack/core/notifications/bill_notification_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

const _incomeCategories = ['Gaji', 'Bonus', 'Usaha', 'Investasi', 'Hadiah', 'Lainnya'];
const _expenseCategories = ['Makanan', 'Transportasi', 'Belanja', 'Tagihan', 'Kesehatan', 'Pendidikan', 'Hiburan', 'Lainnya'];

DateTime _addMonthsClamped(DateTime date, int months) {
  final target = DateTime(date.year, date.month + months, 1);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(target.year, target.month, date.day > lastDay ? lastDay : date.day);
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;

  static const _titles = [
    'Ringkasan',
    'Aktivitas',
    'Tagihan & Rencana',
    'Laporan',
    'Lainnya',
  ];

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final pages = [
      _OverviewPage(database: db),
      _ActivityPage(database: db),
      _PlanningPage(database: db),
      _ReportsPage(database: db),
      _MorePage(database: db),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Tambah rekening',
            onPressed: () => _showAccountDialog(context, db),
            icon: const Icon(Icons.add_card),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Aktivitas',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Rencana',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Laporan',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'Lainnya',
          ),
        ],
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      StreamBuilder<int>(
        stream: database.watchTotalBalance(),
        builder: (context, snapshot) {
          final total = snapshot.data ?? 0;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total saldo', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    _rupiah.format(total),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Gabungan seluruh rekening aktif',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      Text('Aksi cepat', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.add_circle_outline,
              label: 'Pemasukan',
              onTap: () => _showTransactionDialog(context, database, 'income'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickAction(
              icon: Icons.remove_circle_outline,
              label: 'Pengeluaran',
              onTap: () => _showTransactionDialog(context, database, 'expense'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickAction(
              icon: Icons.swap_horiz,
              label: 'Transfer',
              onTap: () => _showTransferDialog(context, database),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _WeeklyCashFlowCard(database: database),
      const SizedBox(height: 12),
      _DetailedMonthlyOverview(database: database),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Text('Rekening', style: Theme.of(context).textTheme.titleMedium),
          ),
          TextButton.icon(
            onPressed: () => _showAccountDialog(context, database),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tambah'),
          ),
        ],
      ),
      _AccountsList(database: database),
      const SizedBox(height: 12),
      Text('Transaksi terbaru', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      _RecentTransactions(database: database),
    ],
  );
}


class _DetailedMonthlyOverview extends StatelessWidget {
  const _DetailedMonthlyOverview({required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final today = DateTime(now.year, now.month, now.day);
    return StreamBuilder<List<FinanceTransaction>>(
      stream: database.watchTransactions(),
      builder: (context, txSnapshot) {
        final transactions = (txSnapshot.data ?? []).where((tx) =>
          tx.type != 'transfer' && !tx.occurredAt.isBefore(start) && tx.occurredAt.isBefore(end)
        ).toList();
        var income = 0;
        var expense = 0;
        final byCategory = <String, int>{};
        for (final tx in transactions) {
          if (tx.type == 'income') {
            income += tx.amount;
          } else if (tx.type == 'expense') {
            expense += tx.amount;
            final category = tx.category?.trim().isNotEmpty == true ? tx.category! : 'Tanpa kategori';
            byCategory[category] = (byCategory[category] ?? 0) + tx.amount;
          }
        }
        final sortedCategories = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ringkasan keuangan bulanan', style: Theme.of(context).textTheme.titleLarge),
          Text(DateFormat('MMMM yyyy', 'id_ID').format(now), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _OverviewMetric(title: 'Pemasukan', value: income, color: Colors.green)),
            const SizedBox(width: 8),
            Expanded(child: _OverviewMetric(title: 'Pengeluaran', value: expense, color: Colors.red)),
          ]),
          const SizedBox(height: 8),
          Card(child: ListTile(
            title: const Text('Arus kas bersih bulan ini'),
            subtitle: const Text('Pemasukan dikurangi pengeluaran'),
            trailing: Text(_rupiah.format(income - expense), style: TextStyle(fontWeight: FontWeight.bold, color: income >= expense ? Colors.green : Colors.red)),
          )),
          const SizedBox(height: 8),
          StreamBuilder<List<Bill>>(
            stream: database.watchBills(),
            builder: (context, billSnapshot) {
              final bills = billSnapshot.data ?? <Bill>[];
              final unpaid = bills.where((b) => !b.isPaid).toList();
              final dueThisMonth = unpaid.where((b) => !b.dueDate.isBefore(start) && b.dueDate.isBefore(end)).toList();
              final overdue = unpaid.where((b) => DateTime(b.dueDate.year, b.dueDate.month, b.dueDate.day).isBefore(today)).toList();
              final totalUnpaid = unpaid.fold<int>(0, (sum, b) => sum + b.amount);
              final totalMonth = dueThisMonth.fold<int>(0, (sum, b) => sum + b.amount);
              return Card(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tagihan yang harus dibayar', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _OverviewLine(label: 'Total tagihan belum lunas', value: _rupiah.format(totalUnpaid), strong: true),
                  _OverviewLine(label: 'Tagihan jatuh tempo bulan ini', value: _rupiah.format(totalMonth)),
                  _OverviewLine(label: 'Jumlah tagihan belum lunas', value: unpaid.length.toString() + ' tagihan'),
                  _OverviewLine(label: 'Sudah melewati jatuh tempo', value: overdue.length.toString() + ' tagihan', color: overdue.isEmpty ? null : Colors.red),
                ]),
              ));
            },
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<Debt>>(
            stream: database.watchDebts(),
            builder: (context, debtSnapshot) {
              final debts = debtSnapshot.data ?? <Debt>[];
              return FutureBuilder<List<int>>(
                future: Future.wait(debts.map((d) => database.debtRemaining(d.id))),
                builder: (context, remainingSnapshot) {
                  final remaining = remainingSnapshot.data ?? debts.map((d) => d.amount).toList();
                  var payable = 0; var receivable = 0; var payableCount = 0; var receivableCount = 0;
                  for (var i = 0; i < debts.length; i++) {
                    if (debts[i].direction == 'payable') {
                      payable += remaining[i]; if (remaining[i] > 0) payableCount++;
                    } else {
                      receivable += remaining[i]; if (remaining[i] > 0) receivableCount++;
                    }
                  }
                  return Card(child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Utang & piutang tersisa', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _OverviewLine(label: 'Utang yang masih harus dibayar ($payableCount)', value: _rupiah.format(payable), color: Colors.red),
                      _OverviewLine(label: 'Piutang yang belum diterima ($receivableCount)', value: _rupiah.format(receivable), color: Colors.green),
                    ]),
                  ));
                },
              );
            },
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<Budget>>(
            stream: database.watchBudgetsForMonth(now),
            builder: (context, budgetSnapshot) {
              final budgets = budgetSnapshot.data ?? <Budget>[];
              final totalLimit = budgets.fold<int>(0, (sum, b) => sum + b.monthlyLimit);
              final spentForBudget = budgets.fold<int>(0, (sum, b) => sum + (byCategory[b.category] ?? 0));
              return Card(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Anggaran bulan ini', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _OverviewLine(label: 'Total batas anggaran', value: _rupiah.format(totalLimit)),
                  _OverviewLine(label: 'Pengeluaran kategori beranggaran', value: _rupiah.format(spentForBudget)),
                  _OverviewLine(label: 'Sisa anggaran', value: _rupiah.format(totalLimit - spentForBudget), color: spentForBudget > totalLimit ? Colors.red : Colors.green),
                  if (budgets.isEmpty) const Text('Belum ada anggaran yang dibuat.', style: TextStyle(fontSize: 12)),
                ]),
              ));
            },
          ),
          const SizedBox(height: 8),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pengeluaran per kategori', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (sortedCategories.isEmpty) const Text('Belum ada pengeluaran bulan ini.')
              else ...sortedCategories.map((entry) => _OverviewCategoryLine(label: entry.key, amount: entry.value, total: expense)),
            ]),
          )),
        ]);
      },
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.title, required this.value, required this.color});
  final String title; final int value; final Color color;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 5),
      Text(_rupiah.format(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
    ]),
  ));
}

class _OverviewLine extends StatelessWidget {
  const _OverviewLine({required this.label, required this.value, this.color, this.strong = false});
  final String label; final String value; final Color? color; final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.bold : null))),
      const SizedBox(width: 8),
      Text(value, textAlign: TextAlign.end, style: TextStyle(fontWeight: strong ? FontWeight.bold : null, color: color)),
    ]),
  );
}

class _OverviewCategoryLine extends StatelessWidget {
  const _OverviewCategoryLine({required this.label, required this.amount, required this.total});
  final String label; final int amount; final int total;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label)),
        Text(_rupiah.format(amount), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text(total == 0 ? '0%' : (amount * 100 / total).round().toString() + '%', style: Theme.of(context).textTheme.bodySmall),
      ]),
      const SizedBox(height: 4),
      LinearProgressIndicator(value: total == 0 ? 0 : (amount / total).clamp(0.0, 1.0)),
    ]),
  );
}

class _WeeklyCashFlowCard extends StatelessWidget {
  const _WeeklyCashFlowCard({required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<FinanceTransaction>>(
    stream: database.watchTransactions(),
    builder: (context, snapshot) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final days = List.generate(7, (index) => today.subtract(Duration(days: 6 - index)));
      final income = List<int>.filled(7, 0);
      final expense = List<int>.filled(7, 0);

      for (final tx in snapshot.data ?? <FinanceTransaction>[]) {
        final date = DateTime(tx.occurredAt.year, tx.occurredAt.month, tx.occurredAt.day);
        final index = date.difference(days.first).inDays;
        if (index < 0 || index >= 7) continue;
        if (tx.type == 'income') income[index] += tx.amount;
        if (tx.type == 'expense') expense[index] += tx.amount;
      }

      final totalIncome = income.fold<int>(0, (sum, value) => sum + value);
      final totalExpense = expense.fold<int>(0, (sum, value) => sum + value);
      final maxValue = [...income, ...expense].fold<int>(
        0,
        (current, value) => value > current ? value : current,
      );
      final maxBar = maxValue == 0 ? 1 : maxValue.toDouble();
      final colors = Theme.of(context).colorScheme;

      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Arus kas 7 hari', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _CashFlowTotal(
                      label: 'Pemasukan',
                      amount: totalIncome,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CashFlowTotal(
                      label: 'Pengeluaran',
                      amount: totalExpense,
                      color: colors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 104,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (index) {
                    final incomeHeight = income[index] / maxBar * 66;
                    final expenseHeight = expense[index] / maxBar * 66;
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _CashFlowBar(
                                  height: incomeHeight,
                                  color: Colors.green.shade600,
                                ),
                                const SizedBox(width: 3),
                                _CashFlowBar(
                                  height: expenseHeight,
                                  color: colors.error,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            DateFormat('EEEEE', 'id_ID').format(days[index]),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CashFlowLegend(color: Colors.green.shade600, label: 'Masuk'),
                  const SizedBox(width: 18),
                  _CashFlowLegend(color: colors.error, label: 'Keluar'),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CashFlowTotal extends StatelessWidget {
  const _CashFlowTotal({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 3),
      Text(
        _rupiah.format(amount),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

class _CashFlowBar extends StatelessWidget {
  const _CashFlowBar({required this.height, required this.color});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: height.clamp(2.0, 66.0),
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    ),
  );
}

class _CashFlowLegend extends StatelessWidget {
  const _CashFlowLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [TransactionHistorySection(database: database)],
  );
}

class _PlanningPage extends StatelessWidget {
  const _PlanningPage({required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      BillsSection(database: database),
      const SizedBox(height: 20),
      DebtSection(database: database),
      const SizedBox(height: 20),
      BudgetSection(database: database),
    ],
  );
}

class _ReportsPage extends StatelessWidget {
  const _ReportsPage({required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [FinanceReportsSection(database: database)],
  );
}

class _MorePage extends StatelessWidget {
  const _MorePage({required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Pengelolaan data', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      BackupSection(database: database),
    ],
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Column(
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    ),
  );
}

class _AccountsList extends StatelessWidget {
  const _AccountsList({required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Account>>(
    stream: database.watchAccounts(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Card(child: ListTile(title: Text('Rekening gagal dimuat.')));
      }
      final accounts = snapshot.data ?? [];
      if (accounts.isEmpty) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Belum ada rekening. Tambahkan rekening pertama.'),
          ),
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 520 ? 3 : 2;
          final ratio = columns == 2 ? 1.65 : 1.8;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: accounts.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: ratio,
            ),
            itemBuilder: (context, index) {
              final account = accounts[index];
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            account.type == 'Tunai'
                                ? Icons.payments_outlined
                                : account.type == 'E-Wallet'
                                    ? Icons.account_balance_wallet_outlined
                                    : Icons.account_balance_outlined,
                            size: 19,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              account.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
                      FutureBuilder<int>(
                        future: database.balanceFor(account.id),
                        builder: (context, balance) => Text(
                          _rupiah.format(balance.data ?? account.openingBalance),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        account.type,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions({required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<FinanceTransaction>>(
    stream: database.watchTransactions(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Card(child: ListTile(title: Text('Transaksi gagal dimuat.')));
      }
      final items = (snapshot.data ?? []).take(5).toList();
      if (items.isEmpty) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Belum ada transaksi.'),
          ),
        );
      }
      return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  indent: 64,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              Builder(
                builder: (context) {
                  final tx = items[index];
                  final isIncome = tx.type == 'income';
                  final isTransfer = tx.type == 'transfer';
                  final amountColor = isIncome
                      ? Colors.green.shade700
                      : isTransfer
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.error;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    leading: CircleAvatar(
                      radius: 18,
                      child: Icon(
                        isTransfer
                            ? Icons.swap_horiz
                            : isIncome ? Icons.south_west : Icons.north_east,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      tx.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      DateFormat('dd MMM yyyy', 'id_ID').format(tx.occurredAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Text(
                      '${isIncome ? '+' : isTransfer ? '' : '-'}${_rupiah.format(tx.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: amountColor,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      );
    },
  );
}

Future<void> _showAccountDialog(BuildContext context, AppDatabase db) async {
  final name = TextEditingController();
  final balance = TextEditingController(text: '0');
  String type = 'Bank';
  await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
    builder: (context, setState) => AlertDialog(
      title: const Text('Tambah rekening'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama rekening')),
        TextField(controller: balance, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Saldo awal (Rp)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: type,
          items: const ['Bank', 'E-Wallet', 'Tunai', 'Tabungan', 'Lainnya']
            .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => type = v ?? 'Bank'),
          decoration: const InputDecoration(labelText: 'Jenis rekening'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
        FilledButton(onPressed: () async {
          final amount = int.tryParse(balance.text.replaceAll('.', '').replaceAll(',', '')) ?? -1;
          try {
            await db.addAccount(name.text, type, amount);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text(e.toString())),
              );
            }
          }
        }, child: const Text('Simpan')),
      ],
    ),
  ));
}

Future<void> _showTransactionDialog(BuildContext context, AppDatabase db, String type) async {
  final accounts = await db.watchAccounts().first;
  if (!context.mounted) return;
  if (accounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tambahkan rekening terlebih dahulu.')));
    return;
  }
  final title = TextEditingController();
  final amount = TextEditingController();
  String accountId = accounts.first.id;
  final categories = type == 'income' ? _incomeCategories : _expenseCategories;
  String category = categories.first;
  await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
    builder: (context, setState) => AlertDialog(
      title: Text(type == 'income' ? 'Catat pemasukan' : 'Catat pengeluaran'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Keterangan')),
        TextField(controller: amount, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Nominal (Rp)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: accountId,
          items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
          onChanged: (v) => setState(() => accountId = v ?? accounts.first.id),
          decoration: const InputDecoration(labelText: 'Rekening'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: category,
          items: categories.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
          onChanged: (value) => setState(() => category = value ?? categories.first),
          decoration: const InputDecoration(labelText: 'Kategori'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
        FilledButton(onPressed: () async {
          final value = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
          try {
            if (type == 'income') {
              await db.addIncome(accountId: accountId, amount: value, title: title.text, category: category);
            } else {
              await db.addExpense(accountId: accountId, amount: value, title: title.text, category: category);
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text(e.toString())),
              );
            }
          }
        }, child: const Text('Simpan')),
      ],
    ),
  ));
}

Future<void> _showTransferDialog(BuildContext context, AppDatabase db) async {
  final accounts = await db.watchAccounts().first;
  if (!context.mounted) return;
  if (accounts.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Minimal dua rekening diperlukan untuk transfer.')));
    return;
  }
  final title = TextEditingController(text: 'Transfer antar rekening');
  final amount = TextEditingController();
  String fromId = accounts.first.id;
  String toId = accounts[1].id;
  await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
    builder: (context, setState) => AlertDialog(
      title: const Text('Transfer antar rekening'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Keterangan')),
        TextField(controller: amount, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Nominal (Rp)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: fromId,
          items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('Dari: ${a.name}'))).toList(),
          onChanged: (v) => setState(() { fromId = v ?? fromId; if (fromId == toId) {
            toId = accounts.firstWhere((a) => a.id != fromId).id;
          } }),
        ),
        DropdownButtonFormField<String>(
          initialValue: toId,
          items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('Ke: ${a.name}'))).toList(),
          onChanged: (v) => setState(() => toId = v ?? toId),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
        FilledButton(onPressed: () async {
          final value = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
          try {
            await db.createTransfer(fromAccountId: fromId, toAccountId: toId, amount: value, title: title.text);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(content: Text(e.toString())),
              );
            }
          }
        }, child: const Text('Transfer')),
      ],
    ),
  ));
}
 
Future<void> _showEditTransactionDialog(
  BuildContext context,
  AppDatabase db,
  FinanceTransaction transaction,
) async {
  final accounts = await db.watchAccounts().first;
  if (!context.mounted || accounts.isEmpty) return;
  final title = TextEditingController(text: transaction.title);
  final amount = TextEditingController(text: transaction.amount.toString());
  String accountId = accounts.any((a) => a.id == transaction.accountId)
      ? transaction.accountId
      : accounts.first.id;
  final categories = transaction.type == 'income' ? _incomeCategories : _expenseCategories;
  String category = categories.contains(transaction.category) ? transaction.category! : categories.first;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(transaction.type == 'income' ? 'Edit pemasukan' : 'Edit pengeluaran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Keterangan'),
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: accountId,
              items: accounts.map((a) => DropdownMenuItem(
                value: a.id,
                child: Text(a.name),
              )).toList(),
              onChanged: (value) => setState(() => accountId = value ?? accountId),
              decoration: const InputDecoration(labelText: 'Rekening'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: category,
              items: categories.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
              onChanged: (value) => setState(() => category = value ?? category),
              decoration: const InputDecoration(labelText: 'Kategori'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final value = int.tryParse(
                amount.text.replaceAll('.', '').replaceAll(',', ''),
              ) ?? 0;
              try {
                await db.updateTransaction(
                  transactionId: transaction.id,
                  accountId: accountId,
                  amount: value,
                  title: title.text,
                  category: category,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            child: const Text('Simpan perubahan'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmDeleteTransaction(
  BuildContext context,
  AppDatabase db,
  FinanceTransaction transaction,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Hapus transaksi?'),
      content: Text('Transaksi "${transaction.title}" akan dihapus dan saldo rekening akan disesuaikan.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await db.deleteTransaction(transaction.id);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

class TransactionHistorySection extends StatefulWidget {
  const TransactionHistorySection({super.key, required this.database});

  final AppDatabase database;

  @override
  State<TransactionHistorySection> createState() => _TransactionHistorySectionState();
}

class _TransactionHistorySectionState extends State<TransactionHistorySection> {
  final _searchController = TextEditingController();
  String _typeFilter = 'Semua';
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Riwayat transaksi', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Cari keterangan atau kategori',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Hapus pencarian',
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              icon: const Icon(Icons.close),
            ),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _typeFilter,
          decoration: const InputDecoration(
            labelText: 'Filter jenis transaksi',
            border: OutlineInputBorder(),
          ),
          items: const ['Semua', 'Pemasukan', 'Pengeluaran', 'Transfer']
              .map((value) => DropdownMenuItem(value: value, child: Text(value)))
              .toList(),
          onChanged: (value) => setState(() => _typeFilter = value ?? 'Semua'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                _dateRange == null
                    ? 'Pilih tanggal'
                    : '${DateFormat('dd MMM', 'id_ID').format(_dateRange!.start)} – ${DateFormat('dd MMM yyyy', 'id_ID').format(_dateRange!.end)}',
              ),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(now.year + 5, 12, 31),
                  initialDateRange: _dateRange,
                  helpText: 'Pilih rentang tanggal transaksi',
                  saveText: 'Terapkan',
                  cancelText: 'Batal',
                  builder: (context, child) => child!,
                );
                if (picked != null && mounted) {
                  setState(() => _dateRange = DateTimeRange(
                    start: DateTime(picked.start.year, picked.start.month, picked.start.day),
                    end: DateTime(picked.end.year, picked.end.month, picked.end.day),
                  ));
                }
              },
            ),
            if (_dateRange != null)
              TextButton.icon(
                onPressed: () => setState(() => _dateRange = null),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Hapus tanggal'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<FinanceTransaction>>(
          stream: widget.database.watchTransactions(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Gagal memuat riwayat transaksi.');
            }
            final query = _searchController.text.trim().toLowerCase();
            final type = switch (_typeFilter) {
              'Pemasukan' => 'income',
              'Pengeluaran' => 'expense',
              'Transfer' => 'transfer',
              _ => null,
            };
            final items = (snapshot.data ?? []).where((tx) {
              final matchesType = type == null || tx.type == type;
              final matchesSearch = query.isEmpty ||
                  tx.title.toLowerCase().contains(query) ||
                  (tx.category ?? '').toLowerCase().contains(query);
              final matchesDate = _dateRange == null ||
                  (!tx.occurredAt.isBefore(_dateRange!.start) &&
                   tx.occurredAt.isBefore(_dateRange!.end.add(const Duration(days: 1))));
              return matchesType && matchesSearch && matchesDate;
            }).toList();

            if (items.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Tidak ada transaksi yang cocok dengan filter.'),
                ),
              );
            }
            return Column(
              children: items.map((tx) {
                final income = tx.type == 'income';
                final transfer = tx.type == 'transfer';
                final date = DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(tx.occurredAt);
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(transfer ? Icons.swap_horiz : income ? Icons.south_west : Icons.north_east),
                    ),
                    title: Text(tx.title),
                    subtitle: Text(tx.category == null || tx.category!.isEmpty
                        ? date
                        : '$date • ${tx.category}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${income ? '+' : transfer ? '' : '-'}${_rupiah.format(tx.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: income ? Colors.green : transfer ? null : Colors.red,
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Aksi transaksi',
                          onSelected: (action) {
                            if (action == 'edit' && !transfer) {
                              _showEditTransactionDialog(context, widget.database, tx);
                            } else if (action == 'delete') {
                              _confirmDeleteTransaction(context, widget.database, tx);
                            }
                          },
                          itemBuilder: (context) => [
                            if (!transfer)
                              const PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('Edit'),
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.delete_outline),
                                title: Text('Hapus'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}








class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.database});

  final AppDatabase database;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  bool _busy = false;

  Future<String?> _askPassword({required bool confirm}) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(confirm ? 'Buat kata sandi backup' : 'Kata sandi backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Kata sandi (minimal 10 karakter)',
              ),
            ),
            if (confirm) TextField(
              controller: confirmation,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Ulangi kata sandi'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (password.text.length < 10 ||
                  (confirm && password.text != confirmation.text)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(password.text.length < 10
                      ? 'Kata sandi minimal 10 karakter.'
                      : 'Konfirmasi kata sandi tidak sama.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, password.text);
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    password.dispose();
    confirmation.dispose();
    return result;
  }

  Future<void> _exportBackup() async {
    final password = await _askPassword(confirm: true);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final json = await widget.database.exportBackupJson();
      final encrypted = await BackupCrypto.encrypt(
        plaintext: json,
        password: password,
      );
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan backup FinTrack terenkripsi',
        fileName: 'fintrack_backup_$stamp.ftbackup',
        type: FileType.custom,
        allowedExtensions: ['ftbackup'],
        bytes: Uint8List.fromList(utf8.encode(encrypted)),
      );
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup terenkripsi berhasil disimpan.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat backup: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pulihkan backup?'),
        content: const Text(
          'Pemulihan akan mengganti seluruh data FinTrack saat ini. '
          'Buat backup terbaru sebelum melanjutkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Pilih file backup'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final password = await _askPassword(confirm: false);
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Pilih backup FinTrack terenkripsi',
        type: FileType.custom,
        allowedExtensions: ['ftbackup'],
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return;
      final encrypted = utf8.decode(result.files.single.bytes!);
      final source = await BackupCrypto.decrypt(
        encrypted: encrypted,
        password: password,
      );
      await widget.database.restoreBackupJson(source);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup berhasil dipulihkan.')),
      );
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup tidak dapat dibuka: $e')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memulihkan backup: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Backup & restore', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'Simpan salinan rekening, transaksi, anggaran, dan tagihan. '
        'File backup dienkripsi dengan kata sandi sebelum disimpan dan dapat dipindahkan ke perangkat lain.',
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _exportBackup,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Buat backup'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importBackup,
            icon: const Icon(Icons.restore),
            label: const Text('Pulihkan backup'),
          ),
        ],
      ),
      if (_busy) const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(),
      ),
    ],
  );
}


class DebtSection extends StatefulWidget {
  const DebtSection({super.key, required this.database});

  final AppDatabase database;

  @override
  State<DebtSection> createState() => _DebtSectionState();
}

class _DebtSectionState extends State<DebtSection> {
  Future<void> _addDebt(String direction) async {
    final party = TextEditingController();
    final title = TextEditingController();
    final amount = TextEditingController();
    final notes = TextEditingController();
    DateTime? dueDate;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(direction == 'payable' ? 'Catat utang' : 'Catat piutang'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: party,
                decoration: InputDecoration(
                  labelText: direction == 'payable' ? 'Nama pemberi pinjaman' : 'Nama peminjam',
                ),
              ),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Keterangan')),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total nominal (Rp)'),
              ),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Jatuh tempo (opsional)'),
                subtitle: Text(dueDate == null
                    ? 'Belum ditentukan'
                    : DateFormat('dd MMMM yyyy', 'id_ID').format(dueDate!)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: dueDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setDialogState(() => dueDate = picked);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final value = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
                try {
                  await widget.database.addDebt(
                    direction: direction,
                    partyName: party.text,
                    title: title.text,
                    amount: value,
                    dueDate: dueDate,
                    notes: notes.text,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    party.dispose();
    title.dispose();
    amount.dispose();
    notes.dispose();
  }

  Future<void> _editDebt(Debt debt) async {
    final party = TextEditingController(text: debt.partyName);
    final title = TextEditingController(text: debt.title);
    final amount = TextEditingController(text: debt.amount.toString());
    final notes = TextEditingController(text: debt.notes ?? '');
    DateTime? dueDate = debt.dueDate;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(debt.direction == 'payable' ? 'Edit utang' : 'Edit piutang'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: party, decoration: const InputDecoration(labelText: 'Nama pihak terkait')),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Keterangan')),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total nominal (Rp)')),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Catatan')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Jatuh tempo'),
              subtitle: Text(dueDate == null ? 'Belum ditentukan' : DateFormat('dd MMM yyyy', 'id_ID').format(dueDate!)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(context: dialogContext, initialDate: dueDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (picked != null) setDialogState(() => dueDate = picked);
              },
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
            FilledButton(onPressed: () async {
              final value = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
              try {
                await widget.database.updateDebt(debtId: debt.id, partyName: party.text, title: title.text, amount: value, dueDate: dueDate, notes: notes.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            }, child: const Text('Simpan perubahan')),
          ],
        ),
      ),
    );
    party.dispose(); title.dispose(); amount.dispose(); notes.dispose();
  }

  Future<void> _deleteDebt(Debt debt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus rencana?'),
        content: Text('Data "' + debt.title + '" akan dihapus. Data dengan riwayat pembayaran tidak dapat dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.database.deleteDebt(debt.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _payDebt(Debt debt, int remaining) async {
    final accounts = await widget.database.watchAccounts().first;
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan rekening terlebih dahulu.')),
      );
      return;
    }
    final amount = TextEditingController(text: remaining.toString());
    String accountId = accounts.first.id;
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(debt.direction == 'payable' ? 'Bayar utang' : 'Terima pembayaran piutang'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Sisa: ${_rupiah.format(remaining)}'),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nominal pembayaran (Rp)'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: accountId,
              decoration: const InputDecoration(labelText: 'Rekening'),
              items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
              onChanged: (v) => setDialogState(() => accountId = v ?? accountId),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
                Navigator.pop(dialogContext, parsed);
              },
              child: const Text('Simpan pembayaran'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    if (value == null || value <= 0) return;
    try {
      await widget.database.addDebtPayment(
        debtId: debt.id,
        accountId: accountId,
        amount: value,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text('Utang & piutang', style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(
            tooltip: 'Tambah utang',
            onPressed: () => _addDebt('payable'),
            icon: const Icon(Icons.call_made),
          ),
          IconButton(
            tooltip: 'Tambah piutang',
            onPressed: () => _addDebt('receivable'),
            icon: const Icon(Icons.call_received),
          ),
        ],
      ),
      StreamBuilder<List<Debt>>(
        stream: widget.database.watchDebts(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('Data utang/piutang tidak dapat dimuat.');
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Belum ada catatan utang atau piutang.'),
              ),
            );
          }
          return Column(
            children: items.map((debt) => FutureBuilder<int>(
              future: widget.database.debtRemaining(debt.id),
              builder: (context, balance) {
                final remaining = balance.data ?? debt.amount;
                final paid = remaining == 0;
                final overdue = debt.dueDate != null &&
                    DateTime(debt.dueDate!.year, debt.dueDate!.month, debt.dueDate!.day)
                        .isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)) &&
                    !paid;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(debt.direction == 'payable' ? Icons.call_made : Icons.call_received),
                    ),
                    title: Text(debt.title),
                    subtitle: Text(
                      '${debt.partyName} • ${debt.direction == 'payable' ? 'Utang' : 'Piutang'}'
                      '${debt.dueDate == null ? '' : ' • Jatuh tempo ${DateFormat('dd MMM yyyy', 'id_ID').format(debt.dueDate!)}'}'
                      '${overdue ? ' • TERLAMBAT' : ''}'
                      '\nTotal ${_rupiah.format(debt.amount)} • Sisa ${_rupiah.format(remaining)}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') _editDebt(debt);
                        if (action == 'delete') _deleteDebt(debt);
                        if (action == 'pay' && !paid) _payDebt(debt, remaining);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                        const PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('Hapus'))),
                        if (!paid) const PopupMenuItem(value: 'pay', child: ListTile(dense: true, leading: Icon(Icons.payments_outlined), title: Text('Bayar'))),
                      ],
                    ),
                  ),
                );
              },
            )).toList(),
          );
        },
      ),
    ],
  );
}

class BillsSection extends StatefulWidget {
  const BillsSection({super.key, required this.database});

  final AppDatabase database;

  @override
  State<BillsSection> createState() => _BillsSectionState();
}

class _BillsSectionState extends State<BillsSection> {
  bool _remindersEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadReminderState();
  }

  Future<void> _loadReminderState() async {
    try {
      final enabled = await BillNotificationService.instance.hasPermission();
      if (!mounted) return;
      setState(() => _remindersEnabled = enabled);
      if (enabled) await _refreshReminders();
    } catch (_) {
      // Reminder setup should not prevent bill management from working.
    }
  }

  Future<void> _refreshReminders() async {
    final bills = await widget.database.watchBills().first;
    await BillNotificationService.instance.syncBills(bills);
  }

  Future<void> _enableReminders() async {
    try {
      final granted = await BillNotificationService.instance.requestPermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Izin notifikasi belum diberikan. Aktifkan melalui pengaturan aplikasi Android.',
          )),
        );
        return;
      }
      setState(() => _remindersEnabled = true);
      await _refreshReminders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Pengingat tagihan aktif: satu hari sebelum dan pada hari jatuh tempo.',
        )),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengaktifkan pengingat: $e')),
        );
      }
    }
  }

  Future<void> _addBill() async {
    final title = TextEditingController();
    final amount = TextEditingController();
    String category = _expenseCategories.first;
    bool monthly = true;
    bool limited = true;
    DateTime dueDate = DateTime.now();
    DateTime repeatUntil = _addMonthsClamped(dueDate, 5);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tambah tagihan'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Nama tagihan')),
              TextField(controller: amount, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nominal (Rp)')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: category, decoration: const InputDecoration(labelText: 'Kategori'),
                items: _expenseCategories.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                onChanged: (value) => setDialogState(() => category = value ?? category),
              ),
              const SizedBox(height: 8),
              ListTile(contentPadding: EdgeInsets.zero, title: const Text('Tanggal mulai'),
                subtitle: Text(DateFormat('dd MMMM yyyy', 'id_ID').format(dueDate)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final picked = await showDatePicker(context: dialogContext, initialDate: dueDate,
                    firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (picked != null) {
                    setDialogState(() {
                      dueDate = picked;
                      if (repeatUntil.isBefore(dueDate)) {
                        repeatUntil = _addMonthsClamped(dueDate, 5);
                      }
                    });
                  }
                }),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: monthly,
                title: const Text('Ulangi setiap bulan'),
                onChanged: (value) => setDialogState(() => monthly = value)),
              if (monthly) ...[
                CheckboxListTile(contentPadding: EdgeInsets.zero, value: limited,
                  title: const Text('Tentukan batas akhir'), subtitle: const Text('Contoh: 6 atau 12 bulan'),
                  onChanged: (value) => setDialogState(() => limited = value ?? true)),
                if (limited)
                  ListTile(contentPadding: EdgeInsets.zero, title: const Text('Berulang sampai tanggal'),
                    subtitle: Text(DateFormat('dd MMMM yyyy', 'id_ID').format(repeatUntil)),
                    trailing: const Icon(Icons.event),
                    onTap: () async {
                      final picked = await showDatePicker(context: dialogContext,
                        initialDate: repeatUntil.isBefore(dueDate) ? dueDate : repeatUntil,
                        firstDate: dueDate, lastDate: DateTime(2100));
                      if (picked != null) setDialogState(() => repeatUntil = picked);
                    }),
              ],
              if (monthly && limited)
                Align(alignment: Alignment.centerLeft, child: Text(
                  'Jadwal: ${DateFormat('MMM yyyy', 'id_ID').format(dueDate)} – ${DateFormat('MMM yyyy', 'id_ID').format(repeatUntil)}',
                  style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
            FilledButton(onPressed: () async {
              final value = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
              try {
                await widget.database.addBill(title: title.text, category: category, amount: value,
                  dueDate: dueDate, isMonthly: monthly, repeatUntil: monthly && limited ? repeatUntil : null);
                await _refreshReminders();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            }, child: const Text('Simpan tagihan')),
          ],
        ),
      ),
    );
    title.dispose();
    amount.dispose();
  }

  Future<void> _editBill(Bill bill) async {
    final title = TextEditingController(text: bill.title);
    final amount = TextEditingController(text: bill.amount.toString());
    String category = bill.category;
    DateTime dueDate = bill.dueDate;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit tagihan'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Nama tagihan')),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nominal (Rp)')),
            DropdownButtonFormField<String>(
              initialValue: _expenseCategories.contains(category) ? category : _expenseCategories.first,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: _expenseCategories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setDialogState(() => category = v ?? category),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tanggal jatuh tempo'),
              subtitle: Text(DateFormat('dd MMMM yyyy', 'id_ID').format(dueDate)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(context: dialogContext, initialDate: dueDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (picked != null) setDialogState(() => dueDate = picked);
              },
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
            FilledButton(onPressed: () async {
              final value = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
              try {
                await widget.database.updateBill(billId: bill.id, title: title.text, category: category, amount: value, dueDate: dueDate);
                await _refreshReminders();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            }, child: const Text('Simpan perubahan')),
          ],
        ),
      ),
    );
    title.dispose(); amount.dispose();
  }

  Future<void> _deleteBill(Bill bill) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus tagihan?'),
        content: Text('Tagihan "' + bill.title + '" akan dihapus dari daftar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.database.deleteBill(bill.id);
    await _refreshReminders();
  }

  Future<void> _payBill(Bill bill) async {
    final accounts = await widget.database.watchAccounts().first;
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan rekening sebelum membayar tagihan.')),
      );
      return;
    }
    String accountId = accounts.first.id;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bayar tagihan'),
          content: DropdownButtonFormField<String>(
            initialValue: accountId,
            decoration: const InputDecoration(labelText: 'Bayar menggunakan rekening'),
            items: accounts.map((account) => DropdownMenuItem(
              value: account.id,
              child: Text(account.name),
            )).toList(),
            onChanged: (value) => setDialogState(
              () => accountId = value ?? accountId,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, accountId),
              child: const Text('Konfirmasi pembayaran'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    try {
      await widget.database.markBillPaid(
        billId: bill.id,
        accountId: selected,
      );
      await _refreshReminders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Tagihan & jatuh tempo',
                style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              tooltip: _remindersEnabled ? 'Pengingat aktif' : 'Aktifkan pengingat',
              onPressed: _remindersEnabled ? null : _enableReminders,
              icon: Icon(
                _remindersEnabled ? Icons.notifications_active : Icons.notifications_none,
              ),
            ),
            IconButton(
              tooltip: 'Tambah tagihan',
              onPressed: _addBill,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        StreamBuilder<List<Bill>>(
          stream: widget.database.watchBills(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Tagihan tidak dapat dimuat.');
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Belum ada tagihan. Tambahkan listrik, internet, cicilan, atau tagihan rutin lainnya.'),
                ),
              );
            }
            final unpaid = items.where((bill) => !bill.isPaid).toList();
            final paid = items.where((bill) => bill.isPaid).toList();
            return Column(
              children: [
                if (unpaid.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Tidak ada tagihan yang menunggu pembayaran.'),
                    ),
                  ),
                ...unpaid.map((bill) {
                  final due = DateTime(
                    bill.dueDate.year, bill.dueDate.month, bill.dueDate.day,
                  );
                  final days = due.difference(todayDate).inDays;
                  final overdue = days < 0;
                  final nearDue = days >= 0 && days <= 3;
                  final color = overdue ? Colors.red : nearDue ? Colors.orange : Colors.green;
                  final status = overdue
                      ? 'Terlambat ${days.abs()} hari'
                      : days == 0
                          ? 'Jatuh tempo hari ini'
                          : 'Jatuh tempo $days hari lagi';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(
                          overdue ? Icons.warning_amber_rounded : Icons.receipt_long,
                          color: color,
                        ),
                      ),
                      title: Text(bill.title),
                      subtitle: Text(
                        '${bill.category} • ${DateFormat('dd MMM yyyy', 'id_ID').format(bill.dueDate)}\n$status${bill.isMonthly ? ' • Bulanan' : ''}',
                        style: TextStyle(color: color),
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') _editBill(bill);
                          if (action == 'delete') _deleteBill(bill);
                          if (action == 'pay') _payBill(bill);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                          const PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('Hapus'))),
                          const PopupMenuItem(value: 'pay', child: ListTile(dense: true, leading: Icon(Icons.payments_outlined), title: Text('Bayar'))),
                        ],
                      ),
                    ),
                  );
                }),
                if (paid.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Riwayat tagihan lunas',
                      style: Theme.of(context).textTheme.titleMedium),
                  ),
                  ...paid.take(5).map((bill) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text(bill.title),
                      subtitle: Text(
                        '${DateFormat('dd MMM yyyy', 'id_ID').format(bill.dueDate)} • Lunas ${bill.paidAt == null ? '' : DateFormat('dd MMM yyyy', 'id_ID').format(bill.paidAt!)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Hapus tagihan',
                        onPressed: () => _deleteBill(bill),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  )),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class BudgetSection extends StatefulWidget {
  const BudgetSection({super.key, required this.database});

  final AppDatabase database;

  @override
  State<BudgetSection> createState() => _BudgetSectionState();
}

class _BudgetSectionState extends State<BudgetSection> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  String get _monthLabel => DateFormat('MMMM yyyy', 'id_ID').format(_month);

  Future<void> _showBudgetDialog({Budget? existing}) async {
    final amount = TextEditingController(
      text: existing == null ? '' : existing.monthlyLimit.toString(),
    );
    String category = existing?.category ?? _expenseCategories.first;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Tambah anggaran' : 'Ubah anggaran'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: _expenseCategories.map((value) => DropdownMenuItem(
                  value: value,
                  child: Text(value),
                )).toList(),
                onChanged: existing == null
                    ? (value) => setDialogState(() => category = value ?? category)
                    : null,
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Batas per bulan (Rp)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final limit = int.tryParse(
                  amount.text.replaceAll('.', '').replaceAll(',', ''),
                ) ?? 0;
                try {
                  await widget.database.saveBudget(
                    category: category,
                    monthlyLimit: limit,
                    month: _month,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Anggaran bulanan',
                style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              tooltip: 'Bulan sebelumnya',
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month - 1);
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Bulan berikutnya',
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month + 1);
              }),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Text(_monthLabel, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showBudgetDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Tambah anggaran kategori'),
          ),
        ),
        StreamBuilder<List<Budget>>(
          stream: widget.database.watchBudgetsForMonth(_month),
          builder: (context, budgetSnapshot) {
            if (budgetSnapshot.hasError) {
              return const Text('Anggaran tidak dapat dimuat.');
            }
            final budgets = budgetSnapshot.data ?? [];
            return StreamBuilder<List<FinanceTransaction>>(
              stream: widget.database.watchTransactions(),
              builder: (context, transactionSnapshot) {
                final expenses = (transactionSnapshot.data ?? []).where((tx) =>
                  tx.type == 'expense' &&
                  tx.occurredAt.year == _month.year &&
                  tx.occurredAt.month == _month.month
                );
                final spentByCategory = <String, int>{};
                for (final tx in expenses) {
                  final category = (tx.category == null || tx.category!.isEmpty)
                      ? 'Tanpa kategori'
                      : tx.category!;
                  spentByCategory[category] =
                      (spentByCategory[category] ?? 0) + tx.amount;
                }
                if (budgets.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Belum ada anggaran. Tambahkan batas pengeluaran untuk kategori yang ingin dikendalikan.'),
                    ),
                  );
                }
                final totalLimit = budgets.fold<int>(
                  0, (sum, budget) => sum + budget.monthlyLimit,
                );
                final totalSpent = budgets.fold<int>(
                  0,
                  (sum, budget) =>
                    sum + (spentByCategory[budget.category] ?? 0),
                );
                return Column(
                  children: [
                    Card(
                      child: ListTile(
                        title: const Text('Total anggaran kategori'),
                        subtitle: Text('Terpakai: ${_rupiah.format(totalSpent)}'),
                        trailing: Text(_rupiah.format(totalLimit),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    ...budgets.map((budget) {
                      final spent = spentByCategory[budget.category] ?? 0;
                      final ratio = spent / budget.monthlyLimit;
                      final exceeded = spent > budget.monthlyLimit;
                      final nearLimit = ratio >= 0.8;
                      final color = exceeded
                          ? Colors.red
                          : nearLimit ? Colors.orange : Colors.green;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(budget.category,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  IconButton(
                                    tooltip: 'Ubah anggaran',
                                    onPressed: () => _showBudgetDialog(existing: budget),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Hapus anggaran',
                                    onPressed: () async {
                                      await widget.database.deleteBudget(budget.id);
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              Text('${_rupiah.format(spent)} dari ${_rupiah.format(budget.monthlyLimit)}'),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: ratio.clamp(0.0, 1.0).toDouble(),
                                color: color,
                                minHeight: 8,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                exceeded
                                    ? 'Melebihi anggaran ${_rupiah.format(spent - budget.monthlyLimit)}'
                                    : nearLimit
                                        ? 'Peringatan: anggaran sudah terpakai ${(ratio * 100).round()}%'
                                        : 'Terpakai ${(ratio * 100).round()}%',
                                style: TextStyle(color: color, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class FinanceReportsSection extends StatefulWidget {
  const FinanceReportsSection({super.key, required this.database});

  final AppDatabase database;

  @override
  State<FinanceReportsSection> createState() => _FinanceReportsSectionState();
}

class _FinanceReportsSectionState extends State<FinanceReportsSection> {
  String _period = 'Bulan ini';
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _exporting = false;

  DateTime _periodStart(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'Bulan lalu':
        return DateTime(now.year, now.month - 1);
      case '30 hari':
        return today.subtract(const Duration(days: 29));
      case 'Rentang tanggal':
        return _customStart ?? DateTime(now.year, now.month);
      default:
        return DateTime(now.year, now.month);
    }
  }

  DateTime _periodEnd(DateTime now) {
    if (_period == 'Bulan lalu') return DateTime(now.year, now.month);
    if (_period == 'Rentang tanggal' && _customEnd != null) {
      return DateTime(_customEnd!.year, _customEnd!.month, _customEnd!.day + 1);
    }
    return DateTime(now.year, now.month, now.day + 1);
  }


  Future<void> _chooseRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
      initialDateRange: DateTimeRange(
        start: _customStart ?? DateTime(now.year, now.month, 1),
        end: _customEnd ?? DateTime(now.year, now.month, now.day),
      ),
    );
    if (picked != null) {
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
        _period = 'Rentang tanggal';
      });
    }
  }

  String _dateLabel(DateTime start, DateTime end) =>
      '${DateFormat('dd MMM yyyy', 'id_ID').format(start)} - '
      '${DateFormat('dd MMM yyyy', 'id_ID').format(end.subtract(const Duration(days: 1)))}';

  Future<void> _saveExcel(List<FinanceTransaction> items, int income,
      int expense, int opening, Map<String, int> categories,
      DateTime start, DateTime end) async {
    setState(() => _exporting = true);
    try {
      final book = xls.Excel.createExcel();
      final sheet = book['Laporan Keuangan'];
      sheet.appendRow([xls.TextCellValue('LAPORAN KEUANGAN FINTRACK')]);
      sheet.appendRow([xls.TextCellValue(_dateLabel(start, end))]);
      sheet.appendRow([xls.TextCellValue('Saldo awal'), xls.IntCellValue(opening)]);
      sheet.appendRow([xls.TextCellValue('Pemasukan'), xls.IntCellValue(income)]);
      sheet.appendRow([xls.TextCellValue('Pengeluaran'), xls.IntCellValue(expense)]);
      sheet.appendRow([xls.TextCellValue('Saldo akhir'), xls.IntCellValue(opening + income - expense)]);
      sheet.appendRow([]);
      sheet.appendRow([xls.TextCellValue('REKAP PENGELUARAN PER KATEGORI')]);
      sheet.appendRow([xls.TextCellValue('Kategori'), xls.TextCellValue('Total')]);
      final sortedCategories = categories.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sortedCategories) {
        sheet.appendRow([
          xls.TextCellValue(entry.key),
          xls.IntCellValue(entry.value),
        ]);
      }
      sheet.appendRow([]);
      sheet.appendRow([
        xls.TextCellValue('Tanggal'), xls.TextCellValue('Jenis'),
        xls.TextCellValue('Keterangan'), xls.TextCellValue('Kategori'),
        xls.TextCellValue('Nominal'),
      ]);
      final sorted = [...items]..sort((x, y) => x.occurredAt.compareTo(y.occurredAt));
      for (final tx in sorted) {
        sheet.appendRow([
          xls.TextCellValue(DateFormat('yyyy-MM-dd').format(tx.occurredAt)),
          xls.TextCellValue(tx.type == 'income' ? 'Pemasukan' : 'Pengeluaran'),
          xls.TextCellValue(tx.title),
          xls.TextCellValue(tx.category ?? 'Tanpa kategori'),
          xls.IntCellValue(tx.amount),
        ]);
      }
      final bytes = book.encode();
      if (bytes == null) throw StateError('Gagal membuat file Excel.');
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan laporan Excel',
        fileName: 'fintrack_laporan_$stamp.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ekspor Excel gagal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _savePdf(List<FinanceTransaction> items, int income,
      int expense, int opening, Map<String, int> categories,
      DateTime start, DateTime end) async {
    setState(() => _exporting = true);
    try {
      final doc = pw.Document();
      final detail = <List<String>>[
        ['Tanggal', 'Jenis', 'Keterangan', 'Kategori', 'Nominal'],
        ...([...items]..sort((x, y) => x.occurredAt.compareTo(y.occurredAt)))
            .map((tx) => [
              DateFormat('dd/MM/yy').format(tx.occurredAt),
              tx.type == 'income' ? 'Masuk' : 'Keluar',
              tx.title, tx.category ?? '-',
              _rupiah.format(tx.amount),
            ]),
      ];
      final sortedCategories = categories.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final categoryRows = <List<String>>[
        ['Kategori', 'Total pengeluaran'],
        ...sortedCategories.map((entry) => [
          entry.key,
          _rupiah.format(entry.value),
        ]),
      ];
      doc.addPage(pw.MultiPage(build: (context) => [
        pw.Text('LAPORAN KEUANGAN FINTRACK',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text(_dateLabel(start, end)),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(data: [
          ['Ringkasan', 'Nominal'],
          ['Saldo awal', _rupiah.format(opening)],
          ['Pemasukan', _rupiah.format(income)],
          ['Pengeluaran', _rupiah.format(expense)],
          ['Saldo akhir', _rupiah.format(opening + income - expense)],
        ]),
        pw.SizedBox(height: 16),
        pw.Text('Pengeluaran per kategori',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(data: categoryRows),
        pw.SizedBox(height: 16),
        pw.Text('Rincian transaksi',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(data: detail),
      ]));
      final bytes = await doc.save();
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan laporan PDF',
        fileName: 'fintrack_laporan_$stamp.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ekspor PDF gagal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = _periodStart(now);
    final end = _periodEnd(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Laporan keuangan', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _period,
          decoration: const InputDecoration(
            labelText: 'Periode laporan',
            border: OutlineInputBorder(),
          ),
          items: const ['Bulan ini', 'Bulan lalu', '30 hari', 'Rentang tanggal']
              .map((value) => DropdownMenuItem(value: value, child: Text(value)))
              .toList(),
          onChanged: (value) {
            if (value == 'Rentang tanggal') { _chooseRange(); }
            else { setState(() => _period = value ?? 'Bulan ini'); }
          },
        ),
        if (_period == 'Rentang tanggal' && _customStart != null && _customEnd != null)
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: _chooseRange,
            icon: const Icon(Icons.date_range),
            label: Text(_dateLabel(start, end)),
          )),
        const SizedBox(height: 8),
        StreamBuilder<List<FinanceTransaction>>(
          stream: widget.database.watchTransactions(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Laporan tidak dapat dimuat.'),
              ));
            }
            final allTransactions = snapshot.data ?? [];
            final transactions = allTransactions.where((tx) =>
              tx.type != 'transfer' &&
              !tx.occurredAt.isBefore(start) &&
              tx.occurredAt.isBefore(end)
            ).toList();

            var income = 0;
            var expense = 0;
            final expenseByCategory = <String, int>{};
            for (final tx in transactions) {
              if (tx.type == 'income') {
                income += tx.amount;
              } else if (tx.type == 'expense') {
                expense += tx.amount;
                final category = (tx.category == null || tx.category!.isEmpty)
                    ? 'Tanpa kategori'
                    : tx.category!;
                expenseByCategory[category] = (expenseByCategory[category] ?? 0) + tx.amount;
              }
            }
            final days = List<DateTime>.generate(7, (index) {
              final today = DateTime(now.year, now.month, now.day);
              return today.subtract(Duration(days: 6 - index));
            });
            final dailyIncome = <int>[];
            final dailyExpense = <int>[];
            for (final day in days) {
              var dayIncome = 0;
              var dayExpense = 0;
              for (final tx in allTransactions) {
                if (tx.type != 'transfer' &&
                    tx.occurredAt.year == day.year &&
                    tx.occurredAt.month == day.month &&
                    tx.occurredAt.day == day.day) {
                  if (tx.type == 'income') dayIncome += tx.amount;
                  if (tx.type == 'expense') dayExpense += tx.amount;
                }
              }
              dailyIncome.add(dayIncome);
              dailyExpense.add(dayExpense);
            }
            final categories = expenseByCategory.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final maxCategory = categories.isEmpty ? 1 : categories.first.value;
            final net = income - expense;
            final openingFlow = allTransactions.where((tx) =>
              tx.type != 'transfer' && tx.occurredAt.isBefore(start)
            ).fold<int>(0, (sum, tx) =>
              sum + (tx.type == 'income' ? tx.amount : -tx.amount));
            final openingAccounts = widget.database.watchAccounts().first;

            return Column(
              children: [
                FutureBuilder<List<Account>>(
                  future: openingAccounts,
                  builder: (context, accountSnapshot) {
                    final opening = (accountSnapshot.data ?? const <Account>[])
                      .fold<int>(0, (sum, account) => sum + account.openingBalance)
                      + openingFlow;
                    return Column(children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(
                          onPressed: _exporting ? null : () => _saveExcel(
                            transactions, income, expense, opening,
                            expenseByCategory, start, end),
                          icon: const Icon(Icons.table_view),
                          label: const Text('Ekspor Excel'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _exporting ? null : () => _savePdf(
                            transactions, income, expense, opening,
                            expenseByCategory, start, end),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Ekspor PDF'),
                        ),
                      ]),
                      if (_exporting) const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                      Card(child: ListTile(
                        title: const Text('Saldo awal periode'),
                        trailing: Text(_rupiah.format(opening)),
                      )),
                      Card(child: ListTile(
                        title: const Text('Saldo akhir periode'),
                        trailing: Text(_rupiah.format(opening + net)),
                      )),
                    ]);
                  },
                ),
                Row(
                  children: [
                    Expanded(child: _ReportMetric(
                      title: 'Pemasukan',
                      amount: income,
                      color: Colors.green,
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _ReportMetric(
                      title: 'Pengeluaran',
                      amount: expense,
                      color: Colors.red,
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: const Text('Selisih pemasukan - pengeluaran'),
                    subtitle: Text(_period),
                    trailing: Text(
                      _rupiah.format(net),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: net >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Aktivitas 7 hari terakhir',
                          style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 150,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _DailyFinanceChartPainter(
                              income: dailyIncome,
                              expense: dailyExpense,
                              incomeColor: Colors.green,
                              expenseColor: Colors.red,
                              gridColor: Theme.of(context).dividerColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: days.map((day) => Text(
                            DateFormat('E', 'id_ID').format(day),
                            style: Theme.of(context).textTheme.bodySmall,
                          )).toList(),
                        ),
                        const SizedBox(height: 12),
                        const Wrap(
                          spacing: 16,
                          children: [
                            _ChartLegend(color: Colors.green, label: 'Pemasukan'),
                            _ChartLegend(color: Colors.red, label: 'Pengeluaran'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pengeluaran per kategori',
                          style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        if (categories.isEmpty)
                          const Text('Belum ada pengeluaran pada periode ini.')
                        else
                          ...categories.map((entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text(entry.key)),
                                    Text(_rupiah.format(entry.value)),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                LinearProgressIndicator(
                                  value: entry.value / maxCategory,
                                  minHeight: 7,
                                ),
                              ],
                            ),
                          )),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.title,
    required this.amount,
    required this.color,
  });

  final String title;
  final int amount;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            _rupiah.format(amount),
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(2),
      )),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _DailyFinanceChartPainter extends CustomPainter {
  _DailyFinanceChartPainter({
    required this.income,
    required this.expense,
    required this.incomeColor,
    required this.expenseColor,
    required this.gridColor,
  });

  final List<int> income;
  final List<int> expense;
  final Color incomeColor;
  final Color expenseColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 8.0;
    const bottom = 8.0;
    final chartHeight = size.height - top - bottom;
    final incomeMax = income.reduce((a, b) => a > b ? a : b);
    final expenseMax = expense.reduce((a, b) => a > b ? a : b);
    final maxValue = math.max(1, math.max(incomeMax, expenseMax));
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.7;
    for (var line = 0; line <= 3; line++) {
      final y = top + chartHeight * line / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final slotWidth = size.width / 7;
    final barWidth = math.min(10.0, slotWidth * 0.27);
    final incomePaint = Paint()..color = incomeColor;
    final expensePaint = Paint()..color = expenseColor;
    for (var i = 0; i < 7; i++) {
      final center = slotWidth * (i + 0.5);
      final incomeHeight = chartHeight * income[i] / maxValue;
      final expenseHeight = chartHeight * expense[i] / maxValue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(center - barWidth - 1, top + chartHeight - incomeHeight, barWidth, incomeHeight),
          const Radius.circular(3),
        ),
        incomePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(center + 1, top + chartHeight - expenseHeight, barWidth, expenseHeight),
          const Radius.circular(3),
        ),
        expensePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DailyFinanceChartPainter oldDelegate) =>
      oldDelegate.income != income ||
      oldDelegate.expense != expense ||
      oldDelegate.incomeColor != incomeColor ||
      oldDelegate.expenseColor != expenseColor ||
      oldDelegate.gridColor != gridColor;
}
