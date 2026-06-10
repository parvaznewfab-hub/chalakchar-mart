import 'package:flutter/material.dart';

class ConnectAccountPage extends StatelessWidget {
  const ConnectAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Connect Account")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.account_circle, size: 80, color: Colors.blue),
          SizedBox(height: 30),
          ListTile(
            leading: Icon(Icons.phone, color: Colors.blue),
            title: Text("মোবাইল নাম্বার কানেক্ট করুন"),
          ),
          ListTile(
            leading: Icon(Icons.facebook, color: Colors.blue),
            title: Text("ফেসবুক কানেক্ট করুন"),
          ),
        ],
      ),
    );
  }
}



