import 'dart:io';

import 'package:another_telephony/telephony.dart';

import '../db/db_helper.dart';
import '../models/expense.dart';
import 'sms_parser.dart';

String _deriveId(int? date, String? body) {
  // The live broadcast carries millisecond-precision date, but the same SMS
  // read back from the content provider during backfill is truncated to the
  // nearest second — round both to seconds so the same physical message
  // always derives the same id regardless of which path saw it first.
  final datePart = date != null ? date ~/ 1000 : 0;
  final bodyHash = (body ?? '').hashCode;
  return 'sms_${datePart}_$bodyHash';
}

Future<void> _handleIncomingMessage(SmsMessage message) async {
  if (!SmsParser.isBankSender(message.address)) return;

  final parsed = SmsParser.parse(message.body ?? '', bankSender: message.address);
  if (parsed == null) return;

  final id = _deriveId(message.date, message.body);
  if (await DbHelper.instance.exists(id)) return;

  await DbHelper.instance.insertExpense(
    Expense(
      id: id,
      amount: parsed.amount,
      title: parsed.title,
      date: message.date != null
          ? DateTime.fromMillisecondsSinceEpoch(message.date!)
          : DateTime.now(),
      type: parsed.type,
      source: ExpenseSource.auto,
      rawSms: message.body,
      bankSender: message.address,
    ),
  );
}

// Runs in a separate background isolate when a new SMS arrives while the app
// isn't in the foreground. Must stay a top-level function per the telephony
// plugin's requirements.
@pragma('vm:entry-point')
Future<void> smsBackgroundHandler(SmsMessage message) async {
  await _handleIncomingMessage(message);
}

class SmsService {
  final Telephony _telephony = Telephony.instance;

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return false;
    return await _telephony.requestSmsPermissions ?? false;
  }

  /// Scans existing inbox SMS (default: last 180 days, or since [after] if
  /// that's more recent — set after "clear all data" so wiped transactions
  /// don't just reappear from the SMS still sitting in the inbox) and stores
  /// any transaction messages not already saved. Used on first launch and
  /// for a manual "rescan" so messages received before the app was
  /// installed, or while it was force-closed, still get picked up.
  Future<int> backfillInbox({int days = 180, DateTime? after}) async {
    if (!Platform.isAndroid) return 0;

    final windowCutoff = DateTime.now().subtract(Duration(days: days));
    final cutoff =
        after != null && after.isAfter(windowCutoff) ? after : windowCutoff;
    final messages = await _telephony.getInboxSms(
      columns: [
        SmsColumn.ID,
        SmsColumn.ADDRESS,
        SmsColumn.BODY,
        SmsColumn.DATE,
      ],
      filter: SmsFilter.where(SmsColumn.DATE)
          .greaterThan(cutoff.millisecondsSinceEpoch.toString()),
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    var inserted = 0;
    for (final message in messages) {
      if (!SmsParser.isBankSender(message.address)) continue;

      final parsed = SmsParser.parse(message.body ?? '', bankSender: message.address);
      if (parsed == null) continue;

      final id = _deriveId(message.date, message.body);
      if (await DbHelper.instance.exists(id)) continue;

      await DbHelper.instance.insertExpense(
        Expense(
          id: id,
          amount: parsed.amount,
          title: parsed.title,
          date: message.date != null
              ? DateTime.fromMillisecondsSinceEpoch(message.date!)
              : DateTime.now(),
          type: parsed.type,
          source: ExpenseSource.auto,
          rawSms: message.body,
          bankSender: message.address,
        ),
      );
      inserted++;
    }
    return inserted;
  }

  /// Starts listening for new incoming SMS, both while the app is open and
  /// (via [smsBackgroundHandler]) while it's closed. [onForegroundMessage]
  /// is called after a transaction SMS received in the foreground has been
  /// saved, so the UI can refresh.
  void startListening({required void Function() onForegroundMessage}) {
    if (!Platform.isAndroid) return;

    _telephony.listenIncomingSms(
      onNewMessage: (message) async {
        await _handleIncomingMessage(message);
        onForegroundMessage();
      },
      onBackgroundMessage: smsBackgroundHandler,
      listenInBackground: true,
    );
  }
}
