import 'package:material_ui/material_ui.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/features/dashboard/dashboard_screen.dart';

void main() {
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

    expect(find.text('Ringkasan'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Aktivitas'), findsOneWidget);
    expect(find.text('Rencana'), findsOneWidget);
    expect(find.text('Kalender'), findsOneWidget);
    expect(find.text('Total saldo'), findsOneWidget);
    expect(find.text('Aksi cepat'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Prediksi kondisi keuangan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Prediksi kondisi keuangan'), findsOneWidget);
    expect(find.text('Lainnya'), findsOneWidget);

    await db.closeDatabase();
  });
}
