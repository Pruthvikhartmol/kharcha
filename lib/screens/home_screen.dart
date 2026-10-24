import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/expense_provider.dart';
import '../utils/bank_directory.dart';
import '../widgets/expense_tile.dart';
import '../widgets/total_card.dart';
import 'add_edit_expense_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _searching = false;
  final _searchController = TextEditingController();

  void _startSearch() {
    setState(() => _searching = true);
  }

  void _stopSearch() {
    _searchController.clear();
    context.read<ExpenseProvider>().setSearchQuery('');
    setState(() => _searching = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches a share made while Kharcha was backgrounded (not relaunched) —
    // iOS Share Extensions can't reach the Dart side directly, so this is
    // the other half of the check that also runs at app startup.
    if (state == AppLifecycleState.resumed) {
      context.read<ExpenseProvider>().checkPendingShares();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    // null stands for "All accounts"; every other entry is a bankSender this
    // provider has actually seen a transaction from, so a newly-detected
    // account just shows up as a new tab the next time this rebuilds.
    final tabKeys = <String?>[null, ...provider.accountKeys];

    return DefaultTabController(
      length: tabKeys.length,
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search transactions…',
                    border: InputBorder.none,
                  ),
                  onChanged: provider.setSearchQuery,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/icon/icon_foreground.png',
                        width: 28, height: 28),
                    const SizedBox(width: 10),
                    const Text('My Spendings'),
                  ],
                ),
          actions: [
            IconButton(
              tooltip: _searching ? 'Close search' : 'Search',
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: _searching ? _stopSearch : _startSearch,
            ),
            if (!_searching) ...[
              IconButton(
                tooltip: 'Filter',
                icon: const Icon(Icons.filter_list),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => const _SortFilterSheet(),
                ),
              ),
              if (provider.isAndroid)
                IconButton(
                  tooltip: 'Rescan SMS inbox',
                  icon: provider.scanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  onPressed:
                      provider.scanning ? null : () => provider.rescan(),
                ),
              IconButton(
                tooltip: 'Profile',
                icon: const Icon(Icons.account_circle_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
              ),
            ],
          ],
          bottom: tabKeys.length > 1
              ? TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: tabKeys
                      .map((key) => Tab(
                          text: key == null
                              ? 'All'
                              : BankDirectory.displayName(key)))
                      .toList(),
                )
              : null,
        ),
        body: provider.loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: tabKeys
                    .map((key) => _AccountTab(accountKey: key))
                    .toList(),
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddEditExpenseScreen()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
      ),
    );
  }
}

String _dateScopeLabel(DateTimeRange? range) {
  if (range == null) return 'This month';
  final sameYear = range.start.year == range.end.year;
  final startFmt = sameYear ? DateFormat('d MMM') : DateFormat('d MMM yyyy');
  final endFmt = DateFormat('d MMM yyyy');
  return '${startFmt.format(range.start)} – ${endFmt.format(range.end)}';
}

class _AccountTab extends StatelessWidget {
  final String? accountKey;

  const _AccountTab({required this.accountKey});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final expenses = provider.expensesFor(accountKey);
    final hasAnyForAccount = accountKey == null
        ? provider.expenses.isNotEmpty
        : provider.expenses.any((e) => e.bankSender == accountKey);
    final accountCount = provider.accountKeys.length;

    return RefreshIndicator(
      onRefresh: provider.rescan,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                TotalCard(
                  totalSpent: provider.totalSpentFor(accountKey),
                  totalReceived: provider.totalReceivedFor(accountKey),
                  transactionCount: provider.matchingCountFor(accountKey),
                  scopeLabel: accountKey == null
                      ? 'All accounts'
                      : BankDirectory.displayName(accountKey!),
                  dateScopeLabel: _dateScopeLabel(provider.dateRange),
                  accountCount:
                      accountKey == null && accountCount > 1
                          ? accountCount
                          : null,
                ),
                if (accountKey == null &&
                    provider.isAndroid &&
                    !provider.smsPermissionGranted)
                  _PermissionBanner(onGrant: provider.rescan),
                if (accountKey == null && provider.pendingShares.isNotEmpty)
                  _PendingShareBanner(
                    count: provider.pendingShares.length,
                    onReview: () {
                      final text = provider.pendingShares.first;
                      provider.dismissPendingShare(text);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AddEditExpenseScreen(prefilledSmsText: text),
                        ),
                      );
                    },
                  ),
                if (expenses.isNotEmpty)
                  _SortHeaderRow(
                    sort: provider.sort,
                    onChanged: provider.setSort,
                  ),
              ],
            ),
          ),
          if (expenses.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                isAndroid: provider.isAndroid,
                isFiltered: accountKey != null,
                filterHidingResults: hasAnyForAccount &&
                    (provider.filter != ExpenseFilter.all ||
                        provider.searchQuery.trim().isNotEmpty),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final expense = expenses[index];
                  return ExpenseTile(
                    expense: expense,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AddEditExpenseScreen(
                          existing: expense,
                        ),
                      ),
                    ),
                  );
                },
                childCount: expenses.length,
              ),
            ),
          if (provider.hasMoreFor(accountKey))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: TextButton(
                    onPressed: () => provider.showMore(accountKey),
                    child: const Text('See more'),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

class _SortHeaderRow extends StatelessWidget {
  final ExpenseSort sort;
  final ValueChanged<ExpenseSort> onChanged;

  const _SortHeaderRow({required this.sort, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SortToggle(
            label: 'Date',
            ascValue: ExpenseSort.dateAsc,
            descValue: ExpenseSort.dateDesc,
            current: sort,
            onChanged: onChanged,
          ),
          _SortToggle(
            label: 'Amount',
            ascValue: ExpenseSort.amountAsc,
            descValue: ExpenseSort.amountDesc,
            current: sort,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SortToggle extends StatelessWidget {
  final String label;
  final ExpenseSort ascValue;
  final ExpenseSort descValue;
  final ExpenseSort current;
  final ValueChanged<ExpenseSort> onChanged;

  const _SortToggle({
    required this.label,
    required this.ascValue,
    required this.descValue,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current == ascValue || current == descValue;
    final isAsc = current == ascValue;
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () =>
          onChanged(isActive ? (isAsc ? descValue : ascValue) : descValue),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              isActive
                  ? (isAsc ? Icons.arrow_upward : Icons.arrow_downward)
                  : Icons.unfold_more,
              size: 15,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

class _SortFilterSheet extends StatefulWidget {
  const _SortFilterSheet();

  @override
  State<_SortFilterSheet> createState() => _SortFilterSheetState();
}

class _SortFilterSheetState extends State<_SortFilterSheet> {
  late ExpenseFilter _filter;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ExpenseProvider>();
    _filter = provider.filter;
    _range = provider.dateRange;
  }

  void _clear() {
    setState(() {
      _filter = ExpenseFilter.all;
      _range = null;
    });
  }

  void _apply() {
    final provider = context.read<ExpenseProvider>();
    provider.setFilter(_filter);
    provider.setDateRange(_range);
    Navigator.of(context).pop();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SHOW',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
            ),
            RadioGroup<ExpenseFilter>(
              groupValue: _filter,
              onChanged: (f) => setState(() => _filter = f!),
              child: const Column(
                children: [
                  RadioListTile<ExpenseFilter>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('All transactions'),
                    value: ExpenseFilter.all,
                  ),
                  RadioListTile<ExpenseFilter>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Debits only (money out)'),
                    value: ExpenseFilter.debitsOnly,
                  ),
                  RadioListTile<ExpenseFilter>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Credits only (money in)'),
                    value: ExpenseFilter.creditsOnly,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'DATE RANGE',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(_range == null
                  ? 'This month'
                  : _dateScopeLabel(_range)),
              subtitle: Text(_range == null
                  ? 'Showing up to 10 at a time'
                  : 'Showing every matching transaction'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickRange,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingShareBanner extends StatelessWidget {
  final int count;
  final VoidCallback onReview;

  const _PendingShareBanner({required this.count, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.ios_share, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? 'A message shared from Messages is ready to log.'
                  : '$count messages shared from Messages are ready to log.',
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(onPressed: onReview, child: const Text('Review')),
        ],
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final Future<void> Function() onGrant;

  const _PermissionBanner({required this.onGrant});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.sms_failed_outlined,
              color: Theme.of(context).colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'SMS permission not granted — transactions won\'t be '
              'detected automatically.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(onPressed: onGrant, child: const Text('Grant')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isAndroid;
  final bool isFiltered;
  final bool filterHidingResults;

  const _EmptyState({
    required this.isAndroid,
    required this.isFiltered,
    required this.filterHidingResults,
  });

  @override
  Widget build(BuildContext context) {
    final String message;
    if (filterHidingResults) {
      message = 'No transactions match the current filter.';
    } else if (isFiltered) {
      message = 'No transactions from this account yet.';
    } else if (isAndroid) {
      message = 'No transactions yet.\nSpend via UPI and it\'ll show up '
          'here, or add one manually.';
    } else {
      message = 'No transactions yet.\niOS can\'t read SMS automatically — '
          'tap + and paste the bank SMS text to log a spend.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
