import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle, SystemChrome, SystemUiOverlayStyle, SystemNavigator, HapticFeedback;
import 'package:google_nav_bar/google_nav_bar.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
  ));
  runApp(const MyApp());
}

// બટન માટેનું સ્ટ્રક્ચર
class SmartButton {
  final String title;
  final IconData icon;
  final String keyword; // વેબસાઈટમાં શોધવા માટેનો શબ્દ
  String? detectedUrl;

  SmartButton({required this.title, required this.icon, required this.keyword, this.detectedUrl});
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebFlow Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, primaryColor: const Color(0xFF6366F1)),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/home': (context) => const MainScreen(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () => Navigator.pushReplacementNamed(context, '/home'));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6366F1),
      body: Center(child: Image.asset('assets/images/logo.png', width: 150)),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  String? mainUrl;
  
  // આખા લિસ્ટમાંથી જે કામના હશે તે જ બતાવીશું
  List<SmartButton> allPossibleButtons = [
    SmartButton(title: "Home", icon: Icons.home_rounded, keyword: "home"),
    SmartButton(title: "Shop", icon: Icons.shopping_bag_rounded, keyword: "shop"),
    SmartButton(title: "Cart", icon: Icons.shopping_cart_rounded, keyword: "cart"),
    SmartButton(title: "Profile", icon: Icons.person_rounded, keyword: "account"),
    SmartButton(title: "Search", icon: Icons.search_rounded, keyword: "search"),
    SmartButton(title: "Contact", icon: Icons.contact_support_rounded, keyword: "contact"),
  ];

  List<SmartButton> visibleButtons = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => _injectCleaner(),
        onPageFinished: (url) {
          setState(() => isLoading = false);
          _injectCleaner();
          _scanWebsiteForButtons();
        },
      ));
    _loadUrl();
  }

  void _injectCleaner() {
    // સાઈટનું મેનુ છુપાવવા માટે
    controller.runJavaScript("""
      (function() {
        var css = 'header, nav, footer, .header, .navbar, .mobile-menu, #header, #navigation { display: none !important; } body { padding-top: 0 !important; margin-top: 0 !important; }';
        var style = document.createElement('style');
        style.innerHTML = css;
        document.head.appendChild(style);
      })();
    """);
  }

  void _scanWebsiteForButtons() async {
    const String scanJs = """
      (function() {
        var results = {};
        var links = document.querySelectorAll('a');
        var keywords = ['home', 'shop', 'cart', 'account', 'search', 'contact', 'about', 'login'];
        
        links.forEach(function(link) {
          var text = link.innerText.toLowerCase();
          var href = link.href.toLowerCase();
          
          keywords.forEach(function(k) {
            if ((text.includes(k) || href.includes(k)) && !results[k]) {
              results[k] = link.href;
            }
          });
        });
        return JSON.stringify(results);
      })();
    """;

    var result = await controller.runJavaScriptReturningResult(scanJs);
    if (result != null && result.toString() != "{}") {
      Map<String, dynamic> detected = jsonDecode(result.toString().replaceAll('\\"', '"').replaceAll('^"', '').replaceAll('"\$', ''));
      
      List<SmartButton> found = [];
      // હંમેશા હોમ બટન તો રાખવું જ
      found.add(allPossibleButtons[0]..detectedUrl = mainUrl);

      for (var btn in allPossibleButtons) {
        if (detected.containsKey(btn.keyword)) {
          btn.detectedUrl = detected[btn.keyword];
          if (!found.contains(btn)) found.add(btn);
        }
      }

      setState(() {
        visibleButtons = found.take(4).toList(); // મહત્તમ 4 બટન બતાવવા
      });
    } else {
      // જો કંઈ ના મળે તો ડિફોલ્ટ હોમ બતાવવું
      setState(() {
        visibleButtons = [allPossibleButtons[0]..detectedUrl = mainUrl];
      });
    }
  }

  _loadUrl() async {
    String fileContent = await rootBundle.loadString('assets/url.txt');
    mainUrl = fileContent.trim();
    if (mainUrl != null) {
      if (!mainUrl!.startsWith('http')) mainUrl = 'https://$mainUrl';
      controller.loadRequest(Uri.parse(mainUrl!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await controller.canGoBack()) {
          controller.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 60,
          leading: Padding(padding: const EdgeInsets.all(12.0), child: Image.asset('assets/images/logo.png')),
          title: const Text("WEBFLOW PRO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => controller.reload()),
            const SizedBox(width: 10),
          ],
        ),
        body: Stack(
          children: [
            if (mainUrl != null) WebViewWidget(controller: controller),
            if (isLoading) Container(color: Colors.white, child: const Center(child: CircularProgressIndicator())),
          ],
        ),
        bottomNavigationBar: visibleButtons.length > 1 ? Container(
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              child: GNav(
                gap: 8,
                activeColor: const Color(0xFF6366F1),
                iconSize: 24,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                tabBackgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                color: Colors.grey,
                tabs: visibleButtons.map((btn) => GButton(icon: btn.icon, text: btn.title)).toList(),
                selectedIndex: _selectedIndex,
                onTabChange: (index) {
                  setState(() => _selectedIndex = index);
                  HapticFeedback.lightImpact();
                  if (visibleButtons[index].detectedUrl != null) {
                    controller.loadRequest(Uri.parse(visibleButtons[index].detectedUrl!));
                  }
                },
              ),
            ),
          ),
        ) : null,
      ),
    );
  }
}