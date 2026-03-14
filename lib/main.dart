import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

// ૧. થીમ સેટઅપ
class AppTheme {
  static Color primary = const Color(0xFF6366F1); // Modern Indigo
  static ThemeData lightTheme = ThemeData(
    primaryColor: primary,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: AppBarTheme(backgroundColor: primary, foregroundColor: Colors.white),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebFlow Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const MainScreen(),
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
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  int _currentIndex = 0;
  String? mainUrl;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) => setState(() => isLoading = false),
      ));
    _loadUrlFromAssets();
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
        title: const Text("WebFlow Dashboard"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => controller.reload())],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: AppTheme.primary),
              accountName: const Text("Developer"),
              accountEmail: const Text("dev@webflowpro.com"),
              currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person)),
            ),
            ListTile(leading: const Icon(Icons.home), title: const Text("Home"), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.info), title: const Text("About App"), onTap: () {}),
            const Spacer(),
            ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text("Logout"), onTap: () => Navigator.pushReplacementNamed(context, '/login')),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (mainUrl != null) WebViewWidget(controller: controller),
          if (isLoading) const Center(child: CircularProgressIndicator()),
          if (mainUrl == null && !isLoading) const Center(child: Text("No URL found in assets/url.txt")),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: AppTheme.primary,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            // અહીં તું અલગ અલગ લિંક્સ સેટ કરી શકે, અત્યારે મેં મેઈન URL જ રાખ્યું છે
            if (mainUrl != null) controller.loadRequest(Uri.parse(mainUrl!));
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.language), label: "Website"),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Panel"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Account"),
        ],
      ),
    );
  }
}