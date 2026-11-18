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
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('FinTrack Paday'), findsOneWidget);
    expect(find.text('Total saldo'), findsOneWidget);
    expect(find.text('Menu cepat'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await db.closeDatabase();
  });

  testWidgets('dashboard remains usable with larger text scaling', (tester) async {
    await initializeDateFormatting('id_ID');
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.textScaler = const TextScaler.linear(1.3);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetTextScaler);

    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('FinTrack Paday'), findsOneWidget);
    expect(find.text('Total saldo'), findsOneWidget);
    expect(find.text('Menu cepat'), findsOneWidget);
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
    expect(find.text('Aktivitas'), findsNWidgets(2));
    expect(find.text('Rencana'), findsNWidgets(2));
    expect(find.text('Kalender'), findsNWidgets(2));
    expect(find.text('Total saldo'), findsOneWidget);
    expect(find.text('Menu cepat'), findsOneWidget);
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
