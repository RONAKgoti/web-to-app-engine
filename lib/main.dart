import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle, SystemChrome, SystemUiOverlayStyle;
import 'package:google_nav_bar/google_nav_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const MyApp());
}

class AppTheme {
  static Color primary = const Color(0xFF6366F1);
  static Color accent = const Color(0xFF4F46E5);
  
  static ThemeData getTheme(Color mainColor) => ThemeData(
    useMaterial3: true,
    primaryColor: mainColor,
    colorScheme: ColorScheme.fromSeed(seedColor: mainColor),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
        fontWeight: FontWeight.w800, 
        fontSize: 18, 
        color: Colors.black87,
      ),
    ),
  );
}

class SiteProfile {
  final String category;
  final List<GButton> tabs;
  final Color themeColor;
  final bool showBottomNav;

  SiteProfile({
    required this.category,
    required this.tabs,
    required this.themeColor,
    this.showBottomNav = true,
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Color currentPrimary = const Color(0xFF6366F1);

  void updateTheme(Color newColor) {
    setState(() => currentPrimary = newColor);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebFlow AI Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(currentPrimary),
      routes: {
        '/': (context) => const SplashScreen(),
        '/home': (context) => MainScreen(onThemeChange: updateTheme),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primary, AppTheme.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 5)
                  ],
                  image: const DecorationImage(
                    image: AssetImage('assets/images/logo.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                "WEBFLOW AI PRO",
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
              const SizedBox(height: 50),
              const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            ],
          ),
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
  int _currentIndex = 0;
  String? mainUrl;
  late SiteProfile currentProfile;

  @override
  void initState() {
    super.initState();
    currentProfile = _getDefaultProfile();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          _detectAndApplyProfile(url);
          _injectCustomStyle();
        },
        onPageFinished: (url) {
          setState(() => isLoading = false);
          _injectCustomStyle();
        },
        onWebResourceError: (error) => debugPrint("Web Error: ${error.description}"),
      ));
    _loadUrlFromAssets();
  }

  void _injectCustomStyle() {
    // Advanced Injection to hide web headers IMMEDIATELY
    controller.runJavaScript("""
      (function() {
        var css = 'header, nav, .header, .navbar, .mobile-header, .top-bar, #header, #navigation, .elementor-location-header, .sticky-header { display: none !important; } body { padding-top: 0 !important; }';
        var head = document.head || document.getElementsByTagName('head')[0];
        var style = document.createElement('style');
        style.type = 'text/css';
        style.appendChild(document.createTextNode(css));
        head.appendChild(style);
      })();
    """);
  }

  void _detectAndApplyProfile(String url) {
    String lowerUrl = url.toLowerCase();
    SiteProfile newProfile;

    if (lowerUrl.contains('shop') || lowerUrl.contains('cart') || lowerUrl.contains('store')) {
      newProfile = SiteProfile(
        category: "E-Commerce",
        themeColor: const Color(0xFFF59E0B),
        tabs: const [
          GButton(icon: Icons.shopping_bag_rounded, text: 'Shop'),
          GButton(icon: Icons.shopping_cart_rounded, text: 'Cart'),
          GButton(icon: Icons.person_rounded, text: 'Account'),
        ],
      );
    } else if (lowerUrl.contains('news') || lowerUrl.contains('blog')) {
      newProfile = SiteProfile(
        category: "News Feed",
        themeColor: const Color(0xFFEF4444),
        tabs: const [
          GButton(icon: Icons.article_rounded, text: 'Articles'),
          GButton(icon: Icons.trending_up_rounded, text: 'Trending'),
          GButton(icon: Icons.bookmark_rounded, text: 'Saved'),
        ],
      );
    } else {
      newProfile = _getDefaultProfile();
    }

    if (newProfile.category != currentProfile.category) {
      setState(() {
        currentProfile = newProfile;
        widget.onThemeChange(newProfile.themeColor);
      });
    }
  }

  SiteProfile _getDefaultProfile() {
    return SiteProfile(
      category: "WebFlow AI Pro",
      themeColor: const Color(0xFF6366F1),
      tabs: const [
        GButton(icon: Icons.home_rounded, text: 'Home'),
        GButton(icon: Icons.explore_rounded, text: 'Explore'),
        GButton(icon: Icons.info_rounded, text: 'About'),
      ],
    );
  }

  _loadUrlFromAssets() async {
    try {
      String fileContent = await rootBundle.loadString('assets/url.txt');
      String finalUrl = fileContent.trim();
      if (finalUrl.isNotEmpty) {
        if (!finalUrl.startsWith('http')) finalUrl = 'https://$finalUrl';
        setState(() => mainUrl = finalUrl);
        controller.loadRequest(Uri.parse(finalUrl));
      }
    } catch (e) {
      setState(() => isLoading = false);
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
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Exit App?"),
              content: const Text("Are you sure you want to exit?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("No")),
                TextButton(onPressed: () => SystemNavigator.pop(), child: const Text("Yes")),
              ],
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 65,
          leading: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Image.asset('assets/images/logo.png'),
          ),
          title: Text(currentProfile.category),
          actions: [
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => controller.reload()),
            Builder(builder: (context) => IconButton(
              icon: Icon(Icons.menu_rounded, color: currentProfile.themeColor),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            )),
            const SizedBox(width: 5),
          ],
        ),
        endDrawer: Drawer(
          width: MediaQuery.of(context).size.width * 0.75,
          child: Column(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: currentProfile.themeColor),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(radius: 35, backgroundImage: const AssetImage('assets/images/logo.png'), backgroundColor: Colors.white),
                      const SizedBox(height: 10),
                      Text(currentProfile.category, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              _drawerItem(Icons.home_rounded, "Home", () {
                Navigator.pop(context);
                if (mainUrl != null) controller.loadRequest(Uri.parse(mainUrl!));
              }),
              _drawerItem(Icons.info_rounded, "About Us", () => Navigator.pop(context)),
              _drawerItem(Icons.contact_support_rounded, "Support", () => Navigator.pop(context)),
              const Spacer(),
              const Divider(),
              _drawerItem(Icons.share_rounded, "Share App", () => Navigator.pop(context)),
              const SizedBox(height: 20),
            ],
          ),
        ),
        body: Stack(
          children: [
            if (mainUrl != null) WebViewWidget(controller: controller),
            if (isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
        bottomNavigationBar: currentProfile.showBottomNav ? Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 10),
            child: GNav(
              rippleColor: Colors.grey[300]!,
              hoverColor: Colors.grey[100]!,
              gap: 8,
              activeColor: currentProfile.themeColor,
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              duration: const Duration(milliseconds: 400),
              tabBackgroundColor: currentProfile.themeColor.withOpacity(0.1),
              color: Colors.grey,
              tabs: currentProfile.tabs,
              selectedIndex: _currentIndex,
              onTabChange: (index) {
                setState(() => _currentIndex = index);
                // logic for tab clicks can go here
                if (index == 0 && mainUrl != null) controller.loadRequest(Uri.parse(mainUrl!));
              },
            ),
          ),
        ) : null,
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}