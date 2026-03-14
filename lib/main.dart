import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:async';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // સ્ટેટસ બારને પ્રીમિયમ લુક આપવા માટે
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
  ));
  runApp(const WebFlowProMaster());
}

class WebFlowProMaster extends StatelessWidget {
  const WebFlowProMaster({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Professional App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6366F1), // Modern Indigo Color
      ),
      home: const MainAppLoader(),
    );
  }
}

class MainAppLoader extends StatefulWidget {
  const MainAppLoader({super.key});
  @override
  State<MainAppLoader> createState() => _MainAppLoaderState();
}

class _MainAppLoaderState extends State<MainAppLoader> {
  bool isSplash = true;
  String? webUrl;
  String? webLogo;

  @override
  void initState() {
    super.initState();
    _loadAppData();
  }

  _loadAppData() async {
    try {
      String content = await rootBundle.loadString('assets/url.txt');
      webUrl = content.trim();
      if (!webUrl!.startsWith('http')) webUrl = 'https://$webUrl';
      webLogo = "https://www.google.com/s2/favicons?sz=256&domain=$webUrl";
    } catch (e) {
      webUrl = "https://google.com";
    }

    // ૩ સેકન્ડ સ્પ્લેશ સ્ક્રીન
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => isSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return isSplash
        ? _buildSplashScreen()
        : AppDashboard(url: webUrl!, logo: webLogo!);
  }

  Widget _buildSplashScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (webLogo != null)
              Container(
                decoration: BoxDecoration(
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
                    borderRadius: BorderRadius.circular(20)
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.network(webLogo!, width: 100, height: 100),
                ),
              ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Color(0xFF6366F1)),
          ],
        ),
      ),
    );
  }
}

class AppDashboard extends StatefulWidget {
  final String url;
  final String logo;
  const AppDashboard({super.key, required this.url, required this.logo});

  @override
  State<AppDashboard> createState() => _AppDashboardState();
}

class _AppDashboardState extends State<AppDashboard> {
  late final WebViewController controller;
  int _selectedIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => setState(() => _isLoading = true),
        onPageFinished: (url) {
          setState(() => _isLoading = false);
          // આ જાદુઈ કોડ વેબસાઇટના હેડર-ફૂટર કાઢી નાખશે
          _removeWebNoise();
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  void _removeWebNoise() {
    controller.runJavaScript("""
      var head = document.querySelector('header'); if(head) head.style.display='none';
      var foot = document.querySelector('footer'); if(foot) foot.style.display='none';
      var nav = document.querySelector('nav'); if(nav) nav.style.display='none';
      document.body.style.paddingTop = '0px';
    """);
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) controller.loadRequest(Uri.parse(widget.url));
    if (index == 1) controller.loadRequest(Uri.parse("${widget.url}/shop"));
    if (index == 2) controller.loadRequest(Uri.parse("${widget.url}/account"));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (await controller.canGoBack()) {
          controller.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("OFFICIAL APP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leading: Builder(builder: (context) => IconButton(
            icon: const Icon(Icons.menu_open_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          )),
          actions: [IconButton(icon: const Icon(Icons.notifications_none_rounded), onPressed: () {})],
        ),
        drawer: _buildDrawer(),
        body: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onNavTap,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.category_outlined), selectedIcon: Icon(Icons.category), label: 'Shop'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: const Text("Premium User"),
            accountEmail: const Text("user@example.com"),
            currentAccountPicture: CircleAvatar(backgroundImage: NetworkImage(widget.logo)),
          ),
          ListTile(leading: const Icon(Icons.settings), title: const Text("Settings"), onTap: () {}),
          ListTile(leading: const Icon(Icons.info), title: const Text("About Us"), onTap: () {}),
          const Spacer(),
          ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text("Logout"), onTap: () {}),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}