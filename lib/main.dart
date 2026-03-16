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

// બટન મોડેલ
class SmartModule {
  final String id;
  final String label;
  final IconData icon;
  String? url;

  SmartModule({required this.id, required this.label, required this.icon, this.url});
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebFlow Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF6366F1),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
      ),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo.png', width: 140),
              const SizedBox(height: 40),
              const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ],
          ),
        ),
      ),
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
  int _selectedIndex = 0;

  // બધા જ સંભવિત બટનોની લિબ્રેરી
  final List<SmartModule> masterLibrary = [
    SmartModule(id: 'home', label: "Home", icon: Icons.home_rounded),
    SmartModule(id: 'shop', label: "Shop", icon: Icons.shopping_bag_rounded),
    SmartModule(id: 'cart', label: "Cart", icon: Icons.shopping_cart_rounded),
    SmartModule(id: 'service', label: "Services", icon: Icons.miscellaneous_services_rounded),
    SmartModule(id: 'account', label: "Account", icon: Icons.person_rounded),
    SmartModule(id: 'contact', label: "Help", icon: Icons.contact_support_rounded),
  ];

  List<SmartModule> visibleTabs = [];

  @override
  void initState() {
    super.initState();
    // શરૂઆતમાં હોમ બટન તો રાખવું જ
    visibleTabs = [masterLibrary[0]];
    
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => _injectCleaner(),
        onPageFinished: (url) {
          setState(() => isLoading = false);
          _injectCleaner();
          _smartMapWebsite(); // ફુલ્લી ઓટોમેટિક સ્કેનર
        },
      ));
    _loadBaseUrl();
  }

  void _injectCleaner() {
    controller.runJavaScript("""
      (function() {
        var css = 'header, nav, footer, .header, .navbar, .mobile-header, #header, #navigation, .sticky-header, .burger-menu { display: none !important; } body { padding-top: 0 !important; margin-top: 0 !important; }';
        var style = document.createElement('style');
        style.innerHTML = css;
        document.head.appendChild(style);
      })();
    """);
  }

  void _smartMapWebsite() async {
    const String scanJs = """
      (function() {
        var map = {};
        var links = document.querySelectorAll('a');
        links.forEach(function(a) {
          var t = a.innerText.toLowerCase().trim();
          var h = a.href.toLowerCase();
          if ((t.includes('shop') || h.includes('shop')) && !map['shop']) map['shop'] = a.href;
          if ((t.includes('cart') || h.includes('cart') || h.includes('checkout')) && !map['cart']) map['cart'] = a.href;
          if ((t.includes('service') || h.includes('service')) && !map['service']) map['service'] = a.href;
          if ((t.includes('account') || h.includes('profile') || h.includes('login')) && !map['account']) map['account'] = a.href;
          if ((t.includes('contact') || h.includes('help') || t.includes('contact-us')) && !map['contact']) map['contact'] = a.href;
        });
        return JSON.stringify(map);
      })();
    """;

    try {
      var result = await controller.runJavaScriptReturningResult(scanJs);
      Map<String, dynamic> detected = jsonDecode(result.toString().replaceAll('\\"', '"').replaceAll('^"', '').replaceAll('"\$', ''));
      
      List<SmartModule> found = [masterLibrary[0]..url = mainUrl]; // Home always

      for (var mod in masterLibrary.skip(1)) {
        if (detected.containsKey(mod.id)) {
          mod.url = detected[mod.id];
          found.add(mod);
        }
      }

      // જો વેબસાઈટમાં કંઈ ના મળે તો ડિફોલ્ટ હોમ, સર્વિસ અને હેલ્પ બતાવો (જેથી ડમી ના લાગે)
      if (found.length < 3) {
        found = [
          masterLibrary[0]..url = mainUrl,
          masterLibrary[3]..url = "$mainUrl/services", // Logical guess
          masterLibrary[5]..url = "$mainUrl/contact",  // Logical guess
        ];
      }

      setState(() {
        visibleTabs = found.take(4).toList(); // Max 4 for best UI
      });
    } catch (e) {
       debugPrint("Mapping error: $e");
    }
  }

  _loadBaseUrl() async {
    String content = await rootBundle.loadString('assets/url.txt');
    mainUrl = content.trim();
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
          toolbarHeight: 65,
          leading: Padding(padding: const EdgeInsets.all(12.0), child: Image.asset('assets/images/logo.png')),
          title: const Text("WEBFLOW AI PRO", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => controller.reload()),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            if (mainUrl != null) WebViewWidget(controller: controller),
            if (isLoading) Container(color: Colors.white, child: const Center(child: CircularProgressIndicator())),
          ],
        ),
        bottomNavigationBar: (visibleTabs.length > 1) ? Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: GNav(
                gap: 8,
                activeColor: const Color(0xFF6366F1),
                iconSize: 24,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                tabBackgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                color: Colors.grey[600],
                tabs: visibleTabs.map((t) => GButton(icon: t.icon, text: t.label)).toList(),
                selectedIndex: _selectedIndex,
                onTabChange: (index) {
                  setState(() => _selectedIndex = index);
                  HapticFeedback.lightImpact(); // Professional touch feedback
                  if (visibleTabs[index].url != null) {
                    controller.loadRequest(Uri.parse(visibleTabs[index].url!));
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