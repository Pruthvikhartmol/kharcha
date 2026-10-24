import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/sms_parser.dart';
import '../theme/app_theme.dart';
import '../utils/bank_directory.dart';

class AddEditExpenseScreen extends StatefulWidget {
  final Expense? existing;
  // Pre-fills the "paste SMS" box and parses it immediately — used when
  // opening this screen from a message shared in via the iOS Share
  // Extension, so the user lands straight on a filled-in form.
  final String? prefilledSmsText;

  const AddEditExpenseScreen({super.key, this.existing, this.prefilledSmsText});

  @override
  State<AddEditExpenseScreen> createState() => _AddEditExpenseScreenState();
}

class _AddEditExpenseScreenState extends State<AddEditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _smsController = TextEditingController();
  DateTime _date = DateTime.now();
  ExpenseType _type = ExpenseType.debit;
  String? _selectedBank;

  bool get _isEditing => widget.existing != null;

  // Once a transaction is saved — auto-logged or manually entered — amount,
  // date, type and bank are treated as the recorded facts of what happened;
  // only the title (a description, not a fact) can be corrected afterward.
  bool get _isLocked => _isEditing;

  bool get _isAutoSource => widget.existing?.source == ExpenseSource.auto;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _amountController.text = existing.amount.toStringAsFixed(2);
      _date = existing.date;
      _type = existing.type;
    }

    _selectedBank = existing?.bankSender;

    final sharedText = widget.prefilledSmsText;
    if (existing == null && sharedText != null) {
      _smsController.text = sharedText;
      final parsed = SmsParser.parse(sharedText);
      if (parsed != null) {
        _titleController.text = parsed.title;
        _amountController.text = parsed.amount.toStringAsFixed(2);
        _type = parsed.type;
      }
      _selectedBank = _reconcileBank(
        context.read<ExpenseProvider>(),
        BankDirectory.detectFromText(sharedText),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _smsController.dispose();
    super.dispose();
  }

  /// `BankDirectory.detectFromText` returns a friendly name (e.g. "HDFC
  /// Bank"), which only means the same thing as an existing account's raw
  /// sender key ("HDFCBK") if they're reconciled — otherwise the two look
  /// identical in the UI but are different values, splitting one bank across
  /// two chips/tabs. Prefer the real key whenever one already matches.
  String? _reconcileBank(ExpenseProvider provider, String? detected) {
    if (detected == null) return null;
    for (final key in provider.accountKeys) {
      if (BankDirectory.displayName(key) == detected) return key;
    }
    return detected;
  }

  /// Banks offered in the picker: only ones the app has actually seen a
  /// transaction from (so it stays short and relevant), plus whichever bank
  /// this entry is already tagged with, so an edit never loses its chip.
  List<String> _bankChipKeys(ExpenseProvider provider) {
    final keys = {...provider.accountKeys};
    final selected = _selectedBank;
    if (selected != null) keys.add(selected);
    final sorted = keys.toList()
      ..sort((a, b) =>
          BankDirectory.displayName(a).compareTo(BankDirectory.displayName(b)));
    return sorted;
  }

  void _applyParsedSms() {
    final parsed = SmsParser.parse(_smsController.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't find an amount/title in that text — "
              'fill the fields in below manually.'),
        ),
      );
      return;
    }
    final detectedBank = _reconcileBank(
      context.read<ExpenseProvider>(),
      BankDirectory.detectFromText(_smsController.text),
    );
    setState(() {
      _titleController.text = parsed.title;
      _amountController.text = parsed.amount.toStringAsFixed(2);
      _type = parsed.type;
      _selectedBank = detectedBank ?? _selectedBank;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<ExpenseProvider>();
    final amount = double.parse(_amountController.text);
    final title = _titleController.text.trim();
    final bankSender = _selectedBank;

    if (_isEditing) {
      await provider.updateExpense(
        widget.existing!.copyWith(
          title: title,
          amount: amount,
          date: _date,
          type: _type,
          bankSender: bankSender,
        ),
      );
    } else {
      await provider.addManualExpense(
        amount: amount,
        title: title,
        date: _date,
        type: _type,
        bankSender: bankSender,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<ExpenseProvider>().deleteExpense(widget.existing!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  InputDecoration _filledDecoration(
    BuildContext context, {
    required String label,
    String? prefixText,
    String? helperText,
    Widget? prefixIcon,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      prefixIcon: prefixIcon,
      helperText: helperText,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ExpenseProvider>();
    final bankChipKeys = _bankChipKeys(provider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit transaction' : 'Add transaction'),
        actions: [
          // Auto-logged transactions mirror a real bank SMS and can only be
          // removed via "Clear all" in Settings — only manual entries can be
          // deleted individually, and only with confirmation.
          if (_isEditing && !_isAutoSource)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isEditing) ...[
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Quick fill from bank SMS',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _smsController,
                        maxLines: 3,
                        decoration: _filledDecoration(
                          context,
                          label: 'Paste the SMS text',
                        ).copyWith(
                          hintText:
                              'Rs.250.00 debited ... paid to Swiggy ...',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: _applyParsedSms,
                          icon: const Icon(Icons.bolt, size: 18),
                          label: const Text('Parse'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    'OR ENTER MANUALLY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: _filledDecoration(
                        context,
                        label: 'Title (where you spent)',
                        prefixIcon: const Icon(Icons.storefront_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _amountController,
                      enabled: !_isLocked,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: _filledDecoration(
                        context,
                        label: 'Amount',
                        prefixText: '₹ ',
                        helperText: _isLocked
                            ? (_isAutoSource
                                ? 'Taken from the bank SMS — can\'t be edited'
                                : 'Can\'t be edited after saving')
                            : null,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final parsed = double.tryParse(v);
                        if (parsed == null || parsed <= 0) {
                          return 'Invalid amount';
                        }
                        return null;
                      },
                    ),
                    if (_isLocked) ...[
                      if (_selectedBank != null) ...[
                        Row(
                          children: [
                            Icon(Icons.account_balance_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text(
                              BankDirectory.displayName(_selectedBank!),
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                    ] else if (bankChipKeys.isNotEmpty) ...[
                      Text(
                        'Bank',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final key in bankChipKeys)
                            ChoiceChip(
                              label: Text(BankDirectory.displayName(key)),
                              selected: _selectedBank == key,
                              // Tapping the already-selected chip again clears
                              // it back to a general (no-bank) entry.
                              onSelected: (selected) => setState(
                                  () => _selectedBank = selected ? key : null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_isLocked)
                      _TypeBadge(type: _type)
                    else
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ExpenseType>(
                          segments: const [
                            ButtonSegment(
                              value: ExpenseType.debit,
                              label: Text('Spent'),
                              icon: Icon(Icons.arrow_upward),
                            ),
                            ButtonSegment(
                              value: ExpenseType.credit,
                              label: Text('Received'),
                              icon: Icon(Icons.arrow_downward),
                            ),
                          ],
                          selected: {_type},
                          onSelectionChanged: (s) =>
                              setState(() => _type = s.first),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Material(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _isLocked ? null : _pickDate,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              child: const Icon(Icons.calendar_today_outlined,
                                  size: 18),
                            ),
                            title: const Text('Date'),
                            subtitle: Text(
                              _isLocked
                                  ? '${_date.day}/${_date.month}/${_date.year} '
                                      '— ${_isAutoSource ? 'taken from the bank SMS' : "can't be changed after saving"}'
                                  : '${_date.day}/${_date.month}/${_date.year}',
                            ),
                            trailing: _isLocked
                                ? null
                                : const Icon(Icons.chevron_right),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: Icon(_isEditing ? Icons.check : Icons.add),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _isEditing ? 'Save changes' : 'Add transaction',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared rounded-card surface used to group each section of the form.
class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: child,
    );
  }
}

/// Read-only stand-in for the Spent/Received picker on locked (auto-logged)
/// transactions — a disabled SegmentedButton loses its color distinction
/// entirely, making it impossible to tell which side is active at a glance.
class _TypeBadge extends StatelessWidget {
  final ExpenseType type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isDebit = type == ExpenseType.debit;
    final txnColors = Theme.of(context).extension<TransactionColors>()!;
    final color = isDebit ? txnColors.debit : txnColors.credit;
    final containerColor =
        isDebit ? txnColors.debitContainer : txnColors.creditContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isDebit ? Icons.arrow_upward : Icons.arrow_downward,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            isDebit ? 'Spent' : 'Received',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
