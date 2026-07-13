import 'package:flutter/material.dart';

class PermissionsPage extends StatelessWidget {
  const PermissionsPage({super.key});

  Widget _permissionItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2CB1DE), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        title: const Text("Permissions"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "We request only necessary permissions to provide better service.",
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),

          const SizedBox(height: 16),

          _permissionItem(
            icon: Icons.call,
            title: "Phone Permission",
            description:
            "Used to call customer support directly from the app when needed.",
          ),

          _permissionItem(
            icon: Icons.location_on,
            title: "Location Permission (Optional)",
            description:
            "Used to help provide accurate delivery services. You can still use the app without enabling this.",
          ),

          _permissionItem(
            icon: Icons.camera_alt,
            title: "Camera Permission",
            description:
            "Used to capture and upload list images for product orders.",
          ),

          _permissionItem(
            icon: Icons.photo_library,
            title: "Storage / Gallery",
            description:
            "Used to select list images from your device gallery.",
          ),

          _permissionItem(
            icon: Icons.notifications,
            title: "Notification",
            description:
            "Used to send updates about orders, delivery status, and important alerts.",
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              "We respect your privacy. All permissions are used only to improve your experience and are never misused.",
              style: TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        title: const Text("About Us"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          '''About ChalakChar Mart

ChalakChar Mart is a trusted online marketplace and e-commerce platform dedicated to providing safe, reliable, and convenient product ordering services.

We aim to make daily shopping easier by allowing customers to browse products, upload lists, and receive reliable order support from home.


Who We Are

ChalakChar Mart is based in Chalak Char Bazar, Monohardi, Narsingdi, Bangladesh.

We are committed to providing authentic products, reliable vendors, and helpful customer support with honesty and care.


Our Mission

Our mission is to make essential shopping accessible, affordable, and trustworthy for everyone.

We work to ensure:
1. Genuine and quality products
2. Easy product ordering
3. Reliable list support
4. Smooth customer experience
5. Helpful support through phone, WhatsApp and Messenger


What We Offer

1. Online product ordering
2. List upload system
3. Home delivery support
4. Customer support
5. Simple and user-friendly mobile and web experience


Our Commitment

We are committed to customer safety, product authenticity, privacy, and responsible marketplace service.

We always try to improve our service so that customers can get better support and a smooth shopping experience.


Contact Information

Address:
Chalak Char Bazar, Monohardi, Narsingdi, Bangladesh.

Phone:
01975838764

Email:
chalakcharmart@gmail.com


Thank you for choosing ChalakChar Mart.

We are always here to support your daily needs.''',
          style: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        title: const Text("Privacy Policy"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          '''ব্যবহারকারীর তথ্য সুরক্ষা

1. আপনার তথ্য আমাদের কাছে নিরাপদ থাকবে। আপনার সম্মতি ছাড়া আমরা আপনার ব্যক্তিগত তথ্য কারও সাথে শেয়ার করব না।

2. ব্যক্তিগত তথ্য: আপনার নাম, ফোন নম্বর, ঠিকানা, ইমেইল, অর্ডার তথ্য এবং অ্যাকাউন্ট সম্পর্কিত তথ্য নিরাপদে সংরক্ষণ করা হবে।

3. যোগাযোগের তথ্য: আপনার ফোন নম্বর ও যোগাযোগের তথ্য শুধুমাত্র অর্ডার কনফার্মেশন, ডেলিভারি এবং কাস্টমার সাপোর্টের জন্য ব্যবহার করা হবে।

4. লগইন তথ্য: আপনি ChalakChar Mart অ্যাপে লগইন করলে আপনার লগইন তথ্য নিরাপদ রাখা হবে।

5. তথ্য বিক্রি: ChalakChar Mart কখনোই আপনার ব্যক্তিগত তথ্য আপনার অনুমতি ছাড়া কোনো তৃতীয় পক্ষের কাছে বিক্রি বা বিতরণ করবে না।


যে তথ্য আমরা সংগ্রহ করতে পারি

আমরা আমাদের অ্যাপ ব্যবহার করার সময় আপনার কাছ থেকে কিছু প্রয়োজনীয় তথ্য সংগ্রহ করতে পারি, যেমন:

1. নাম
2. ফোন নম্বর
3. ইমেইল ঠিকানা
4. ডেলিভারি ঠিকানা
5. অর্ডার তথ্য
6. পেমেন্ট সম্পর্কিত তথ্য
7. ডিভাইস সম্পর্কিত সাধারণ তথ্য
8. অ্যাপ ব্যবহারের সাধারণ তথ্য

এই তথ্যগুলো ব্যবহার করা হবে আপনার অর্ডার গ্রহণ, অর্ডার প্রসেসিং, ডেলিভারি, পেমেন্ট যাচাই, কাস্টমার সাপোর্ট এবং আমাদের সার্ভিস উন্নত করার জন্য।


পণ্য সম্পর্কিত তথ্য

ChalakChar Mart অ্যাপে ব্যবহারকারী পণ্য, ব্যক্তিগত পরিচর্যা পণ্য এবং প্রয়োজনীয় প্রয়োজনীয় পণ্য অর্ডার করতে পারবেন।

যদি ব্যবহারকারী কোনো লিস্ট/ছবি আপলোড করেন, তাহলে সেটি শুধুমাত্র অর্ডার যাচাই এবং প্রয়োজনীয় পণ্য সরবরাহের উদ্দেশ্যে ব্যবহার করা হবে।

আমরা কোনো ভিডিও কল, অডিও কল বা অনলাইন সেবা প্রদানকারী পরামর্শ সেবা প্রদান করি না। ChalakChar Mart অ্যাপ কোনো সেবা প্রদানকারী কনসালটেশন প্ল্যাটফর্ম নয়।

জরুরি বা ঝুঁকিপূর্ণ পরিস্থিতিতে ব্যবহারকারীকে সংশ্লিষ্ট স্থানীয় কর্তৃপক্ষ বা যোগ্য পেশাজীবীর সাথে সরাসরি যোগাযোগ করার পরামর্শ দেওয়া হচ্ছে।


অর্ডার ও ডেলিভারি

ChalakChar Mart অ্যাপের মাধ্যমে ব্যবহারকারী প্রয়োজনীয় পণ্য অর্ডার করতে পারবেন। অর্ডার কনফার্ম করার জন্য আমাদের টিম প্রয়োজনে ব্যবহারকারীর সাথে ফোন বা মেসেজের মাধ্যমে যোগাযোগ করতে পারে।

ডেলিভারি ঠিকানা, ফোন নম্বর এবং অর্ডার তথ্য শুধুমাত্র অর্ডার সম্পন্ন করার জন্য ব্যবহার করা হবে।


লিস্ট/ছবি ব্যবহার

কিছু পণ্যের ক্ষেত্রে বৈধ লিস্ট/ছবি প্রয়োজন হতে পারে। ব্যবহারকারী যদি লিস্ট/ছবি আপলোড করেন, তাহলে সেটি শুধুমাত্র সংশ্লিষ্ট অর্ডার যাচাইয়ের জন্য ব্যবহার করা হবে।

ভুল, অসম্পূর্ণ বা অবৈধ লিস্ট/ছবিের ক্ষেত্রে ChalakChar Mart অর্ডার বাতিল করার অধিকার রাখে।


তথ্য সংরক্ষণ ও মুছে ফেলা

আপনি চাইলে আমাদের কাছে সংরক্ষিত আপনার ব্যক্তিগত তথ্য সম্পর্কে জানতে অনুরোধ করতে পারেন।

আপনি চাইলে আপনার ব্যক্তিগত তথ্য সম্পূর্ণ বা আংশিকভাবে মুছে ফেলার জন্য আমাদের সাথে যোগাযোগ করতে পারেন। তবে আইনগত, অর্ডার রেকর্ড, পেমেন্ট রেকর্ড বা নিরাপত্তাজনিত কারণে কিছু তথ্য নির্দিষ্ট সময় পর্যন্ত সংরক্ষণ করা হতে পারে।


অ-ব্যক্তিগত তথ্য

আমরা অ্যাপের কার্যকারিতা উন্নত করার জন্য কিছু অ-ব্যক্তিগত তথ্য সংগ্রহ করতে পারি, যেমন অ্যাপ ব্যবহারের ধরণ, ডিভাইসের ধরন, অ্যাপ ভার্সন এবং সাধারণ ব্যবহারের পরিসংখ্যান।

এই তথ্য ব্যবহারকারীর ব্যক্তিগত পরিচয় প্রকাশ করে না এবং শুধুমাত্র সার্ভিস উন্নত করার জন্য ব্যবহার করা হয়।


তৃতীয় পক্ষের সেবা

অর্ডার ডেলিভারি, পেমেন্ট প্রসেসিং বা অ্যাপের কার্যকারিতার জন্য কিছু নির্ভরযোগ্য তৃতীয় পক্ষের সেবা ব্যবহার করা হতে পারে। এসব ক্ষেত্রে শুধুমাত্র প্রয়োজনীয় তথ্য শেয়ার করা হবে।


ব্যবহারকারীর দায়িত্ব

আপনি ChalakChar Mart অ্যাপে যে তথ্য প্রদান করবেন তা সঠিক, সম্পূর্ণ এবং বর্তমান হওয়া উচিত।

ভুল তথ্য, ভুল ঠিকানা বা ভুল ফোন নম্বর দেওয়ার কারণে অর্ডার বিলম্বিত বা বাতিল হলে ChalakChar Mart দায়ী থাকবে না।


পণ্য তথ্য ও সতর্কতা

ChalakChar Mart অ্যাপে প্রদত্ত পণ্য সম্পর্কিত তথ্য সাধারণ তথ্য হিসেবে দেওয়া হয়। ক্রয়ের আগে পণ্যের লেবেল, নির্দেশনা, মূল্য এবং শর্ত ভালোভাবে যাচাই করা উচিত।

পণ্য ব্যবহারের আগে অবশ্যই সেবা প্রদানকারী বা যোগ্য পেশাজীবীের পরামর্শ নেওয়া উচিত।


নীতিমালার পরিবর্তন

ChalakChar Mart প্রয়োজনে এই গোপনীয়তা নীতিমালা পরিবর্তন বা আপডেট করতে পারে। কোনো পরিবর্তন হলে অ্যাপ বা ওয়েবসাইটের মাধ্যমে ব্যবহারকারীদের জানানো হবে।''',
          style: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        title: const Text("Terms & Conditions"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          '''শর্তাবলী

ChalakChar Mart মোবাইল অ্যাপ্লিকেশন ব্যবহার করার মাধ্যমে আপনি নিশ্চিত করছেন যে আপনি নিচে উল্লেখিত আমাদের শর্তাবলী ও নীতিমালা মেনে নিচ্ছেন। আপনি যদি এই শর্তাবলী মেনে নিতে না চান, তাহলে অনুগ্রহ করে অ্যাপ ব্যবহার করা বন্ধ করুন।

ChalakChar Mart একটি অনলাইন মার্কেটপ্লেস ও ই-কমার্স সেবা, যেখানে ব্যবহারকারীরা দৈনন্দিন প্রয়োজনীয় পণ্য, গ্রোসারি, গৃহস্থালি পণ্য এবং অন্যান্য অনুমোদিত পণ্য অর্ডার করতে পারবেন।

যোগাযোগ:
ফোন: 01975838764
ইমেইল: chalakcharmart@gmail.com


অর্ডার ও ডেলিভারি

ChalakChar Mart অ্যাপের মাধ্যমে ব্যবহারকারী প্রয়োজনীয় পণ্য অর্ডার করতে পারবেন।

অর্ডার কনফার্ম করার জন্য আমাদের টিম প্রয়োজনে ব্যবহারকারীর সাথে ফোন বা মেসেজের মাধ্যমে যোগাযোগ করতে পারে।

ডেলিভারি সময় এলাকা, পণ্য প্রাপ্যতা এবং কুরিয়ার/ডেলিভারি সার্ভিসের উপর নির্ভর করতে পারে।

ভুল ঠিকানা, ভুল ফোন নম্বর বা অসম্পূর্ণ তথ্যের কারণে অর্ডার বিলম্বিত বা বাতিল হলে ChalakChar Mart দায়ী থাকবে না।


পেমেন্ট নীতিমালা

ব্যবহারকারী ক্যাশ অন ডেলিভারি অথবা ChalakChar Mart কর্তৃক অনুমোদিত পেমেন্ট পদ্ধতির মাধ্যমে পেমেন্ট করতে পারবেন।

অগ্রিম পেমেন্টের ক্ষেত্রে কোনো কারণে অর্ডার বাতিল হলে যাচাই-বাছাইয়ের পর নির্ধারিত সময়ের মধ্যে টাকা ফেরত দেওয়া হবে।

পেমেন্ট সংক্রান্ত কোনো সমস্যার ক্ষেত্রে ব্যবহারকারী আমাদের কাস্টমার সাপোর্টে যোগাযোগ করতে পারবেন।


মূল্য ফেরত নীতিমালা

যদি কোনো অর্ডারের সম্পূর্ণ বা আংশিক অর্থ অগ্রিম পরিশোধ করা হয় এবং কোনো কারণে অর্ডার বাতিল হয়, তাহলে যাচাই-বাছাইয়ের পর ৭ কার্যদিবসের মধ্যে টাকা ফেরত দেওয়ার চেষ্টা করা হবে।

রিফান্ড ব্যবহারকারীর ব্যবহৃত পেমেন্ট মাধ্যম অথবা ChalakChar Mart কর্তৃক নির্ধারিত পদ্ধতিতে প্রদান করা হতে পারে।

ব্যাংক, মোবাইল ফাইন্যান্সিয়াল সার্ভিস বা পেমেন্ট গেটওয়ের কারণে রিফান্ড সম্পন্ন হতে অতিরিক্ত সময় লাগতে পারে।


পণ্য ফেরত ও বিনিময় নীতিমালা

যদি পণ্য ভুল, ক্ষতিগ্রস্ত বা অর্ডারকৃত পণ্যের সাথে মিল না থাকে, তাহলে ডেলিভারির পর দ্রুত আমাদের সাথে যোগাযোগ করতে হবে।

পণ্য বা ব্যক্তিগত পরিচর্যা পণ্য ফেরত/বিনিময়ের ক্ষেত্রে পণ্য অবশ্যই অক্ষত, অব্যবহৃত, সিলযুক্ত এবং মূল প্যাকেজিংসহ থাকতে হবে।

ব্যবহৃত স্ট্রিপ, খোলা বোতল, ক্ষতিগ্রস্ত প্যাকেট বা মেয়াদোত্তীর্ণ হওয়ার কাছাকাছি পণ্য ফেরত নেওয়া নাও হতে পারে।

ইনজেকশন, ইনসুলিন, ঠান্ডা সংরক্ষণযোগ্য পণ্য বা বিশেষ সংরক্ষণ প্রয়োজন এমন পণ্য নিরাপত্তাজনিত কারণে সাধারণত ফেরত নেওয়া হয় না।

লিস্ট/ছবি পরিবর্তনের কারণে পণ্য ফেরত বা বিনিময়ের প্রয়োজন হলে ChalakChar Mart পরিস্থিতি যাচাই করে সিদ্ধান্ত নেবে।


লিস্ট/ছবি নীতিমালা

কিছু পণ্যের ক্ষেত্রে বৈধ লিস্ট/ছবি প্রয়োজন হতে পারে।

ব্যবহারকারী যদি লিস্ট/ছবি আপলোড করেন, তাহলে সেটি শুধুমাত্র অর্ডার যাচাই এবং প্রয়োজনীয় পণ্য সরবরাহের উদ্দেশ্যে ব্যবহার করা হবে।

ভুল, অসম্পূর্ণ, অস্পষ্ট বা অবৈধ লিস্ট/ছবিের ক্ষেত্রে ChalakChar Mart অর্ডার বাতিল করার অধিকার রাখে।

ব্যবহারকারী লিস্ট/ছবি ছাড়া কোনো লিস্ট/ছবি-নির্ভর পণ্য অর্ডার করলে ChalakChar Mart সেই অর্ডার গ্রহণ না করার অধিকার রাখে।


পণ্য তথ্য ও সতর্কতা

ChalakChar Mart কোনো ভিডিও কল, অডিও কল বা অনলাইন সেবা প্রদানকারী পরামর্শ সেবা প্রদান করে না।

ChalakChar Mart অ্যাপে প্রদত্ত পণ্য সম্পর্কিত তথ্য সাধারণ তথ্য হিসেবে দেওয়া হয়। ক্রয়ের আগে পণ্যের লেবেল, নির্দেশনা, মূল্য এবং শর্ত ভালোভাবে যাচাই করা উচিত।

পণ্য ব্যবহারের আগে অবশ্যই নিবন্ধিত সেবা প্রদানকারী বা যোগ্য পেশাজীবীের পরামর্শ নেওয়া উচিত।

জরুরি বা ঝুঁকিপূর্ণ পরিস্থিতিতে সংশ্লিষ্ট স্থানীয় কর্তৃপক্ষ বা যোগ্য পেশাজীবীর সাথে সরাসরি যোগাযোগ করুন।


ব্যবহারকারীর দায়িত্ব

ব্যবহারকারী ChalakChar Mart অ্যাপে যে তথ্য প্রদান করবেন তা সঠিক, সম্পূর্ণ এবং বর্তমান হওয়া উচিত।

ভুল তথ্য, ভুল ঠিকানা, ভুল ফোন নম্বর বা মিথ্যা তথ্য প্রদানের কারণে অর্ডার বিলম্বিত, বাতিল বা ডেলিভারি ব্যর্থ হলে ChalakChar Mart দায়ী থাকবে না।

ব্যবহারকারী অ্যাপের কোনো সুবিধা, কুপন, রেফারেল বা অফার অপব্যবহার করতে পারবেন না।


রেফারেল নীতিমালা

ব্যবহারকারী নিজের নম্বর নিজে রেফার করতে পারবেন না।

রেফারেল সুবিধা শুধুমাত্র প্রকৃত নতুন ব্যবহারকারীর ক্ষেত্রে প্রযোজ্য হতে পারে।

রেফারেল কোডের অপব্যবহার, ভুয়া অ্যাকাউন্ট তৈরি বা অসদাচরণ পরিলক্ষিত হলে ChalakChar Mart রেফারেল সুবিধা বাতিল করার অধিকার রাখে।

ChalakChar Mart প্রয়োজন অনুযায়ী রেফারেল নীতিমালা পরিবর্তন, স্থগিত বা বাতিল করতে পারে।


অ্যাকাউন্ট ও নিরাপত্তা

ব্যবহারকারী নিজের অ্যাকাউন্টের তথ্য নিরাপদ রাখার জন্য দায়ী।

অন্যের অ্যাকাউন্ট ব্যবহার, ভুল তথ্য প্রদান বা প্রতারণামূলক কার্যক্রম নিষিদ্ধ।

নিয়ম ভঙ্গ করলে ChalakChar Mart ব্যবহারকারীর অ্যাকাউন্ট সাময়িক বা স্থায়ীভাবে বন্ধ করার অধিকার রাখে।


নীতিমালার পরিবর্তন

ChalakChar Mart প্রয়োজন অনুযায়ী এই শর্তাবলী পরিবর্তন, সংশোধন বা আপডেট করতে পারে।

কোনো পরিবর্তন হলে অ্যাপ বা ওয়েবসাইটের মাধ্যমে ব্যবহারকারীদের জানানো হতে পারে।

অ্যাপ ব্যবহার অব্যাহত রাখলে পরিবর্তিত শর্তাবলী ব্যবহারকারী মেনে নিয়েছেন বলে গণ্য হবে।''',
          style: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

class ReturnPolicyPage extends StatelessWidget {
  const ReturnPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        title: const Text("Return Policy"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          '''রিটার্ন ও রিফান্ড পলিসি

ChalakChar Mart থেকে অর্ডার করা পণ্য ফেরত, বিনিময় এবং রিফান্ডের ক্ষেত্রে নিচের নীতিমালা প্রযোজ্য হবে।


পণ্য ফেরত বা বিনিময়

যদি পণ্য ভুল, ক্ষতিগ্রস্ত, মেয়াদোত্তীর্ণ বা অর্ডারকৃত পণ্যের সাথে মিল না থাকে, তাহলে ডেলিভারির পর দ্রুত আমাদের কাস্টমার সাপোর্টে যোগাযোগ করুন।

ফেরত বা বিনিময়ের জন্য পণ্য অবশ্যই অক্ষত, অব্যবহৃত, সিলযুক্ত এবং মূল প্যাকেজিংসহ থাকতে হবে।

ব্যবহৃত স্ট্রিপ, খোলা বোতল, ছেঁড়া প্যাকেট, ক্ষতিগ্রস্ত প্যাকেজিং বা ব্যবহার করা পণ্য ফেরত নেওয়া হবে না।

নিরাপত্তা, হাইজিন বা প্যাকেজিং কারণে কিছু পণ্য ফেরত নেওয়া নাও হতে পারে।


যেসব পণ্য ফেরতযোগ্য নয়

নিচের পণ্যগুলো সাধারণত ফেরত নেওয়া হয় না:

1. ব্যবহৃত পণ্য বা খোলা স্ট্রিপ
2. খোলা বোতল বা খোলা প্যাকেট
3. ইনজেকশন, ইনসুলিন বা ঠান্ডা সংরক্ষণযোগ্য পণ্য
4. ব্যক্তিগত পরিচর্যা বা হাইজিন পণ্য
5. মেয়াদোত্তীর্ণ হওয়ার কাছাকাছি পণ্য
6. গ্রাহকের ভুল অর্ডার করা পণ্য, যদি পণ্য ইতোমধ্যে ডেলিভারি সম্পন্ন হয়


লিস্ট/ছবি পরিবর্তনের কারণে রিটার্ন

লিস্ট/ছবি পরিবর্তনের কারণে পণ্য ফেরত বা বিনিময়ের প্রয়োজন হলে ChalakChar Mart বিষয়টি যাচাই করে সিদ্ধান্ত নেবে।

এক্ষেত্রে পুরোনো এবং নতুন লিস্ট/ছবি দেখাতে হতে পারে।

সব ক্ষেত্রে রিটার্ন বা বিনিময় অনুমোদন ChalakChar Mart কর্তৃপক্ষের সিদ্ধান্তের উপর নির্ভর করবে।


ভুল বা ক্ষতিগ্রস্ত পণ্য

যদি ChalakChar Mart ভুল পণ্য পাঠায় বা পণ্য ক্ষতিগ্রস্ত অবস্থায় পৌঁছায়, তাহলে যাচাই-বাছাইয়ের পর পণ্য পরিবর্তন বা প্রয়োজনীয় সমাধান দেওয়া হবে।

এক্ষেত্রে ব্যবহারকারীকে পণ্যের ছবি, অর্ডার নম্বর এবং প্রয়োজনীয় তথ্য প্রদান করতে হতে পারে।


রিফান্ড পলিসি

যদি কোনো অর্ডারের সম্পূর্ণ বা আংশিক অর্থ অগ্রিম পরিশোধ করা হয় এবং কোনো কারণে অর্ডার বাতিল হয়, তাহলে যাচাই-বাছাইয়ের পর রিফান্ড প্রক্রিয়া শুরু করা হবে।

রিফান্ড সাধারণত ৭ কার্যদিবসের মধ্যে সম্পন্ন করার চেষ্টা করা হবে।

ব্যাংক, মোবাইল ফাইন্যান্সিয়াল সার্ভিস বা পেমেন্ট গেটওয়ের কারণে রিফান্ড সম্পন্ন হতে অতিরিক্ত সময় লাগতে পারে।

রিফান্ড ব্যবহারকারীর ব্যবহৃত পেমেন্ট মাধ্যম অথবা ChalakChar Mart কর্তৃক নির্ধারিত পদ্ধতিতে প্রদান করা হতে পারে।


ক্যাশ অন ডেলিভারি অর্ডার

ক্যাশ অন ডেলিভারি অর্ডারের ক্ষেত্রে অর্ডার গ্রহণের আগে পণ্য যাচাই করার অনুরোধ করা হচ্ছে।

পণ্য গ্রহণের পর রিটার্নের ক্ষেত্রে পণ্যের অবস্থা এবং নীতিমালা অনুযায়ী সিদ্ধান্ত নেওয়া হবে।


অর্ডার বাতিল

অর্ডার প্রসেসিং বা ডেলিভারির আগে ব্যবহারকারী অর্ডার বাতিলের অনুরোধ করতে পারেন।

যদি অর্ডার ইতোমধ্যে ডেলিভারির জন্য পাঠানো হয়ে থাকে, তাহলে বাতিল করা নাও যেতে পারে।

ChalakChar Mart পণ্য প্রাপ্যতা, লিস্ট/ছবি সমস্যা, ভুল তথ্য বা নিরাপত্তাজনিত কারণে যেকোনো অর্ডার বাতিল করার অধিকার রাখে।


যোগাযোগ

রিটার্ন, বিনিময় বা রিফান্ড সংক্রান্ত যেকোনো সহায়তার জন্য আমাদের সাথে যোগাযোগ করুন।

ফোন: 01975838764
ইমেইল: chalakcharmart@gmail.com


নীতিমালার পরিবর্তন

ChalakChar Mart প্রয়োজন অনুযায়ী এই Return Policy পরিবর্তন বা আপডেট করতে পারে। কোনো পরিবর্তন হলে অ্যাপ বা ওয়েবসাইটের মাধ্যমে ব্যবহারকারীদের জানানো হবে।''',
          style: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

