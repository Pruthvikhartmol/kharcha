import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/expense.dart';
import '../services/share_service.dart';
import '../services/sms_service.dart';

enum ExpenseFilter { all, debitsOnly, creditsOnly }

enum ExpenseSort { dateDesc, dateAsc, amountDesc, amountAsc }

class ExpenseProvider extends ChangeNotifier {
  static const _clearedAtKey = 'expenses_cleared_at';
  static const _pageSize = 10;

  final SmsService _smsService = SmsService();
  final ShareService _shareService = ShareService();
  final _uuid = const Uuid();

  List<Expense> _expenses = [];
  bool _loading = true;
  bool _smsPermissionGranted = false;
  bool _scanning = false;
  DateTime? _clearedAt;
  ExpenseFilter _filter = ExpenseFilter.all;
  ExpenseSort _sort = ExpenseSort.dateDesc;
  DateTimeRange? _dateRange;
  String _searchQuery = '';
  final Map<String?, int> _visibleCounts = {};
  final List<String> _pendingShares = [];

  List<Expense> get expenses => _expenses;
  bool get loading => _loading;
  bool get smsPermissionGranted => _smsPermissionGranted;
  bool get scanning => _scanning;
  bool get isAndroid => Platform.isAndroid;
  bool get isIOS => Platform.isIOS;
  List<String> get pendingShares => _pendingShares;
  ExpenseFilter get filter => _filter;
  ExpenseSort get sort => _sort;
  DateTimeRange? get dateRange => _dateRange;
  String get searchQuery => _searchQuery;

  double get totalSpent => _expenses
      .where((e) => e.type == ExpenseType.debit)
      .fold(0.0, (sum, e) => sum + e.amount);

  double get totalReceived => _expenses
      .where((e) => e.type == ExpenseType.credit)
      .fold(0.0, (sum, e) => sum + e.amount);

  /// Accounts are derived from the distinct SMS sender on each auto-logged
  /// expense (e.g. "HDFCBK") rather than a separate account entity — there's
  /// no registration step, a new sender just shows up as a new tab the first
  /// time a transaction arrives from it.
  List<String> get accountKeys {
    final keys = _expenses
        .map((e) => e.bankSender)
        .whereType<String>()
        .toSet()
        .toList();
    keys.sort();
    return keys;
  }

  /// [accountKey]'s transactions scoped to the active date range, or to the
  /// current calendar month when no range has been explicitly picked. This
  /// is the basis for both the totals (ignores the show-filter) and the list
  /// (filter/sort/pagination applied on top).
  List<Expense> _dateScopedExpenses(String? accountKey) {
    final base = accountKey == null
        ? _expenses
        : _expenses.where((e) => e.bankSender == accountKey).toList();

    final range = _dateRange;
    if (range != null) {
      final start = DateTime(range.start.year, range.start.month, range.start.day);
      final endExclusive =
          DateTime(range.end.year, range.end.month, range.end.day + 1);
      return base
          .where((e) => !e.date.isBefore(start) && e.date.isBefore(endExclusive))
          .toList();
    }

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    return base.where((e) => !e.date.isBefore(monthStart)).toList();
  }

  List<Expense> _filteredSortedFor(String? accountKey) {
    var list = _dateScopedExpenses(accountKey);

    list = switch (_filter) {
      ExpenseFilter.all => list,
      ExpenseFilter.debitsOnly =>
        list.where((e) => e.type == ExpenseType.debit).toList(),
      ExpenseFilter.creditsOnly =>
        list.where((e) => e.type == ExpenseType.credit).toList(),
    };

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((e) => e.title.toLowerCase().contains(query)).toList();
    }

    final sorted = [...list];
    switch (_sort) {
      case ExpenseSort.dateDesc:
        sorted.sort((a, b) => b.date.compareTo(a.date));
      case ExpenseSort.dateAsc:
        sorted.sort((a, b) => a.date.compareTo(b.date));
      case ExpenseSort.amountDesc:
        sorted.sort((a, b) => b.amount.compareTo(a.amount));
      case ExpenseSort.amountAsc:
        sorted.sort((a, b) => a.amount.compareTo(b.amount));
    }
    return sorted;
  }

  /// The transactions to actually render for [accountKey]: date-scoped,
  /// filtered and sorted, then paginated 10-at-a-time — unless an explicit
  /// date range is active, in which case everything in that range is shown.
  List<Expense> expensesFor(String? accountKey) {
    final full = _filteredSortedFor(accountKey);
    if (_dateRange != null) return full;

    final visibleCount = _visibleCounts[accountKey] ?? _pageSize;
    return full.length > visibleCount ? full.sublist(0, visibleCount) : full;
  }

  /// Total count matching the current scope/filter, ignoring pagination —
  /// used for the "N transactions" summary, which should describe the whole
  /// matching set even when only the first page of it is rendered.
  int matchingCountFor(String? accountKey) =>
      _filteredSortedFor(accountKey).length;

  bool hasMoreFor(String? accountKey) {
    if (_dateRange != null) return false;
    final visibleCount = _visibleCounts[accountKey] ?? _pageSize;
    return _filteredSortedFor(accountKey).length > visibleCount;
  }

  void showMore(String? accountKey) {
    final current = _visibleCounts[accountKey] ?? _pageSize;
    _visibleCounts[accountKey] = current + _pageSize;
    notifyListeners();
  }

  /// Total spent for [accountKey] (or overall, if null), scoped to the
  /// active date range (or this month, by default) — always the true debit
  /// total for that scope, regardless of the list's show-filter, so
  /// switching "show only credits" doesn't change what "Total spent" means.
  double totalSpentFor(String? accountKey) => _dateScopedExpenses(accountKey)
      .where((e) => e.type == ExpenseType.debit)
      .fold(0.0, (sum, e) => sum + e.amount);

  /// Money in for the same scope as [totalSpentFor] — used alongside it to
  /// show the spent/received split, so "Total spent" never hides how much
  /// came back in over the same period.
  double totalReceivedFor(String? accountKey) => _dateScopedExpenses(accountKey)
      .where((e) => e.type == ExpenseType.credit)
      .fold(0.0, (sum, e) => sum + e.amount);

  int debitCountFor(String? accountKey) => _dateScopedExpenses(accountKey)
      .where((e) => e.type == ExpenseType.debit)
      .length;

  /// All-time (not date-scoped) figures for [accountKey] — used by the
  /// Profile screen's bank directory, which should always show the complete
  /// picture regardless of whatever date range is active on the Home screen.
  double allTimeTotalSpentFor(String? accountKey) {
    final scoped = accountKey == null
        ? _expenses
        : _expenses.where((e) => e.bankSender == accountKey).toList();
    return scoped
        .where((e) => e.type == ExpenseType.debit)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  int allTimeTransactionCountFor(String? accountKey) {
    final scoped = accountKey == null
        ? _expenses
        : _expenses.where((e) => e.bankSender == accountKey).toList();
    return scoped.length;
  }

  void setFilter(ExpenseFilter filter) {
    _filter = filter;
    _visibleCounts.clear();
    notifyListeners();
  }

  void setSort(ExpenseSort sort) {
    _sort = sort;
    notifyListeners();
  }

  void setDateRange(DateTimeRange? range) {
    _dateRange = range;
    _visibleCounts.clear();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _visibleCounts.clear();
    notifyListeners();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final clearedAtMs = prefs.getInt(_clearedAtKey);
    _clearedAt = clearedAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(clearedAtMs)
        : null;

    await _loadFromDb();

    if (Platform.isAndroid) {
      _smsPermissionGranted = await _smsService.requestPermissions();
      if (_smsPermissionGranted) {
        await rescan();
        _smsService.startListening(onForegroundMessage: _loadFromDb);
      }
    }

    if (Platform.isIOS) {
      await checkPendingShares();
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> _loadFromDb() async {
    _expenses = await DbHelper.instance.getAllExpenses();
    notifyListeners();
  }

  /// Picks up SMS text shared into the app via the iOS Share Extension
  /// (Messages → Share → Kharcha) since the last check. Called on launch and
  /// on every app resume, so a share made while Kharcha wasn't running still
  /// surfaces as soon as it's opened.
  Future<void> checkPendingShares() async {
    final shares = await _shareService.takePendingShares();
    if (shares.isEmpty) return;
    _pendingShares.addAll(shares);
    notifyListeners();
  }

  void dismissPendingShare(String text) {
    _pendingShares.remove(text);
    notifyListeners();
  }

  /// Re-requests permission (in case it was denied at first launch) and
  /// re-scans the SMS inbox for any transactions not yet saved.
  Future<void> rescan() async {
    if (!Platform.isAndroid) return;

    _smsPermissionGranted = await _smsService.requestPermissions();
    if (!_smsPermissionGranted) {
      notifyListeners();
      return;
    }

    _scanning = true;
    notifyListeners();
    await _smsService.backfillInbox(after: _clearedAt);
    await _loadFromDb();
    _scanning = false;
    notifyListeners();
  }

  Future<void> addManualExpense({
    required double amount,
    required String title,
    required DateTime date,
    required ExpenseType type,
    String? bankSender,
  }) async {
    final expense = Expense(
      id: _uuid.v4(),
      amount: amount,
      title: title,
      date: date,
      type: type,
      source: ExpenseSource.manual,
      bankSender: bankSender,
    );
    await DbHelper.instance.insertExpense(expense);
    await _loadFromDb();
  }

  Future<void> updateExpense(Expense expense) async {
    await DbHelper.instance.updateExpense(expense);
    await _loadFromDb();
  }

  Future<void> deleteExpense(String id) async {
    await DbHelper.instance.deleteExpense(id);
    await _loadFromDb();
  }

  /// Wipes every stored transaction and draws a line so a later rescan won't
  /// just re-import the same SMS back out of the inbox — only messages from
  /// after this point get picked up again.
  Future<void> clearAllData() async {
    final now = DateTime.now();
    await DbHelper.instance.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_clearedAtKey, now.millisecondsSinceEpoch);
    _clearedAt = now;
    _expenses = [];
    notifyListeners();
  }
}
