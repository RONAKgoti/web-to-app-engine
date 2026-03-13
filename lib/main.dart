import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: WebViewApp(),
  ));
}

class WebViewApp extends StatefulWidget {
  const WebViewApp({super.key});
  @override
  State<WebViewApp> createState() => _WebViewAppState();
}

class _WebViewAppState extends State<WebViewApp> {
  late final WebViewController controller;
  bool isLoading = true;
  String? url;

  @override
  void initState() {
    super.initState();
    // ૧. પહેલા કંટ્રોલર સેટ કરો
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000)) // ટ્રાન્સપરન્ટ બેકગ્રાઉન્ડ
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() { isLoading = false; });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint("WebView Error: ${error.description}");
          },
        ),
      );

    // ૨. URL લોડ કરો
    _loadUrl();
  }

  _loadUrl() async {
    try {
      // assets માંથી URL વાંચશે
      String fileContent = await rootBundle.loadString('assets/url.txt');
      String finalUrl = fileContent.trim();

      if (finalUrl.isNotEmpty) {
        // જો લિંકમાં http ન હોય તો ઉમેરો
        if (!finalUrl.startsWith('http')) {
          finalUrl = 'https://$finalUrl';
        }
        setState(() { url = finalUrl; });
        controller.loadRequest(Uri.parse(finalUrl));
      } else {
        setState(() { isLoading = false; });
      }
    } catch (e) {
      setState(() { isLoading = false; });
      debugPrint("Error loading URL: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // બ્લેક સ્ક્રીન રોકવા માટે વ્હાઈટ બેકગ્રાઉન્ડ
      body: SafeArea(
        child: Stack(
          children: [
            // જો URL મળી જાય તો જ WebView બતાવો
            if (url != null)
              WebViewWidget(controller: controller),

            // લોડિંગ બતાવો
            if (isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.blue),
              ),

            // જો URL લોડ ન થાય તો મેસેજ બતાવો
            if (!isLoading && url == null)
              const Center(child: Text("Invalid URL or File missing")),
          ],
        ),
      ),
    );
  }
}