import 'package:flutter/material.dart';

/// Turns a raw SMS sender ID (e.g. "AD-HDFCBK-S", "ICICIB", "SBIUPI") into a
/// human-readable bank name and a stable color, so a transaction's account
/// reads as "HDFC Bank" instead of a cryptic DLT code.
class BankDirectory {
  BankDirectory._();

  // DLT sender IDs are commonly wrapped as "<2-letter-telco>-<CODE>-<type>"
  // (e.g. "AD-HDFCBK-S"); strip that scaffolding before matching the core.
  static final RegExp _dltWrapper =
      RegExp(r'^[A-Z]{2}-|-[A-Z]$', caseSensitive: false);

  static final Map<String, String> _knownBanks = {
    'HDFC': 'HDFC Bank',
    'ICICI': 'ICICI Bank',
    'SBIUPI': 'State Bank of India',
    'SBIINB': 'State Bank of India',
    'SBICRD': 'State Bank of India',
    'SBI': 'State Bank of India',
    'AXIS': 'Axis Bank',
    'KOTAK': 'Kotak Mahindra Bank',
    'PNB': 'Punjab National Bank',
    'BOB': 'Bank of Baroda',
    'BARODA': 'Bank of Baroda',
    'BOI': 'Bank of India',
    'CANBNK': 'Canara Bank',
    'CANARA': 'Canara Bank',
    'UBOI': 'Union Bank of India',
    'UNIONB': 'Union Bank of India',
    'IDFC': 'IDFC FIRST Bank',
    'YESBNK': 'Yes Bank',
    'INDUS': 'IndusInd Bank',
    'RBLBNK': 'RBL Bank',
    'RBL': 'RBL Bank',
    'FEDBNK': 'Federal Bank',
    'FEDERAL': 'Federal Bank',
    'PAYTM': 'Paytm Payments Bank',
    'AMAZONPAY': 'Amazon Pay',
    'AMAZON': 'Amazon Pay',
    'PHONPE': 'PhonePe',
    'PHONEPE': 'PhonePe',
    'GPAY': 'Google Pay',
    'HSBC': 'HSBC',
    'CITI': 'Citibank',
    'SCBL': 'Standard Chartered',
    'STANC': 'Standard Chartered',
    'IDBI': 'IDBI Bank',
    'INDBNK': 'Indian Bank',
    'INDIAN': 'Indian Bank',
    'CBOI': 'Central Bank of India',
    'CENTBK': 'Central Bank of India',
    'UCOBNK': 'UCO Bank',
    'SIBSMS': 'South Indian Bank',
    'DCBBNK': 'DCB Bank',
    'AUBANK': 'AU Small Finance Bank',
    'AUSFB': 'AU Small Finance Bank',
    'EQUITAS': 'Equitas Small Finance Bank',
    'SLICE': 'Slice',
    'JUPITR': 'Jupiter',
  };

  static final List<Color> _palette = [
    const Color(0xFF6D597A),
    const Color(0xFF355070),
    const Color(0xFFB56576),
    const Color(0xFF0B6E4F),
    const Color(0xFF8A6A1F),
    const Color(0xFF4A5A83),
    const Color(0xFF9E6240),
    const Color(0xFF3E6164),
    const Color(0xFF7D5BA6),
    const Color(0xFF6B705C),
  ];

  /// "AD-HDFCBK-S" / "HDFCBK" / "ICICIB" -> readable bank name. Falls back to
  /// a title-cased version of the sender code when it isn't recognized.
  static String displayName(String senderId) {
    final core =
        senderId.toUpperCase().replaceAll(_dltWrapper, '').trim();
    for (final entry in _knownBanks.entries) {
      if (core.contains(entry.key)) return entry.value;
    }
    if (core.isEmpty) return senderId;
    final titled = core[0] + core.substring(1).toLowerCase();
    return titled;
  }

  /// Scans the full SMS text for a bank's name — used for pasted/shared
  /// messages (manual entry, the iOS Share Extension), which only ever have
  /// the message body, never the actual sender id. Most Indian bank SMS
  /// mention the bank by name somewhere, often as a sign-off like
  /// "...Avl Bal Rs.1,000 -HDFC Bank", so this recovers the bank even
  /// without SMS-sender access.
  static String? detectFromText(String text) {
    final upper = text.toUpperCase();
    for (final entry in _knownBanks.entries) {
      if (upper.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// A stable color per sender so the same bank always gets the same avatar
  /// color across the app, without needing a hand-maintained color map.
  static Color colorFor(String senderId) {
    final hash = senderId.toUpperCase().codeUnits.fold<int>(
        0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    return _palette[hash % _palette.length];
  }
}
