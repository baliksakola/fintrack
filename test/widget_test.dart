import 'package:material_ui/material_ui.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/features/dashboard/dashboard_screen.dart';

void main() {
  testWidgets('dashboard fits compact phone width without layout overflow', (tester) async {
    await initializeDateFormatting('id_ID');
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('FinTrack Paday'), findsOneWidget);
    expect(find.text('Total saldo'), findsOneWidget);
    expect(find.text('Rekening'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Menu cepat'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Menu cepat'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await db.closeDatabase();
  });

  testWidgets('dashboard remains usable with larger text scaling', (tester) async {
    await initializeDateFormatting('id_ID');
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: const DashboardScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('FinTrack Paday'), findsOneWidget);
    expect(find.text('Total saldo'), findsOneWidget);
    expect(find.text('Rekening'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Menu cepat'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Menu cepat'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await db.closeDatabase();
  });

  testWidgets('dashboard cash flow excludes archived account transactions', (tester) async {
    await initializeDateFormatting('id_ID');
    final db = AppDatabase(NativeDatabase.memory());

    await db.addAccount('Aktif', 'Bank', 1000);
    await db.addAccount('Arsip', 'Bank', 9000);
    final accounts = await db.getAllAccounts();
    final active = accounts.firstWhere((account) => account.name == 'Aktif');
    final archived = accounts.firstWhere((account) => account.name == 'Arsip');

    await db.addIncome(
      accountId: active.id,
      amount: 500,
      title: 'Pemasukan aktif',
    );
    await db.addExpense(
      accountId: active.id,
      amount: 100,
      title: 'Pengeluaran aktif',
    );
    await db.addIncome(
      accountId: archived.id,
      amount: 7000,
      title: 'Pemasukan arsip',
    );
    await db.addExpense(
      accountId: archived.id,
      amount: 3000,
      title: 'Pengeluaran arsip',
    );
    await db.customStatement(
      'UPDATE accounts SET archived = 1 WHERE id = ?',
      [archived.id],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await db.watchTotalBalance().first, 1400);
    expect(find.text('Rp 1.400'), findsNWidgets(2));
    expect(find.text('Rp 500'), findsOneWidget);
    expect(find.text('Rp 100'), findsOneWidget);
    expect(find.text('Rp 7.000'), findsNothing);
    expect(find.text('Rp 3.000'), findsNothing);
    expect(tester.takeException(), isNull);

    await db.closeDatabase();
  });

  testWidgets('FinTrack dashboard renders', (tester) async {
    await initializeDateFormatting('id_ID');
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Ringkasan'), findsNWidgets(2));
    expect(find.text('Home'), findsNothing);
    expect(find.text('Total saldo'), findsOneWidget);
    expect(find.text('Rekening'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Menu cepat'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Menu cepat'), findsOneWidget);
    expect(find.text('Aktivitas'), findsNWidgets(2));
    expect(find.text('Rencana'), findsNWidgets(2));
    expect(find.text('Kalender'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.text('Prediksi kondisi keuangan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Prediksi kondisi keuangan'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);

    await tester.tap(find.text('Aktivitas').last);
    await tester.pumpAndSettle();
    expect(find.text('Aktivitas keuangan'), findsOneWidget);

    await tester.tap(find.text('Rencana').last);
    await tester.pumpAndSettle();
    expect(find.text('Rencana keuangan'), findsOneWidget);

    await tester.tap(find.text('Kalender').last);
    await tester.pumpAndSettle();
    expect(find.text('Kalender keuangan'), findsOneWidget);

    await tester.tap(find.text('Lainnya').last);
    await tester.pumpAndSettle();
    expect(find.text('Kelola keamanan, laporan, dan salinan cadangan data FinTrack.'), findsOneWidget);

    await db.closeDatabase();
  });
}
