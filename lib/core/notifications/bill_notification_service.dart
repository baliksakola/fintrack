import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../database/app_database.dart';

class BillNotificationService {
  BillNotificationService._();

  static final BillNotificationService instance = BillNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<bool> hasPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<void> syncBills(List<Bill> bills) async {
    await initialize();
    if (!await hasPermission()) return;

    await _plugin.cancelAll();
    final now = tz.TZDateTime.now(tz.local);

    for (final bill in bills.where((item) => !item.isPaid)) {
      final due = bill.dueDate;
      final reminder = tz.TZDateTime(
        tz.local, due.year, due.month, due.day - 1, 9,
      );
      final dueMorning = tz.TZDateTime(
        tz.local, due.year, due.month, due.day, 8,
      );

      if (reminder.isAfter(now)) {
        await _schedule(
          id: _notificationId(bill.id, 'before'),
          title: 'Pengingat tagihan FinTrack',
          body: 'Besok jatuh tempo: ${bill.title}. Nominal Rp ${bill.amount}.',
          date: reminder,
          payload: bill.id,
        );
      }
      if (dueMorning.isAfter(now)) {
        await _schedule(
          id: _notificationId(bill.id, 'due'),
          title: 'Tagihan jatuh tempo hari ini',
          body: '${bill.title} sebesar Rp ${bill.amount} perlu dibayar hari ini.',
          date: dueMorning,
          payload: bill.id,
        );
      }
    }
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime date,
    required String payload,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      date,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'fintrack_bill_reminders',
          'Pengingat tagihan',
          channelDescription: 'Pengingat sebelum dan pada tanggal jatuh tempo tagihan.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  int _notificationId(String value, String suffix) {
    var hash = 0;
    for (final unit in '$value:$suffix'.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
