import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// 14b step C: opens a vendor / rider identity document for staff.
///
/// The Cloud Function getIdentityDocumentUrl checks the caller's permission,
/// reads the Storage path from the private doc itself and returns a signed
/// URL that works for 5 minutes. The URL lives only in this dialog: it is
/// never written to Firestore, never logged and never shown as text.
class IdentityDocumentService {
  IdentityDocumentService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// [kind] 'vendor' | 'rider'; [which] 'nidFront' | 'nidBack' | 'tradeLicense'.
  static Future<String> signedUrl({
    required String kind,
    required String ownerId,
    required String which,
  }) async {
    final result = await _functions.httpsCallable('getIdentityDocumentUrl').call<dynamic>({
      'kind': kind,
      'ownerId': ownerId,
      'which': which,
    });
    final data = result.data;
    final url = data is Map ? data['url']?.toString() ?? '' : '';
    if (url.isEmpty) {
      throw FirebaseFunctionsException(code: 'not-found', message: 'No URL returned.');
    }
    return url;
  }
}

/// Plain message for the staff member; the technical detail goes to the log.
String identityDocumentErrorText(Object error) {
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return 'আপনার এই কাগজ দেখার অনুমতি নেই।';
      case 'not-found':
        return 'কাগজটা পাওয়া যায়নি।';
      case 'failed-precondition':
        return 'কাগজের তথ্যে সমস্যা আছে, ChalakChar-এর admin-কে জানান।';
      case 'unavailable':
        return 'ইন্টারনেট সংযোগ নেই, আবার চেষ্টা করুন।';
    }
  }
  return 'কাগজটা খোলা যায়নি, একটু পরে আবার চেষ্টা করুন।';
}

Future<void> showIdentityDocumentDialog(
  BuildContext context, {
  required String title,
  required String kind,
  required String ownerId,
  required String which,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _IdentityDocumentDialog(title: title, kind: kind, ownerId: ownerId, which: which),
  );
}

class _IdentityDocumentDialog extends StatefulWidget {
  const _IdentityDocumentDialog({
    required this.title,
    required this.kind,
    required this.ownerId,
    required this.which,
  });

  final String title;
  final String kind;
  final String ownerId;
  final String which;

  @override
  State<_IdentityDocumentDialog> createState() => _IdentityDocumentDialogState();
}

class _IdentityDocumentDialogState extends State<_IdentityDocumentDialog> {
  late Future<String> _url = _load();

  Future<String> _load() async {
    try {
      return await IdentityDocumentService.signedUrl(
        kind: widget.kind,
        ownerId: widget.ownerId,
        which: widget.which,
      );
    } catch (error, stack) {
      debugPrint('[identity document ${widget.kind}/${widget.which}] failed: '
          '${error is FirebaseFunctionsException ? error.code : error.runtimeType}');
      Error.throwWithStackTrace(error, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: size.width < 700 ? size.width * 0.9 : 640,
        height: size.height * 0.6,
        child: FutureBuilder<String>(
          future: _url,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _message(identityDocumentErrorText(snap.error!));
            }
            return InteractiveViewer(
              maxScale: 5,
              child: Image.network(
                snap.data!,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const Center(child: CircularProgressIndicator()),
                errorBuilder: (context, _, __) =>
                    _message('ছবিটা দেখানো যায়নি। লিংকের মেয়াদ ৫ মিনিট, আবার খুলুন।'),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _url = _load()),
          child: const Text('Reload'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
        ),
      );
}
