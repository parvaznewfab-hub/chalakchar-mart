// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void setRecaptchaVisible(bool visible) {
  html.document.getElementById('recaptcha-container')?.style.display =
  visible ? 'block' : 'none';
}





