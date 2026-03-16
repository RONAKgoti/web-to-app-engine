import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../providers/app_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => _injectCleaner(),
        onPageFinished: (url) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) ref.read(appProvider.notifier).setLoading(false);
          });
          _injectCleaner();
          _smartAnalyze(url);
        },
      ));
    _loadInitialUrl();
  }

  void _injectCleaner() {
    controller.runJavaScript("""
      (function() {
        var css = 'header, nav, footer, .header, .navbar, .mobile-header, #header, #navigation { display: none !important; } body { padding-top: 0 !important; margin-top: 0 !important; }';
        var style = document.createElement('style');
        style.innerHTML = css;
        document.head.appendChild(style);
      })();
    """);
  }

  void _smartAnalyze(String currentUrl) async {
    const String scanJs = """
      (function() {
        var map = {};
        var links = document.querySelectorAll('a');
        links.forEach(function(a) {
          var t = a.innerText.toLowerCase().trim();
          var h = a.href.toLowerCase();
          if ((t.includes('shop') || h.includes('shop')) && !map['shop']) map['shop'] = a.href;
          if ((t.includes('cart') || h.includes('cart')) && !map['cart']) map['cart'] = a.href;
          if ((t.includes('service') || h.includes('service')) && !map['service']) map['service'] = a.href;
          if ((t.includes('account') || h.includes('profile')) && !map['account']) map['account'] = a.href;
          if ((t.includes('contact') || h.includes('help')) && !map['contact']) map['contact'] = a.href;
        });
        return JSON.stringify(map);
      })();
    """;

    try {
      var result = await controller.runJavaScriptReturningResult(scanJs);
      Map<String, dynamic> detected = jsonDecode(result.toString().replaceAll('\\"', '"').replaceAll('^"', '').replaceAll('"\$', ''));
      
      final mainUrl = ref.read(appProvider).mainUrl;
      List<SmartModule> found = [SmartModule(id: 'home', label: 'Home', icon: Icons.home_rounded, url: mainUrl)];

      final List<Map<String, dynamic>> masterData = [
        {'id': 'shop', 'label': 'Shop', 'icon': Icons.shopping_bag_rounded},
        {'id': 'cart', 'label': 'Cart', 'icon': Icons.shopping_cart_rounded},
        {'id': 'service', 'label': 'Services', 'icon': Icons.miscellaneous_services_rounded},
        {'id': 'account', 'label': 'User', 'icon': Icons.person_rounded},
        {'id': 'contact', 'label': 'Help', 'icon': Icons.contact_support_rounded},
      ];

      for (var item in masterData) {
        if (detected.containsKey(item['id'])) {
          found.add(SmartModule(id: item['id'], label: item['label'], icon: item['icon'], url: detected[item['id']]));
        }
      }

      if (found.length < 3) {
        found = [
          SmartModule(id: 'home', label: 'Home', icon: Icons.home_rounded, url: mainUrl),
          SmartModule(id: 'service', label: 'Services', icon: Icons.miscellaneous_services_rounded, url: "$mainUrl/services"),
          SmartModule(id: 'contact', label: 'Help', icon: Icons.contact_support_rounded, url: "$mainUrl/contact"),
        ];
      }

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(appProvider.notifier).updateTabs(found.take(4).toList());
        });
      }
    } catch (e) {
      debugPrint("Analysis Error: $e");
    }
  }

  void _loadInitialUrl() async {
    String content = await rootBundle.loadString('assets/url.txt');
    String url = content.trim();
    if (url.isNotEmpty) {
      if (!url.startsWith('http')) url = 'https://$url';
      if (mounted) {
        ref.read(appProvider.notifier).setUrl(url);
        controller.loadRequest(Uri.parse(url));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final selectedIndex = ref.watch(tabIndexProvider);

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
          title: const Text("WEBFLOW AI PRO"),
          actions: [
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => controller.reload()),
            const SizedBox(width: 10),
          ],
        ),
        body: Stack(
          children: [
            if (state.mainUrl != null) WebViewWidget(controller: controller),
            if (state.isLoading) Container(color: Colors.white, child: const Center(child: CircularProgressIndicator())),
          ],
        ),
        bottomNavigationBar: (state.activeTabs.isNotEmpty) ? Container(
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: GNav(
                activeColor: Theme.of(context).primaryColor,
                gap: 8,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                tabBackgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                color: Colors.grey,
                tabs: state.activeTabs.map((t) => GButton(icon: t.icon, text: t.label)).toList(),
                selectedIndex: selectedIndex,
                onTabChange: (index) {
                  ref.read(tabIndexProvider.notifier).state = index;
                  HapticFeedback.lightImpact();
                  if (state.activeTabs[index].url != null) {
                    controller.loadRequest(Uri.parse(state.activeTabs[index].url!));
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
