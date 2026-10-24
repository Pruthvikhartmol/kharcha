import '../models/expense.dart';

class ParsedSms {
  final double amount;
  final String title;
  final ExpenseType type;

  const ParsedSms({
    required this.amount,
    required this.title,
    required this.type,
  });
}

/// Best-effort parser for Indian bank / UPI transaction SMS.
///
/// Bank SMS formats are not standardized, so this relies on a handful of
/// keyword + regex heuristics rather than one strict template. Anything it
/// gets wrong (merchant name, or a non-transaction SMS slipping through) is
/// meant to be fixed by the user from the app, not perfected here.
class SmsParser {
  static final RegExp _amountPattern = RegExp(
    r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final RegExp _debitKeywords = RegExp(
    r'\b(debited|debit|spent|paid|withdrawn|sent)\b',
    caseSensitive: false,
  );

  static final RegExp _creditKeywords = RegExp(
    r'\b(credited|credit|received)\b',
    caseSensitive: false,
  );

  // Messages that merely mention a transaction in passing (balance alerts,
  // OTPs, promos) rather than reporting one. Bail out early on these.
  static final RegExp _noisePattern = RegExp(
    r'\b(otp|one time password|offer|cashback upto|win|lucky draw|avoid sharing|do not share)\b',
    caseSensitive: false,
  );

  static final List<RegExp> _titlePatterns = [
    // "...to VPA merchant@okbank" / "...paid to Swiggy on..."
    RegExp(
      r"\bto\s+(?:vpa\s+)?([A-Za-z0-9][A-Za-z0-9 .&'_-]{1,40}?)(?=\s+(?:on|via|upi|ref|successfully|using)\b|[,.]|$)",
      caseSensitive: false,
    ),
    // "...spent at Big Bazaar on..."
    RegExp(
      r"\bat\s+([A-Za-z0-9][A-Za-z0-9 .&'_-]{1,40}?)(?=\s+(?:on|via|upi|ref)\b|[,.]|$)",
      caseSensitive: false,
    ),
    // "...towards UPI/P2M/1234567890/Merchant Name"
    RegExp(
      r"towards\s+(?:upi[/-](?:p2m|p2a)[/-]?\d*[/-]?)?([A-Za-z0-9][A-Za-z0-9 .&'_-]{1,40})",
      caseSensitive: false,
    ),
    // "...credited ... by IMPS/NEFT from Rahul" — the sender's name on a
    // received-from-a-person credit, as opposed to a merchant payment.
    RegExp(
      r"\bfrom\s+([A-Za-z][A-Za-z .&'_-]{1,40}?)(?=\s+(?:on|via|upi|ref|successfully|using)\b|[,.]|$)",
      caseSensitive: false,
    ),
    // Fallback: raw VPA handle, e.g. "merchantname@okhdfcbank"
    RegExp(r'([a-zA-Z0-9.\-_]{3,})@[a-zA-Z]{3,}'),
  ];

  /// Banks/institutions send transactional SMS from DLT-registered
  /// alphanumeric sender IDs (e.g. "HDFCBK", "AD-SBIINB-S") per Indian
  /// telecom regulations — personal contacts always text from a plain phone
  /// number. Used to keep a friend's "paid you 500" out of auto-logging
  /// without having to guess from the message content.
  static bool isBankSender(String? address) {
    if (address == null || address.trim().isEmpty) return false;
    return address.contains(RegExp(r'[A-Za-z]'));
  }

  /// Returns null if [body] doesn't look like a bank transaction SMS.
  static ParsedSms? parse(String body, {String? bankSender}) {
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    if (_noisePattern.hasMatch(normalized)) return null;

    final amountMatch = _amountPattern.firstMatch(normalized);
    if (amountMatch == null) return null;
    final amountStr = amountMatch.group(1)!.replaceAll(',', '');
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) return null;

    final isDebit = _debitKeywords.hasMatch(normalized);
    final isCredit = _creditKeywords.hasMatch(normalized);
    if (!isDebit && !isCredit) return null;
    final type = isDebit ? ExpenseType.debit : ExpenseType.credit;

    final title = _extractTitle(normalized) ?? bankSender ?? 'Unknown';

    return ParsedSms(amount: amount, title: _cleanTitle(title), type: type);
  }

  static String? _extractTitle(String normalized) {
    for (final pattern in _titlePatterns) {
      final match = pattern.firstMatch(normalized);
      if (match != null) {
        final candidate = match.group(1)?.trim();
        if (candidate != null && candidate.length >= 2) {
          return candidate;
        }
      }
    }
    return null;
  }

  static String _cleanTitle(String raw) {
    var title = raw.trim();
    title = title.replaceAll(RegExp(r'[.,]+$'), '');
    // Collapse "merchantname" VPA-style handles into Title Case-ish text.
    if (!title.contains(' ') && title.length > 2) {
      title = title[0].toUpperCase() + title.substring(1);
    }
    return title.trim();
  }
}
