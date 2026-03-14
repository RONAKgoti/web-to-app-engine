import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // સ્ટેટસ બાર ગાયબ
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: AmazonLookApp()));
}

class AmazonLookApp extends StatefulWidget {
  const AmazonLookApp({super.key});
  @override
  State<AmazonLookApp> createState() => _AmazonLookAppState();
}

class _AmazonLookAppState extends State<AmazonLookApp> {
  late final WebViewController controller;
  bool isLoading = true;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => setState(() => isLoading = true),
        onPageFinished: (url) {
          setState(() => isLoading = false);
          // આ જાદુઈ લાઈન ૩ નંબરના ફોટા જેવો લુક લાવશે (વેબસાઈટનું બધું સંતાડી દેશે)
          _hideWebHeaderAndFooter();
        },
      ))
      ..loadRequest(Uri.parse("https://www.amazon.in"));
  }

  // વેબસાઈટના હેડર/સર્ચ બારને છુપાવવાનું ફંક્શન
  void _hideWebHeaderAndFooter() {
    controller.runJavaScript("""
      // Amazon નું પોતાનું હેડર અને સર્ચ બાર સંતાડો
      document.getElementById('nav-logobar').style.display='none';
      document.getElementById('nav-search-keywords').parentElement.style.display='none';
      document.querySelector('header').style.display='none';
      document.getElementById('nav-ftr').style.display='none';
    """);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      // ૧. ઉપરનું નેટિવ સર્ચ બાર (ફોટો ૩ જેવો લુક)
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF84D8E3), Color(0xFFA6E6CE)],
                begin: Alignment.centerLeft, end: Alignment.centerRight,
              ),
            ),
          ),
          title: Container(
            height: 45,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: const TextField(
              decoration: InputDecoration(
                hintText: "Search Amazon.in",
                prefixIcon: Icon(Icons.search, color: Colors.black),
                suffixIcon: Icon(Icons.center_focus_weak, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
      ),

      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading) const Center(child: CircularProgressIndicator(color: Colors.orange)),
        ],
      ),

      // ૨. ૩ નંબરના ફોટા જેવું પ્રોપર બોટમ નેવિગેશન
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF007185),
        unselectedItemColor: Colors.black87,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "You"),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), label: "Wallet"),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), label: "Cart"),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: "Menu"),
        ],
      ),
    );
  }
}