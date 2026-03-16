import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle, SystemChrome, SystemUiOverlayStyle;
import 'package:google_nav_bar/google_nav_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        fontSize: 20, 
        color: Colors.black87,
        letterSpacing: -0.5,
      ),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
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
      title: 'WebFlow Pro',
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
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primary,
              AppTheme.primary.withRed(100).withBlue(255),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder(
                duration: const Duration(seconds: 2),
                tween: Tween<double>(begin: 0, end: 1),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: value,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 30,
                        spreadRadius: 8,
                      ),
                    ],
                    image: const DecorationImage(
                      image: AssetImage('assets/images/logo.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                "WEBFLOW AI PRO",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Loading Premium Experience...",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 50),
              const CircularProgressIndicator(color: Colors.white),
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
      ));
    _loadUrlFromAssets();
  }

  void _injectCustomStyle() {
    controller.runJavaScript("""
      var style = document.createElement('style');
      style.innerHTML = 'header, nav, .header, .navbar, .mobile-header, .top-bar, #header, #navigation { display: none !important; } body { padding-top: 0 !important; }';
      document.head.appendChild(style);
    """);
  }

  void _detectAndApplyProfile(String url) {
    String lowerUrl = url.toLowerCase();
    SiteProfile newProfile;
    if (lowerUrl.contains('shop') || lowerUrl.contains('cart')) {
      newProfile = SiteProfile(
        category: "E-Commerce",
        themeColor: const Color(0xFFF59E0B),
        tabs: const [
          GButton(icon: Icons.home_rounded, text: 'Shop'),
          GButton(icon: Icons.shopping_cart_rounded, text: 'Cart'),
        ],
      );
    } else {
      newProfile = _getDefaultProfile();
    }
    setState(() {
      currentProfile = newProfile;
      widget.onThemeChange(newProfile.themeColor);
    });
  }

  SiteProfile _getDefaultProfile() {
    return SiteProfile(
      category: "General",
      themeColor: const Color(0xFF6366F1),
      tabs: const [
        GButton(icon: Icons.language_rounded, text: 'Home'),
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
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 70,
          leadingWidth: 80,
          leading: Padding(
            padding: const EdgeInsets.only(left: 15.0),
            child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
          ),
          title: Text(currentProfile.category, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => controller.reload()),
            Builder(
              builder: (context) => IconButton(
                icon: Icon(Icons.menu_rounded, color: currentProfile.themeColor),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ],
        ),
        endDrawer: Drawer(
          child: Column(
            children: [
               UserAccountsDrawerHeader(
                decoration: BoxDecoration(color: currentProfile.themeColor),
                accountName: Text(currentProfile.category),
                accountEmail: const Text("Professional WebApp"),
                currentAccountPicture: CircleAvatar(backgroundImage: const AssetImage('assets/images/logo.png'), backgroundColor: Colors.white),
              ),
              ListTile(leading: const Icon(Icons.home), title: const Text("Home"), onTap: () => Navigator.pop(context)),
              ListTile(leading: const Icon(Icons.info), title: const Text("About"), onTap: () => Navigator.pop(context)),
            ],
          ),
        ),
        body: mainUrl == null 
          ? const Center(child: CircularProgressIndicator()) 
          : WebViewWidget(controller: controller),
        bottomNavigationBar: currentProfile.showBottomNav ? Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: GNav(
            activeColor: currentProfile.themeColor,
            tabBackgroundColor: currentProfile.themeColor.withOpacity(0.1),
            tabs: currentProfile.tabs,
            selectedIndex: _currentIndex,
            onTabChange: (index) => setState(() => _currentIndex = index),
          ),
        ) : null,
      ),
    );
  }
}