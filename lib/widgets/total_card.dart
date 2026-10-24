import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

class TotalCard extends StatelessWidget {
  final double totalSpent;
  final double totalReceived;
  final int transactionCount;
  final String scopeLabel;
  final String dateScopeLabel;
  final int? accountCount;

  const TotalCard({
    super.key,
    required this.totalSpent,
    required this.totalReceived,
    required this.transactionCount,
    required this.scopeLabel,
    required this.dateScopeLabel,
    this.accountCount,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final theme = Theme.of(context);
    final txnColors = theme.extension<TransactionColors>()!;
    final txnWord = transactionCount == 1 ? 'transaction' : 'transactions';
    final subtitle = accountCount != null
        ? '$transactionCount $txnWord across $accountCount accounts · $dateScopeLabel'
        : '$transactionCount $txnWord · $dateScopeLabel';

    final total = totalSpent + totalReceived;
    final spentFraction = total > 0 ? totalSpent / total : 0.0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total spent · $scopeLabel',
            style: TextStyle(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            currency.format(totalSpent),
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    Expanded(
                      flex: (spentFraction * 1000).round().clamp(1, 999),
                      child: Container(color: txnColors.debit),
                    ),
                    Expanded(
                      flex: ((1 - spentFraction) * 1000).round().clamp(1, 999),
                      child: Container(color: txnColors.credit),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _LegendDot(color: txnColors.debit, label: 'Spent ${currency.format(totalSpent)}'),
                const SizedBox(width: 16),
                _LegendDot(color: txnColors.credit, label: 'Received ${currency.format(totalReceived)}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
