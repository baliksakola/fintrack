import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

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
              Text('Transaksi terbaru', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              StreamBuilder<List<FinanceTransaction>>(
                stream: db.watchTransactions(),
                builder: (context, snapshot) {
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Belum ada transaksi yang dicatat.'),
                      ),
                    );
                  }
                  return Column(
                    children: items.take(20).map((tx) {
                      final income = tx.type == 'income';
                      final transfer = tx.type == 'transfer';
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(transfer ? Icons.swap_horiz : income ? Icons.south_west : Icons.north_east),
                          ),
                          title: Text(tx.title),
                          subtitle: Text(DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(tx.occurredAt)),
                          trailing: Text(
                            '${income ? '+' : transfer ? '' : '-'}${_rupiah.format(tx.amount)}',
                            style: TextStyle(fontWeight: FontWeight.w600,
                              color: income ? Colors.green : transfer ? null : Colors.red),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
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
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
        FilledButton(onPressed: () async {
          final value = int.tryParse(amount.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
          try {
            if (type == 'income') {
              await db.addIncome(accountId: accountId, amount: value, title: title.text);
            } else {
              await db.addExpense(accountId: accountId, amount: value, title: title.text);
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
          }
        }, child: const Text('Transfer')),
      ],
    ),
  ));
}
