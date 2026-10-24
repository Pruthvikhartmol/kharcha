import 'dart:io';

import 'package:flutter/services.dart';

/// Bridges to the iOS Share Extension: when the user shares SMS text from
/// Messages into Kharcha, the extension stashes it in an App Group shared
/// container (native code can't reach Dart directly). This reads whatever
/// landed there since the app last checked, and clears it in the same call.
class ShareService {
  static const _channel = MethodChannel('com.kharcha.expensetracker/share');

  Future<List<String>> takePendingShares() async {
    if (!Platform.isIOS) return const [];
    final result =
        await _channel.invokeMethod<List<dynamic>>('takePendingShares');
    return (result ?? const []).cast<String>();
  }
}
