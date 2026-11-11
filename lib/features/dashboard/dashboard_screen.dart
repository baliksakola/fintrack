import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

const _incomeCategories = ['Gaji', 'Bonus', 'Usaha', 'Investasi', 'Hadiah', 'Lainnya'];
const _expenseCategories = ['Makanan', 'Transportasi', 'Belanja', 'Tagihan', 'Kesehatan', 'Pendidikan', 'Hiburan', 'Lainnya'];

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FinTrack'),
        actions: [
          IconButton(
            tooltip: 'Tambah rekening',
            onPressed: () => _showAccountDialog(context, db),
            icon: const Icon(Icons.add_card),
          ),
        ],
      ),
      body: StreamBuilder<int>(
        stream: db.watchTotalBalance(),
        builder: (context, balanceSnapshot) {
          final total = balanceSnapshot.data ?? 0;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total saldo', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(_rupiah.format(total),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Saldo gabungan seluruh rekening aktif'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _showTransactionDialog(context, db, 'income'),
                    icon: const Icon(Icons.add),
                    label: const Text('Pemasukan'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _showTransactionDialog(context, db, 'expense'),
                    icon: const Icon(Icons.remove),
                    label: const Text('Pengeluaran'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showTransferDialog(context, db),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Transfer'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Rekening', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              StreamBuilder<List<Account>>(
                stream: db.watchAccounts(),
                builder: (context, snapshot) {
                  final accounts = snapshot.data ?? [];
                  if (accounts.isEmpty) {
                    return const Card(child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Belum ada rekening. Tambahkan rekening pertama.'),
                    ));
                  }
                  return Column(
                    children: accounts.map((account) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet_outlined)),
                        title: Text(account.name),
                        subtitle: Text(account.type),
                        trailing: FutureBuilder<int>(
                          future: db.balanceFor(account.id),
                          builder: (context, value) => Text(
                            _rupiah.format(value.data ?? account.openingBalance),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    )).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              BudgetSection(database: db),
              const SizedBox(height: 24),
              FinanceReportsSection(database: db),
              const SizedBox(height: 24),
              TransactionHistorySection(database: db),
            ],
          );
        },
      ),
    );
  }
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
              return matchesType && matchesSearch;
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

  DateTime _periodStart(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'Bulan lalu':
        return DateTime(now.year, now.month - 1);
      case '30 hari':
        return today.subtract(const Duration(days: 29));
      default:
        return DateTime(now.year, now.month);
    }
  }

  DateTime _periodEnd(DateTime now) {
    if (_period == 'Bulan lalu') {
      return DateTime(now.year, now.month);
    }
    return DateTime(now.year, now.month, now.day + 1);
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
          items: const ['Bulan ini', 'Bulan lalu', '30 hari']
              .map((value) => DropdownMenuItem(value: value, child: Text(value)))
              .toList(),
          onChanged: (value) => setState(() => _period = value ?? 'Bulan ini'),
        ),
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

            return Column(
              children: [
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
