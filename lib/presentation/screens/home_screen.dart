import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:dio/dio.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/states/loading_error_widgets.dart';
import '../providers/web_provider.dart';
import '../../data/models/web_item.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? htmlContent;
  String? currentUrl;
  String pageTitle = "NATIVE WEB ENGINE";
  final Dio _dio = Dio();
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadAndFetch();
  }

  Future<void> _loadAndFetch() async {
    try {
      String fileContent = await rootBundle.loadString('assets/url.txt');
      currentUrl = fileContent.trim();
      if (!currentUrl!.startsWith('http')) currentUrl = 'https://$currentUrl';
      _fetchPage(currentUrl!);
    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  Future<void> _fetchPage(String url, {bool isBack = false}) async {
    if (url.isEmpty) return;
    // Clean trailing slash for comparison
    final normNew = url.toLowerCase().replaceAll(RegExp(r'/$'), '');
    final normCurrent = currentUrl?.toLowerCase().replaceAll(RegExp(r'/$'), '');
    
    if (normNew == normCurrent && htmlContent != null) return;
    
    try {
      ref.read(webProvider.notifier).setLoading(true);
      
      setState(() {
        htmlContent = null; 
        if (!isBack && currentUrl != null) _history.add(currentUrl!);
      });

      final response = await _dio.get(url, options: Options(
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1',
        },
      ));
      
      if (response.statusCode == 200) {
        final rawHtml = response.data.toString();
        final cleanedHtml = _expertCleanHtml(rawHtml);
        
        setState(() {
          currentUrl = url;
          htmlContent = cleanedHtml;
          _extractPageTitle(rawHtml);
        });
        
        if (ref.read(webProvider).menuItems.length <= 1) _parseNavigation(rawHtml);
        ref.read(webProvider.notifier).setUrl(url);
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
      setState(() => htmlContent = "<div style='padding:40px; text-align:center;'><h2>Network Issue</h2><p>Could not load content. Please refresh.</p></div>");
    } finally {
      ref.read(webProvider.notifier).setLoading(false);
    }
  }

  void _handleBack() {
    if (ref.read(webProvider).isLoading) return; // Prevent spamming
    if (_history.isNotEmpty) {
      _fetchPage(_history.removeLast(), isBack: true);
    } else {
      SystemNavigator.pop();
    }
  }

  void _extractPageTitle(String html) {
    var document = html_parser.parse(html);
    var title = document.querySelector('title')?.text.split('|').first.trim() ?? "PalEnable";
    setState(() => pageTitle = title.length > 20 ? "${title.substring(0, 17)}..." : title);
  }

  String _expertCleanHtml(String html) {
    var document = html_parser.parse(html);
    
    // 1. Surgical Noise Removal (No global UI allowed)
    document.querySelectorAll('script, style, link, meta, iframe, noscript, .wpadminbar, .et_pb_menu, #wpadminbar, .mobile_menu, .et_mobile_menu, header, footer, .footer, .tp-bullets').forEach((e) => e.remove());

    // 2. Clear Global Junk
    var siteUI = ['nav', '.top-bar', '.footer-bottom', '#main-header', '#main-footer', '.elementor-location-header', '.elementor-location-footer', '.mobile-header'];
    for (var sel in siteUI) {
      document.querySelectorAll(sel).forEach((e) => e.remove());
    }

    // 3. Ultra-Greedy Selection (Pick the best content shell)
    var selectors = ['#page-container', '.et-main-area', '.elementor', 'main', '#main-content', '.entry-content', 'article', '.content', '.site-content'];
    dom.Element? main;
    for (var sel in selectors) {
      var found = document.querySelector(sel);
      if (found != null && found.text.trim().length > 100) {
        main = found;
        break;
      }
    }
    main ??= document.body;
    if (main == null) return "Discovery Layer Failed.";

    // 4. Surgical Pattern/Symbol Cleaning
    main.querySelectorAll('*').forEach((e) {
      String txt = e.text.trim();
      String cls = e.className.toLowerCase();
      
      // Strict token culling (%, K+, dots)
      if (txt == '%' || txt == 'K+' || txt == '+' || txt == '>' || txt == '»' || txt == '•' || txt == '✓' || txt == '::') {
        e.remove();
      }
      
      // Drop decorative bloat
      if ((cls.contains('pattern') || cls.contains('shape') || cls.contains('dots') || cls.contains('divider')) && txt.length < 50) {
        e.remove();
      }
      
      // Strip background blobs
      if (e.attributes['style']?.contains('background-image') ?? false) {
        e.attributes['style'] = e.attributes['style']!.replaceAll(RegExp(r'background-image:[^;]+;'), '');
      }
    });

    // 5. High-Depth Image Styling
    main.querySelectorAll('img').forEach((img) {
      String src = (img.attributes['src'] ?? '').toLowerCase();
      bool small = src.contains('icon') || src.contains('logo') || src.contains('tick') || (img.attributes['width'] != null && int.tryParse(img.attributes['width']!) != null && int.parse(img.attributes['width']!) < 60);
      
      if (small) {
        img.attributes['style'] = 'width: 32px; height: 32px; object-fit: contain; display: inline-block; vertical-align: middle; margin: 4px;';
      } else {
        img.attributes['style'] = 'width: 100%; height: auto; border-radius: 24px; margin: 24px 0; display: block; box-shadow: 0 16px 40px rgba(0,0,0,0.06);';
      }
    });

    // 6. Native Tile Transformation (For Services)
    main.querySelectorAll('ul').forEach((ul) {
      if (ul.text.length < 600) {
        ul.attributes['style'] = 'list-style: none; padding: 0; margin: 24px 0;';
        ul.querySelectorAll('li').forEach((li) {
          li.attributes['style'] = 'background: #FFFFFF; border: 1px solid #F1F5F9; padding: 22px; margin-bottom: 14px; border-radius: 20px; font-weight: 700; color: #1E293B; box-shadow: 0 4px 10px rgba(0,0,0,0.03); display: flex; align-items: center;';
        });
      }
    });

    return main.innerHtml;
  }

  void _parseNavigation(String html) {
    var document = html_parser.parse(html);
    List<WebItem> items = [];
    Set<String> urls = {};
    Set<String> labels = {'home'};

    Uri? baseUri;
    try { baseUri = Uri.parse(currentUrl!); } catch (_) {}
    if (baseUri == null) return;
    
    String root = "${baseUri.scheme}://${baseUri.host}";
    
    // Core Link: Home
    items.add(WebItem(label: 'Home', url: root, icon: Icons.flash_on_rounded));
    urls.add(root.toLowerCase().replaceAll(RegExp(r'/$'), ''));

    var links = document.querySelectorAll('header a, nav a, .menu a, .et-menu a, .elementor-nav-menu a, .sf-menu a');
    for (var link in links) {
      String label = link.text.trim();
      String? href = link.attributes['href'];
      
      if (label.isEmpty || label.length > 20 || label.length < 2 || href == null || 
          href.startsWith('#') || href.contains('tel:') || href.contains('facebook') || RegExp(r'[0-9]{5,}').hasMatch(label)) continue;

      String absUrl = href.startsWith('http') ? href : "$root/${href.startsWith('/') ? href.substring(1) : href}";
      String normUrl = absUrl.toLowerCase().replaceAll(RegExp(r'/$'), '');
      
      if (urls.contains(normUrl) || labels.contains(label.toLowerCase())) continue;

      items.add(WebItem(label: label, url: absUrl, icon: _getIcon(label)));
      urls.add(normUrl);
      labels.add(label.toLowerCase());
      if (items.length >= 10) break;
    }

    if (items.length > 1) ref.read(webProvider.notifier).updateMenu(items);
  }

  IconData _getIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('home')) return Icons.flash_on_rounded;
    if (l.contains('about')) return Icons.account_circle_rounded;
    if (l.contains('service') || l.contains('what')) return Icons.layers_rounded;
    if (l.contains('contact') || l.contains('reach')) return Icons.send_rounded;
    if (l.contains('blog') || l.contains('news')) return Icons.auto_awesome_motion_rounded;
    return Icons.widgets_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webProvider);
    final isDesktop = Responsive.isSizeDesktop(context);
    final hPadding = Responsive.value(context, mobile: 20.0, tablet: 40.0, desktop: 80.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(pageTitle.toUpperCase(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFF64748B))),
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.white.withOpacity(0.95),
          surfaceTintColor: Colors.transparent,
          leading: Builder(builder: (c) => IconButton(icon: const Icon(Icons.grid_view_rounded, color: AppColors.primary, size: 24), onPressed: () => Scaffold.of(c).openDrawer())),
          actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8), size: 22), onPressed: () => _fetchPage(currentUrl!)), const SizedBox(width: 8)],
        ),
        drawer: _buildDrawer(state.menuItems),
        body: state.isLoading 
            ? const Center(child: LoadingWidget())
            : RefreshIndicator(
                onRefresh: () => _fetchPage(currentUrl!),
                color: AppColors.primary,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  child: Column(
                    children: [
                      Container(
                        constraints: BoxConstraints(maxWidth: isDesktop ? 1100 : double.infinity),
                        padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 24),
                        child: htmlContent == null 
                            ? const Center(child: LoadingWidget())
                            : HtmlWidget(
                                htmlContent!,
                                textStyle: const TextStyle(fontSize: 16, height: 1.7, color: Color(0xFF334155)),
                                onTapUrl: (url) { _fetchPage(url); return true; },
                                customStylesBuilder: (el) {
                                  if (el.localName == 'h1') return {'font-size': '36px', 'font-weight': '900', 'color': '#0F172A', 'line-height': '1.1', 'margin': '20px 0'};
                                  if (el.localName == 'h2') return {'font-size': '26px', 'font-weight': '800', 'color': '#1E293B', 'margin': '32px 0 16px'};
                                  if (el.localName == 'a') return {'color': '#4F46E5', 'text-decoration': 'none', 'font-weight': '800'};
                                  return null;
                                },
                              ),
                      ),
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ),
        bottomNavigationBar: _buildBottomNav(state),
        extendBody: true,
      ),
    );
  }

  Widget _buildDrawer(List<WebItem> items) {
    return Drawer(
      backgroundColor: Colors.white,
      width: MediaQuery.of(context).size.width * 0.8,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(40))),
      child: Column(
        children: [
          Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(32, 80, 32, 40), color: const Color(0xFF0F172A), child: const Text("MENU", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (c, i) {
                final item = items[i];
                final isSelected = item.url == currentUrl;
                return ListTile(
                  leading: Icon(item.icon ?? Icons.circle_outlined, color: isSelected ? AppColors.primary : const Color(0xFF94A3B8)),
                  title: Text(item.label, style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, color: isSelected ? AppColors.primary : const Color(0xFF1E293B))),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  selected: isSelected,
                  selectedTileColor: AppColors.primary.withOpacity(0.05),
                  onTap: () { Navigator.pop(c); if (!isSelected) _fetchPage(item.url); },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(WebState state) {
    if (state.menuItems.isEmpty) return const SizedBox.shrink();
    final items = state.menuItems.take(5).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      height: 76,
      decoration: BoxDecoration(color: const Color(0xFF0F172A).withOpacity(0.98), borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 40, offset: const Offset(0, 10))]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items.map((item) {
          final isSelected = item.url == state.currentUrl;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () { if (!isSelected) { HapticFeedback.mediumImpact(); _fetchPage(item.url); } },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon ?? Icons.explore, color: isSelected ? Colors.white : const Color(0xFF64748B), size: 22),
                  const SizedBox(height: 4),
                  Text(item.label, maxLines: 1, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF475569), fontSize: 10, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}



