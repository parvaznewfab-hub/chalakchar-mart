import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// What a customer, vendor or rider sees when a submit fails: a plain
/// message, never the technical error. The real error goes to the log
/// ([debugPrint], visible in the browser console / logcat).
const String kSubmitFailedMessage =
    'জমা দেওয়া যায়নি, একটু পরে আবার চেষ্টা করুন বা support-এ যোগাযোগ করুন।';

const String kNoConnectionMessage =
    'ইন্টারনেট সংযোগ পাওয়া যায়নি। সংযোগ দেখে আবার চেষ্টা করুন।';

/// Logs [error] under [where] and returns the message to show.
String friendlySubmitError(Object error, {String where = 'submit', StackTrace? stack}) {
  debugPrint('[$where] failed: $error');
  if (stack != null) debugPrint('$stack');
  if (error is FirebaseException && (error.code == 'unavailable' || error.code == 'network-request-failed')) {
    return kNoConnectionMessage;
  }
  return kSubmitFailedMessage;
}
