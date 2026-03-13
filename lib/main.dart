import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: WebViewApp()));
}

class WebViewApp extends StatefulWidget {
  const WebViewApp({super.key});
  @override
  State<WebViewApp> createState() => _WebViewAppState();
}

class _WebViewAppState extends State<WebViewApp> {
  late final WebViewController controller;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) => setState(() => isLoading = false),
      ));
    _loadUrl();
  }

  _loadUrl() async {
    try {
      String url = await rootBundle.loadString('assets/url.txt');
      url = url.trim();
      // જો લિંક ખાલી ન હોય તો જ લોડ કરવી
      if (url.isNotEmpty) {
        // જો લિંકમાં http કે https ન હોય તો ઉમેરો
        if (!url.startsWith('http')) {
          url = 'https://$url';
        }
        controller.loadRequest(Uri.parse(url));
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}