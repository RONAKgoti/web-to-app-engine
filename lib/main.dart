import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle, SystemChrome, SystemUiOverlayStyle, SystemNavigator;
import 'package:google_nav_bar/google_nav_bar.dart';

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

class AppTheme {
  static Color primary = const Color(0xFF6366F1);
  static Color accent = const Color(0xFF4F46E5);
  
  static ThemeData getTheme(Color mainColor) => ThemeData(
    useMaterial3: true,
    primaryColor: mainColor,
    colorScheme: ColorScheme.fromSeed(seedColor: mainColor, primary: mainColor),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w800, 
        fontSize: 18, 
        color: Colors.black87,
        letterSpacing: -0.5,
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
              Hero(
                tag: 'logo',
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, spreadRadius: 10)
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
                  fontSize: 26, 
                  fontWeight: FontWeight.w900, 
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 60),
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
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
      (function() {
        var css = 'header, nav, .header, .navbar, .mobile-header, .top-bar, #header, #navigation, .sticky-header { display: none !important; } body { padding-top: 0 !important; }';
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

    if (lowerUrl.contains('shop') || lowerUrl.contains('cart')) {
      newProfile = SiteProfile(
        category: "E-Commerce",
        themeColor: const Color(0xFFF59E0B),
        tabs: const [
          GButton(icon: Icons.store_rounded, text: 'Shop'),
          GButton(icon: Icons.shopping_bag_rounded, text: 'Orders'),
          GButton(icon: Icons.favorite_rounded, text: 'Saved'),
          GButton(icon: Icons.person_rounded, text: 'Account'),
        ],
      );
    } else if (lowerUrl.contains('news') || lowerUrl.contains('blog')) {
      newProfile = SiteProfile(
        category: "Updates",
        themeColor: const Color(0xFFEF4444),
        tabs: const [
          GButton(icon: Icons.article_rounded, text: 'Feed'),
          GButton(icon: Icons.trending_up_rounded, text: 'Trending'),
          GButton(icon: Icons.bookmark_rounded, text: 'Bookmarks'),
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
      category: "Home",
      themeColor: const Color(0xFF6366F1),
      tabs: const [
        GButton(icon: Icons.home_rounded, text: 'Home'),
        GButton(icon: Icons.explore_rounded, text: 'Explore'),
        GButton(icon: Icons.notifications_rounded, text: 'Alerts'),
        GButton(icon: Icons.settings_rounded, text: 'Config'),
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
          _showExitDialog();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 65,
          leading: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Hero(tag: 'logo', child: Image.asset('assets/images/logo.png')),
          ),
          title: Text(currentProfile.category),
          actions: [
            IconButton(icon: const Icon(Icons.refresh_rounded, size: 22), onPressed: () => controller.reload()),
            Builder(builder: (context) => IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: currentProfile.themeColor.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.grid_view_rounded, color: currentProfile.themeColor, size: 20),
              ),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            )),
            const SizedBox(width: 8),
          ],
        ),
        endDrawer: _buildDrawer(),
        body: Stack(
          children: [
            if (mainUrl != null) WebViewWidget(controller: controller),
            if (isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    if (!currentProfile.showBottomNav) return const SizedBox.shrink();
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: GNav(
            rippleColor: currentProfile.themeColor.withOpacity(0.1),
            hoverColor: currentProfile.themeColor.withOpacity(0.05),
            gap: 6,
            activeColor: currentProfile.themeColor,
            iconSize: 22,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            duration: const Duration(milliseconds: 300),
            tabBackgroundColor: currentProfile.themeColor.withOpacity(0.1),
            color: Colors.grey[600],
            tabs: currentProfile.tabs,
            selectedIndex: _currentIndex,
            onTabChange: (index) {
              setState(() => _currentIndex = index);
              HapticFeedback.lightImpact(); // Added touch feedback
              if (index == 0 && mainUrl != null) controller.loadRequest(Uri.parse(mainUrl!));
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [currentProfile.themeColor, currentProfile.themeColor.withOpacity(0.8)]),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(radius: 35, backgroundColor: Colors.white, backgroundImage: const AssetImage('assets/images/logo.png')),
                  const SizedBox(height: 12),
                  const Text("WEBFLOW AI PRO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ),
          _drawerTile(Icons.home_rounded, "Dashboard", () => Navigator.pop(context)),
          _drawerTile(Icons.info_outline_rounded, "How it works", () => Navigator.pop(context)),
          _drawerTile(Icons.contact_page_rounded, "Contact Us", () => Navigator.pop(context)),
          const Spacer(),
          const Divider(indent: 20, endIndent: 20),
          _drawerTile(Icons.share_rounded, "Share App", () => Navigator.pop(context)),
          _drawerTile(Icons.star_outline_rounded, "Rate App", () => Navigator.pop(context)),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueGrey[700], size: 22),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      onTap: onTap,
      dense: true,
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Exit App?"),
        content: const Text("Are you sure you want to exit WebFlow AI Pro?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => SystemNavigator.pop(),
            style: ElevatedButton.styleFrom(backgroundColor: currentProfile.themeColor, foregroundColor: Colors.white),
            child: const Text("EXIT"),
          ),
        ],
      ),
    );
  }
}