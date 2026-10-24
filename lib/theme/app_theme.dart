import 'package:flutter/material.dart';

/// Semantic colors that aren't part of [ColorScheme] but need to flip
/// between the light and dark palettes (debit/credit amounts, tile icons).
class TransactionColors extends ThemeExtension<TransactionColors> {
  final Color debit;
  final Color debitContainer;
  final Color credit;
  final Color creditContainer;

  const TransactionColors({
    required this.debit,
    required this.debitContainer,
    required this.credit,
    required this.creditContainer,
  });

  @override
  TransactionColors copyWith({
    Color? debit,
    Color? debitContainer,
    Color? credit,
    Color? creditContainer,
  }) {
    return TransactionColors(
      debit: debit ?? this.debit,
      debitContainer: debitContainer ?? this.debitContainer,
      credit: credit ?? this.credit,
      creditContainer: creditContainer ?? this.creditContainer,
    );
  }

  @override
  TransactionColors lerp(TransactionColors? other, double t) {
    if (other == null) return this;
    return TransactionColors(
      debit: Color.lerp(debit, other.debit, t)!,
      debitContainer: Color.lerp(debitContainer, other.debitContainer, t)!,
      credit: Color.lerp(credit, other.credit, t)!,
      creditContainer: Color.lerp(creditContainer, other.creditContainer, t)!,
    );
  }
}

/// "Midnight Ledger" — a deep navy/ink dark theme with a gold ledger-stamp
/// accent, paired with a warm paper-toned light theme using the same accent
/// so switching modes feels like one brand, not two apps.
class AppTheme {
  AppTheme._();

  static const _gold = Color(0xFFCBA25A);

  static const _lightTransactionColors = TransactionColors(
    debit: Color(0xFFB3261E),
    debitContainer: Color(0xFFFBE9E7),
    credit: Color(0xFF1B6B3A),
    creditContainer: Color(0xFFE3F2E7),
  );

  static const _darkTransactionColors = TransactionColors(
    debit: Color(0xFFEF9A9A),
    debitContainer: Color(0xFF3A2222),
    credit: Color(0xFF81C995),
    creditContainer: Color(0xFF1E3326),
  );

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: _gold,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF8A6A1F),
      onPrimary: Colors.white,
      surface: const Color(0xFFFBF8F2),
      surfaceContainerHighest: const Color(0xFFF1ECE0),
    );

    return _base(scheme).copyWith(
      extensions: const [_lightTransactionColors],
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: _gold,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _gold,
      onPrimary: const Color(0xFF1C1506),
      surface: const Color(0xFF12161F),
      surfaceContainerHighest: const Color(0xFF1C2230),
      error: const Color(0xFFEF9A9A),
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0C0F16),
      extensions: const [_darkTransactionColors],
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
      ),
    );
  }
}
