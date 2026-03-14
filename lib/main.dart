import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:async';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // સ્ટેટસ બારને પ્રોફેશનલ લુક આપવા માટે
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AutoSplashScreen(),
  ));
}

// ૧. પ્રોફેશનલ ડાયનેમિક સ્પ્લેશ સ્ક્રીન
class AutoSplashScreen extends StatefulWidget {
  const AutoSplashScreen({super.key});
  @override
  State<AutoSplashScreen> createState() => _AutoSplashScreenState();
}

class _AutoSplashScreenState extends State<AutoSplashScreen> {
  String websiteUrl = ""; // Assets માંથી આવશે
  String? webLogo;

  @override
  void initState() {
    super.initState();
    _setupApp();
  }

  _setupApp() async {
    // અંહી આપણે url.txt વાંચીશું
    try {
      String fileContent = await rootBundle.loadString('assets/url.txt');
      websiteUrl = fileContent.trim();
      if (!websiteUrl.startsWith('http')) websiteUrl = 'https://$websiteUrl';

      // વેબસાઈટનો લોગો ઓટોમેટિક મેળવવા માટે (Favicon Fetcher)
      setState(() {
        webLogo = "https://www.google.com/s2/favicons?sz=256&domain=$websiteUrl";
      });
    } catch (e) {
      websiteUrl = "https://google.com";
    }

    // ૪ સેકન્ડનો સ્પ્લેશ ટાઈમ
    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ProfessionalAppEngine(url: websiteUrl)),
        );
      }
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
            // વેબસાઈટનો લોગો જે એપ જેવો જ લાગશે
            if (webLogo != null)
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(webLogo!, width: 100, height: 100,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.language, size: 80, color: Colors.blueAccent)),
                ),
              ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(strokeWidth: 3, color: Colors.blueAccent),
            const SizedBox(height: 20),
            const Text("Setting up your experience...", style: TextStyle(color: Colors.grey, fontSize: 14, letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }
}

// ૨. પ્રોફેશનલ મેઈન એપ એન્જિન
class ProfessionalAppEngine extends StatefulWidget {
  final String url;
  const ProfessionalAppEngine({super.key, required this.url});
  @override
  State<ProfessionalAppEngine> createState() => _ProfessionalAppEngineState();
}

class _ProfessionalAppEngineState extends State<ProfessionalAppEngine> {
  late final WebViewController controller;
  bool isLoading = true;
  double progress = 0;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => progress = p / 100),
        onPageStarted: (url) => setState(() => isLoading = true),
        onPageFinished: (url) {
          setState(() => isLoading = false);
          _applyNativeTransformation();
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  // આ ફંક્શન વેબસાઈટને અંદરથી "Native App" માં ફેરવશે
  void _applyNativeTransformation() {
    controller.runJavaScript("""
      var style = document.createElement('style');
      style.innerHTML = `
        /* હેડરને એપ બાર જેવું બનાવો */
        header, .navbar, #header { 
          position: sticky !important; top: 0 !important; 
          box-shadow: 0 2px 10px rgba(0,0,0,0.08) !important;
          z-index: 9999 !important;
        }
        /* સ્ક્રોલબાર છુપાવો જેથી અસલી એપ લાગે */
        ::-webkit-scrollbar { display: none !important; }
        /* બટન્સને પ્રોફેશનલ લુક આપો */
        button, .btn { border-radius: 12px !important; }
        /* આખા પેજને નેટિવ ફીલ આપો */
        body { -webkit-tap-highlight-color: transparent !important; }
      `;
      document.head.appendChild(style);
    """);
  }

  @override
  Widget build(BuildContext context) {
    // બેક બટન દબાવતા એપ બંધ ન થાય પણ પેજ પાછું જાય
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
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: controller),
              // ઉપર પાતળો પ્રોગ્રેસ બાર (પ્રીમિયમ લુક)
              if (progress < 1.0)
                LinearProgressIndicator(value: progress, color: Colors.blueAccent, backgroundColor: Colors.transparent, minHeight: 3),
            ],
          ),
        ),
      ),
    );
  }
}