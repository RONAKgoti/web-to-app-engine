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
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const MyApp());
}

class AppModule {
  final String id;
  final String title;
  final IconData icon;
  final String keyword;
  String? url;

  AppModule({required this.id, required this.title, required this.icon, required this.keyword, this.url});
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Color primaryColor = const Color(0xFF6366F1); // Modern Indigo

  void updateThemeColor(Color color) {
    setState(() => primaryColor = color);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebFlow Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: primaryColor,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor, primary: primaryColor),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/home': (context) => MainScreen(onThemeChange: updateThemeColor),
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
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Hero(tag: 'appLogo', child: Image.asset('assets/images/logo.png', width: 150)),
            const SizedBox(height: 30),
            const CircularProgressIndicator(strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final Function(Color) onThemeChange;
  const MainScreen({super.key, required this.onThemeChange});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  String? mainUrl;
  int _selectedIndex = 0;

  // ૧. માસ્ટર લિબ્લ્રેરી - બધા જ સંભવિત બટનો
  final List<AppModule> masterList = [
    AppModule(id: 'home', title: "Home", icon: Icons.home_rounded, keyword: 'home'),
    AppModule(id: 'shop', title: "Store", icon: Icons.shopping_bag_rounded, keyword: 'shop'),
    AppModule(id: 'cart', title: "Cart", icon: Icons.shopping_cart_rounded, keyword: 'cart'),
    AppModule(id: 'profile', title: "User", icon: Icons.person_rounded, keyword: 'account'),
    AppModule(id: 'service', title: "Works", icon: Icons.work_rounded, keyword: 'service'),
    AppModule(id: 'contact', title: "Help", icon: Icons.contact_support_rounded, keyword: 'contact'),
  ];

  List<AppModule> currentModules = [];

  @override
  void initState() {
    super.initState();
    // શરૂઆતમાં ૩ મેઈન બટનો હંમેશા દેખાશે (Ensures touchability from start)
    currentModules = [masterList[0], masterList[4], masterList[5]];
    
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => _injectCleaner(),
        onPageFinished: (url) {
          setState(() => isLoading = false);
          _injectCleaner();
          _runSmartMapping();
        },
      ));
    _loadUrl();
  }

  void _injectCleaner() {
    // સાઈટના હેડર/મેનુ છુપાવવા માટે (Immediate Effect)
    controller.runJavaScript("""
      (function() {
        var css = 'header, nav, footer, .header, .navbar, .mobile-header, #header, #navigation, .elementor-location-header, .sticky-header { display: none !important; } body { padding-top: 0 !important; margin-top: 0 !important; }';
        var style = document.createElement('style');
        style.innerHTML = css;
        document.head.appendChild(style);
      })();
    """);
  }

  void _runSmartMapping() async {
    const String mappingJs = """
      (function() {
        var data = {};
        var tags = document.querySelectorAll('a');
        tags.forEach(function(a) {
          var t = a.innerText.toLowerCase();
          var h = a.href.toLowerCase();
          if ((t.includes('shop') || h.includes('shop')) && !data['shop']) data['shop'] = a.href;
          if ((t.includes('cart') || h.includes('cart')) && !data['cart']) data['cart'] = a.href;
          if ((t.includes('account') || h.includes('account') || t.includes('login')) && !data['profile']) data['profile'] = a.href;
          if ((t.includes('service') || h.includes('service')) && !data['service']) data['service'] = a.href;
          if ((t.includes('contact') || h.includes('contact')) && !data['contact']) data['contact'] = a.href;
        });
        return JSON.stringify(data);
      })();
    """;

    try {
      var result = await controller.runJavaScriptReturningResult(mappingJs);
      Map<String, dynamic> found = jsonDecode(result.toString().replaceAll('\\"', '"').replaceAll('^"', '').replaceAll('"\$', ''));
      
      List<AppModule> detected = [masterList[0]..url = mainUrl]; // Home always first

      for (var mod in masterList.skip(1)) {
        if (found.containsKey(mod.id)) {
          mod.url = found[mod.id];
          detected.add(mod);
        }
      }

      // જો કંઈ ના મળે તો ડિફોલ્ટ હોમ, સર્વિસ, કોન્ટેક્ટ તો રાખવું જ
      if (detected.length < 3) {
        detected = [masterList[0], masterList[4], masterList[5]];
      }

      setState(() {
        currentModules = detected.take(4).toList(); // Max 4 buttons for best responsiveness
      });
    } catch (e) {
      debugPrint("Mapping Error: $e");
    }
  }

  _loadUrl() async {
    String content = await rootBundle.loadString('assets/url.txt');
    mainUrl = content.trim();
    if (mainUrl != null) {
      if (!mainUrl!.startsWith('http')) mainUrl = 'https://$mainUrl';
      masterList[0].url = mainUrl;
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
          leading: Padding(padding: const EdgeInsets.all(12.0), child: Hero(tag: 'appLogo', child: Image.asset('assets/images/logo.png'))),
          title: const Text("WEBFLOW AI PRO"),
          actions: [
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => controller.reload()),
            const SizedBox(width: 10),
          ],
        ),
        body: Stack(
          children: [
            if (mainUrl != null) WebViewWidget(controller: controller),
            if (isLoading) Container(color: Colors.white, child: const Center(child: CircularProgressIndicator())),
          ],
        ),
        bottomNavigationBar: _buildModernNav(),
      ),
    );
  }

  Widget _buildModernNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SafeArea( // Handles notch/bottom bar padding automatically
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: GNav(
            rippleColor: Colors.grey[300]!,
            hoverColor: Colors.grey[100]!,
            gap: 8,
            activeColor: Theme.of(context).primaryColor,
            iconSize: 26, // Larger icons for better touch
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), // More padding for better tap response
            duration: const Duration(milliseconds: 400),
            tabBackgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            color: Colors.grey[600],
            tabs: currentModules.map((m) => GButton(icon: m.icon, text: m.title)).toList(),
            selectedIndex: _selectedIndex,
            onTabChange: (index) {
              setState(() => _selectedIndex = index);
              HapticFeedback.mediumImpact(); // Stronger feedback on touch
              if (currentModules[index].url != null) {
                controller.loadRequest(Uri.parse(currentModules[index].url!));
              }
            },
          ),
        ),
      ),
    );
  }
}