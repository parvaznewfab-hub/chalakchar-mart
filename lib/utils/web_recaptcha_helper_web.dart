import 'dart:html' as html;

void setRecaptchaVisible(bool visible) {
  html.document.getElementById('recaptcha-container')?.style.display =
  visible ? 'block' : 'none';
}


