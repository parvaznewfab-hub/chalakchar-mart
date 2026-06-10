import 'package:flutter/material.dart';
import '../widgets/global_web_header.dart';
import '../widgets/global_web_footer.dart';

class WebMainLayout extends StatelessWidget {
  final Widget child;
  final Widget? drawer;

  const WebMainLayout({
    super.key,
    required this.child,
    this.drawer,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: drawer,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const GlobalWebHeader(),
            child,
            const GlobalWebFooter(),
          ],
        ),
      ),
    );
  }
}


