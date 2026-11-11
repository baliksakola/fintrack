import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fintrack/core/database/app_database.dart';
import 'package:fintrack/main.dart';

void main() {
  testWidgets('FinTrack dashboard renders', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const FinTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FinTrack'), findsOneWidget);
    expect(find.text('Total saldo'), findsOneWidget);
    expect(find.text('Belum ada rekening. Tambahkan rekening pertama.'), findsOneWidget);

    await db.closeDatabase();
  });
}
