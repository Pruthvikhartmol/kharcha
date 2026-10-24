enum ExpenseSource { auto, manual }

enum ExpenseType { debit, credit }

class Expense {
  final String id;
  final double amount;
  final String title;
  final DateTime date;
  final ExpenseType type;
  final ExpenseSource source;
  final String? rawSms;
  final String? bankSender;

  const Expense({
    required this.id,
    required this.amount,
    required this.title,
    required this.date,
    required this.type,
    required this.source,
    this.rawSms,
    this.bankSender,
  });

  static const _unset = Object();

  Expense copyWith({
    String? title,
    double? amount,
    DateTime? date,
    ExpenseType? type,
    // Uses a sentinel default (rather than just `String? bankSender`) so
    // "not passed" (keep existing) and "passed as null" (clear it) are
    // distinguishable — a manually-tagged bank can be unset again.
    Object? bankSender = _unset,
  }) {
    return Expense(
      id: id,
      amount: amount ?? this.amount,
      title: title ?? this.title,
      date: date ?? this.date,
      type: type ?? this.type,
      source: source,
      rawSms: rawSms,
      bankSender:
          identical(bankSender, _unset) ? this.bankSender : bankSender as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'title': title,
      'date': date.millisecondsSinceEpoch,
      'type': type.name,
      'source': source.name,
      'rawSms': rawSms,
      'bankSender': bankSender,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      amount: (map['amount'] as num).toDouble(),
      title: map['title'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      type: ExpenseType.values.firstWhere((e) => e.name == map['type']),
      source: ExpenseSource.values.firstWhere((e) => e.name == map['source']),
      rawSms: map['rawSms'] as String?,
      bankSender: map['bankSender'] as String?,
    );
  }
}
