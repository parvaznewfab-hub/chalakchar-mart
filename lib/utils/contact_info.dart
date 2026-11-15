import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';

/// Contact details come from settings/app (Admin › Settings), shown exactly
/// as entered there, so every page shows the same phone format (audit #13:
/// one page said "01975-838764", the others "01975838764").

/// wa.me link for a Bangladeshi number in any format ("01975838764",
/// "+880 1975-838764", "8801975838764").
String whatsappLink(String number, {String message = ''}) {
  var digits = number.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('0')) digits = '880${digits.substring(1)}';
  final text = message.isEmpty ? '' : '?text=${Uri.encodeComponent(message)}';
  return 'https://wa.me/$digits$text';
}

/// Policy/about texts are written with the shop's phone and email; this
/// shows the values currently in settings instead.
String withSettingsContacts(String text, AppSettings settings) {
  var out = text;
  if (settings.supportPhone.trim().isNotEmpty) {
    out = out.replaceAll('01975838764', settings.supportPhone.trim());
  }
  if (settings.email.trim().isNotEmpty) {
    out = out.replaceAll('chalakcharmart@gmail.com', settings.email.trim());
  }
  return out;
}

/// [Text] of a policy template with the contact details from settings.
class SettingsContactText extends StatelessWidget {
  const SettingsContactText(this.template, {super.key, this.style});

  final String template;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.watch(),
      initialData: AppSettingsService.cached,
      builder: (context, snap) => Text(
        withSettingsContacts(template, snap.data ?? AppSettingsService.cached),
        style: style,
      ),
    );
  }
}
