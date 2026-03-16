import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle, SystemChrome, SystemUiOverlayStyle;
import 'package:google_nav_bar/google_nav_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

// ૧. થીમ સેટઅપ
// ૧. થીમ અને સાઇટ કન્ફિગરેશન
class AppTheme {
  static Color primary = const Color(0xFF6366F1); // Default Indigo
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
      titleTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
  );
}

// સાઇટ પ્રોફાઇલ મોડેલ
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
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => MainScreen(onThemeChange: updateTheme),
      },
    );
  }
}

// ૨. SPLASH SCREEN
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
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bolt, size: 100, color: Colors.white),
            const SizedBox(height: 20),
            const Text("WEBFLOW PRO", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 10),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ૩. LOGIN SCREEN
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Welcome Back", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            const SizedBox(height: 40),
            TextField(decoration: InputDecoration(labelText: "Email", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 16),
            TextField(obscureText: true, decoration: InputDecoration(labelText: "Password", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Log In", style: TextStyle(fontSize: 18, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// ૪. MAIN SCREEN (With Navigation & Web Logic)
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
  
  // Dynamic Profile State
  late SiteProfile currentProfile;

  @override
  void initState() {
    super.initState();
    currentProfile = _getDefaultProfile();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => _detectAndApplyProfile(url),
        onPageFinished: (url) => setState(() => isLoading = false),
      ));
    _loadUrlFromAssets();
  }

  // 🧠 SMART MAPPING SYSTEM
  void _detectAndApplyProfile(String url) {
    String lowerUrl = url.toLowerCase();
    SiteProfile newProfile;

    if (lowerUrl.contains('shop') || lowerUrl.contains('cart') || lowerUrl.contains('product') || lowerUrl.contains('store')) {
      // E-COMMERCE PROFILE
      newProfile = SiteProfile(
        category: "E-Commerce",
        themeColor: const Color(0xFFF59E0B), // Amber color for shops
        tabs: const [
          GButton(icon: Icons.home_rounded, text: 'Shop'),
          GButton(icon: Icons.shopping_bag_rounded, text: 'Orders'),
          GButton(icon: Icons.favorite_rounded, text: 'Wishlist'),
          GButton(icon: Icons.shopping_cart_rounded, text: 'Cart'),
        ],
      );
    } else if (lowerUrl.contains('news') || lowerUrl.contains('blog') || lowerUrl.contains('article')) {
      // NEWS/BLOG PROFILE
      newProfile = SiteProfile(
        category: "News",
        themeColor: const Color(0xFFEF4444), // Red for news
        tabs: const [
          GButton(icon: Icons.article_rounded, text: 'Feed'),
          GButton(icon: Icons.trending_up_rounded, text: 'Trending'),
          GButton(icon: Icons.bookmark_rounded, text: 'Saved'),
        ],
      );
    } else if (lowerUrl.contains('portfolio') || lowerUrl.contains('work')) {
      // PORTFOLIO PROFILE
      newProfile = SiteProfile(
        category: "Portfolio",
        themeColor: const Color(0xFF10B981), // Emerald
        showBottomNav: false, // Portfolios look better full screen
        tabs: [],
      );
    } else {
      // DEFAULT PROFESSIONAL PROFILE
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

  // GitHub માંથી આવતી લિંક અહીં વંચાશે
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Premium WebFlow"),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_open_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => controller.reload(),
          ),
        ],
      ),
      drawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.75,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primary, AppTheme.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              accountName: const Text("WebFlow Pro User", style: TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: const Text("premium@webflow.pro"),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Color(0xFF6366F1), size: 40),
              ),
            ),
            _buildDrawerItem(Icons.home_rounded, "Home", () => Navigator.pop(context)),
            _buildDrawerItem(Icons.settings_rounded, "Settings", () {}),
            _buildDrawerItem(Icons.info_rounded, "Support", () {}),
            const Spacer(),
            const Divider(indent: 20, endIndent: 20),
            _buildDrawerItem(Icons.logout_rounded, "Logout", () => Navigator.pushReplacementNamed(context, '/login'), color: Colors.redAccent),
            const SizedBox(height: 20),
          ],
        ),
      ),
      body: Container(
        color: Colors.white,
        child: Stack(
          children: [
            if (mainUrl != null) 
              WebViewWidget(controller: controller)
            else if (!isLoading)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.link_off_rounded, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text("No URL found in assets/url.txt", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            
            // સુંદર લોડિંગ એનિમેશન
            if (isLoading)
              Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
                      const SizedBox(height: 20),
                      Text("Loading Experience...", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        child: currentProfile.showBottomNav
            ? Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(blurRadius: 20, color: Colors.black.withOpacity(.1)),
                  ],
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
                    color: Colors.grey[600],
                    tabs: currentProfile.tabs,
                    selectedIndex: _currentIndex,
                    onTabChange: (index) {
                      setState(() {
                        _currentIndex = index;
                        // અહીં તું અલગ અલગ લિંક્સ સેટ કરી શકે, અત્યારે મેં મેઈન URL જ રાખ્યું છે
                        if (mainUrl != null) controller.loadRequest(Uri.parse(mainUrl!));
                      });
                    },
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.black87),
      title: Text(title, style: TextStyle(color: color ?? Colors.black87, fontWeight: FontWeight.w500)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}