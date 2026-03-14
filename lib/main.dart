import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: UniversalAppEngine()));
}

class UniversalAppEngine extends StatefulWidget {
  const UniversalAppEngine({super.key});
  @override
  State<UniversalAppEngine> createState() => _UniversalAppEngineState();
}

class _UniversalAppEngineState extends State<UniversalAppEngine> {
  late final WebViewController controller;
  final TextEditingController _searchController = TextEditingController();
  bool isLoading = true;
  String currentUrl = "https://www.amazon.in"; // અંહી તારી કોઈ પણ લિંક ચાલશે

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => setState(() => isLoading = true),
        onPageFinished: (url) {
          setState(() {
            isLoading = false;
            currentUrl = url;
          });
          // જાદુઈ લોજિક: કોઈ પણ વેબસાઈટનું હેડર/ફૂટર છુપાવવા માટે
          _cleanWebsiteUI();
        },
      ))
      ..loadRequest(Uri.parse(currentUrl));
  }

  // ૧. કોમન લોજિક: વેબસાઈટને એપ જેવી બનાવવા માટે (Header/Footer Cleaner)
  void _cleanWebsiteUI() {
    controller.runJavaScript("""
      var selectors = ['header', 'footer', '#nav-bar', '.navbar', '#header', '.header-mobile'];
      selectors.forEach(function(s) {
        var el = document.querySelector(s);
        if(el) el.style.display = 'none';
      });
      document.body.style.paddingTop = '0px';
    """);
  }

  // ૨. સર્ચ લોજિક: કોઈ પણ વેબસાઈટ પર સર્ચ કરવા માટે
  void _search(String query) {
    if (query.isNotEmpty) {
      // મોટેભાગની વેબસાઈટમાં /search?q= લિંક કામ કરે છે
      final searchUrl = "$currentUrl/search?q=${Uri.encodeComponent(query)}";
      controller.loadRequest(Uri.parse(searchUrl));
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // પ્રોપર મોબાઈલ એપ હેડર
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: AppBar(
          elevation: 2,
          backgroundColor: Colors.white,
          title: Container(
            height: 45,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchController,
              onSubmitted: (value) => _search(value),
              decoration: const InputDecoration(
                hintText: "Search in App...",
                prefixIcon: Icon(Icons.search, color: Colors.blue),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          actions: [IconButton(icon: const Icon(Icons.notifications_none, color: Colors.black), onPressed: () {})],
        ),
      ),

      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),

      // પ્રોપર મોબાઈલ એપ બોટમ નેવિગેશન
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          if (index == 0) controller.loadRequest(Uri.parse(currentUrl));
          if (index == 1) controller.runJavaScript("window.history.back();");
          if (index == 3) controller.loadRequest(Uri.parse("$currentUrl/cart"));
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.arrow_back), label: "Back"),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_border), label: "Wishlist"),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Cart"),
        ],
      ),
    );
  }
}