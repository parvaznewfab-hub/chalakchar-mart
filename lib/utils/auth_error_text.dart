/// Plain Bangla text for login errors. Customers never see raw English
/// errors ("Exception: ...", Firebase messages); every login path maps the
/// error code through here.
library;

const String accountExistsBn =
    'এই ইমেইলে আগে থেকে অ্যাকাউন্ট আছে।';

/// Readable name of a Firebase sign-in provider id.
String providerNameBn(String providerId) {
  switch (providerId) {
    case 'google.com':
      return 'Google';
    case 'facebook.com':
      return 'Facebook';
    case 'phone':
      return 'ফোন OTP';
    case 'password':
      return 'ইমেইল ও পাসওয়ার্ড';
    default:
      return providerId;
  }
}

/// [code]: FirebaseAuthException.code (without "auth/"), or one of the
/// app's own codes ('timeout', 'invalid-phone-format', 'otp-length').
String authErrorBn(String code) {
  switch (code) {
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
    case 'user-cancelled':
    case 'web-context-canceled':
    case 'web-context-cancelled':
      return 'লগইন উইন্ডো বন্ধ হয়ে গেছে। আবার চেষ্টা করুন।';
    case 'popup-blocked':
      return 'ব্রাউজার লগইন উইন্ডো আটকে দিয়েছে। popup চালু করে আবার চেষ্টা করুন।';
    case 'network-request-failed':
    case 'timeout':
      return 'ইন্টারনেট সংযোগ পাওয়া যাচ্ছে না। নেট চেক করে আবার চেষ্টা করুন।';
    case 'invalid-phone-number':
    case 'invalid-phone-format':
    case 'missing-phone-number':
      return 'মোবাইল নম্বরটি সঠিক নয়। 01XXXXXXXXX আকারে ১১ সংখ্যার নম্বর লিখুন।';
    case 'invalid-verification-code':
    case 'missing-verification-code':
      return 'OTP সঠিক নয়। SMS-এ পাওয়া ৬ সংখ্যার কোডটি আবার লিখুন।';
    case 'otp-length':
      return '৬ সংখ্যার OTP লিখুন।';
    case 'session-expired':
    case 'code-expired':
    case 'invalid-verification-id':
      return 'OTP-র মেয়াদ শেষ হয়ে গেছে। নতুন OTP পাঠান।';
    case 'too-many-requests':
    case 'quota-exceeded':
      return 'অনেকবার চেষ্টা করা হয়েছে। কয়েক মিনিট পরে আবার চেষ্টা করুন।';
    case 'captcha-check-failed':
    case 'invalid-app-credential':
    case 'missing-app-credential':
      return 'যাচাই করা যায়নি। পেজ রিলোড করে আবার চেষ্টা করুন।';
    case 'account-exists-with-different-credential':
    case 'email-already-in-use':
      return '$accountExistsBn আগের পদ্ধতিতে লগইন করুন।';
    case 'credential-already-in-use':
      return 'এই লগইনটি অন্য একটি অ্যাকাউন্টের সাথে যুক্ত। যে পদ্ধতিতে সেই অ্যাকাউন্ট খুলেছিলেন সেটা দিয়ে লগইন করুন।';
    case 'user-disabled':
      return 'এই অ্যাকাউন্টটি বন্ধ করা আছে। সাহায্যের জন্য আমাদের সাথে যোগাযোগ করুন।';
    case 'provider-already-linked':
      return 'এই লগইন পদ্ধতি আগেই আপনার অ্যাকাউন্টে যুক্ত আছে।';
    default:
      return 'লগইন করা যায়নি। একটু পরে আবার চেষ্টা করুন।';
  }
}
