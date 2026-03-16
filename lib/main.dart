import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle, SystemChrome, SystemUiOverlayStyle, SystemNavigator, HapticFeedback;
import 'package:google_nav_bar/google_nav_bar.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

// માસ્ટર બટન મોડેલ
class AppModule {
  final String id;
  final String title;
  final IconData icon;
  final List<String> keywords;
  String? url;

  AppModule({required this.id, required this.title, required this.icon, required this.keywords, this.url});
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Color themeColor = const Color(0xFF6366F1); // Default

  void updateColor(Color color) {
    setState(() => themeColor = color);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebFlow AI Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: themeColor,
        colorScheme: ColorScheme.fromSeed(seedColor: themeColor, primary: themeColor),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/home': (context) => MainScreen(onThemeUpdate: updateColor),
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
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', width: 140),
            const SizedBox(height: 20),
            const CircularProgressIndicator(strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final Function(Color) onThemeUpdate;
  const MainScreen({super.key, required this.onThemeUpdate});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  String? mainUrl;
  int _selectedIndex = 0;

  // ૧. માસ્ટર લિબ્લ્રેરી (બધા જ બટનો અહીં છે)
  final List<AppModule> masterModules = [
    AppModule(id: 'home', title: "Home", icon: Icons.home_rounded, keywords: ['home', 'index']),
    AppModule(id: 'shop', title: "Shop", icon: Icons.shopping_bag_rounded, keywords: ['shop', 'store', 'product', 'items']),
    AppModule(id: 'cart', title: "Cart", icon: Icons.shopping_cart_rounded, keywords: ['cart', 'checkout', 'basket']),
    AppModule(id: 'profile', title: "Account", icon: Icons.person_rounded, keywords: ['account', 'profile', 'login', 'user']),
    AppModule(id: 'services', title: "Services", icon: Icons.miscellaneous_services_rounded, keywords: ['service', 'work', 'solution']),
    AppModule(id: 'news', title: "News", icon: Icons.article_rounded, keywords: ['news', 'blog', 'article', 'update']),
    AppModule(id: 'search', title: "Search", icon: Icons.search_rounded, keywords: ['search', 'find']),
    AppModule(id: 'contact', title: "Contact", icon: Icons.contact_support_rounded, keywords: ['contact', 'support', 'help', 'email']),
  ];

  List<AppModule> activeModules = [];

  @override
  void initState() {
    super.initState();
    // શરૂઆતમાં ફક્ત હોમ બતાવવું
    activeModules = [masterModules[0]];
    
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => _injectAggressiveCleaner(),
        onPageFinished: (url) {
          setState(() => isLoading = false);
          _injectAggressiveCleaner();
          _smartAnalyzeWebsite(); // સાઈટ સ્કેન કરશે
        },
      ));
    _loadUrlFromAssets();
  }

  // ૨. એગ્રેસિવ ક્લીનર (સાઈટનું મેનુ હટાવવા)
  void _injectAggressiveCleaner() {
    controller.runJavaScript("""
      (function() {
        var css = 'header, nav, footer, .header, .navbar, .mobile-header, #header, #navigation, .elementor-location-header, .burger, .menu-toggle { display: none !important; height: 0 !important; opacity: 0 !important; pointer-events: none !important; } body { padding-top: 0 !important; margin-top: 0 !important; }';
        var style = document.createElement('style');
        style.innerHTML = css;
        document.head.appendChild(style);
      })();
    """);
  }

  // ૩. SMART MAPPING ENGINE (સાઈટ મુજબ બટનો શોધવા અને થીમ મેચ કરવી)
  void _smartAnalyzeWebsite() async {
    const String analysisJs = """
      (function() {
        var results = {};
        var links = document.querySelectorAll('a');
        
        // ૧. લિંક્સ અને બટનો સ્કેન કરવા
        links.forEach(function(l) {
          var t = l.innerText.toLowerCase().trim();
          var h = l.href.toLowerCase();
          
          if ((t.includes('shop') || h.includes('shop')) && !results['shop']) results['shop'] = l.href;
          if ((t.includes('cart') || h.includes('cart')) && !results['cart']) results['cart'] = l.href;
          if ((t.includes('account') || h.includes('account') || t.includes('login')) && !results['profile']) results['profile'] = l.href;
          if ((t.includes('service') || h.includes('service')) && !results['services']) results['services'] = l.href;
          if ((t.includes('blog') || h.includes('blog') || t.includes('news')) && !results['news']) results['news'] = l.href;
          if ((t.includes('search') || h.includes('search')) && !results['search']) results['search'] = l.href;
          if ((t.includes('contact') || h.includes('contact')) && !results['contact']) results['contact'] = l.href;
        });

        // ૨. થીમ કલર શોધવો (સૌથી વધુ વપરાયેલો પ્રાઈમરી કલર)
        var bodyColor = window.getComputedStyle(document.body).backgroundColor;
        var primaryBtn = document.querySelector('button, .btn, .primary');
        var themeHex = '#6366F1'; 
        if(primaryBtn) {
           var rgb = window.getComputedStyle(primaryBtn).backgroundColor;
           themeHex = rgb; 
        }

        return JSON.stringify({links: results, color: themeHex});
      })();
    """;

    try {
      var result = await controller.runJavaScriptReturningResult(analysisJs);
      var data = jsonDecode(result.toString().replaceAll('\\"', '"').replaceAll('^"', '').replaceAll('"\$', ''));
      
      Map<String, dynamic> detectedLinks = data['links'];
      
      List<AppModule> detectedModules = [masterModules[0]..url = mainUrl]; // Home always first

      for (var module in masterModules.skip(1)) {
        if (detectedLinks.containsKey(module.id)) {
          module.url = detectedLinks[module.id];
          detectedModules.add(module);
        }
      }

      // જો કંઈ ના મળે તો ડિફોલ્ટ ૩ બટન આપવા
      if (detectedModules.length < 3) {
        detectedModules = [masterModules[0], masterModules[4], masterModules[7]];
      }

      setState(() {
        activeModules = detectedModules.take(5).toList(); // મહત્તમ ૫ બટન
      });

      // થીમ કલર અપડેટ (જો વેલિડ હોય તો)
      if (data['color'].toString().contains('rgb')) {
        // Simple RGB to Color logic could be added here if needed, for now indigo is safe
      }
    } catch (e) {
      debugPrint("Analysis Error: $e");
    }
  }

  _loadUrlFromAssets() async {
    String fileContent = await rootBundle.loadString('assets/url.txt');
    mainUrl = fileContent.trim();
    if (mainUrl != null) {
      if (!mainUrl!.startsWith('http')) mainUrl = 'https://$mainUrl';
      masterModules[0].url = mainUrl; // Set Home URL
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
            IconButton(icon: const Icon(Icons.refresh_rounded, size: 22), onPressed: () => controller.reload()),
            const SizedBox(width: 5),
          ],
        ),
        body: Stack(
          children: [
            if (mainUrl != null) WebViewWidget(controller: controller),
            if (isLoading) Container(color: Colors.white, child: const Center(child: CircularProgressIndicator())),
          ],
        ),
        bottomNavigationBar: activeModules.length > 1 ? Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: GNav(
                gap: 6,
                activeColor: Theme.of(context).primaryColor,
                iconSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                duration: const Duration(milliseconds: 400),
                tabBackgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                color: Colors.grey[600],
                tabs: activeModules.map((m) => GButton(icon: m.icon, text: m.title)).toList(),
                selectedIndex: _selectedIndex,
                onTabChange: (index) {
                  setState(() => _selectedIndex = index);
                  HapticFeedback.lightImpact();
                  if (activeModules[index].url != null) {
                    controller.loadRequest(Uri.parse(activeModules[index].url!));
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