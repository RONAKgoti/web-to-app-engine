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
  
  // Navigation History for Back Button
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadAndFetch();
  }

  Future<void> _loadAndFetch() async {
    try {
      String content = await rootBundle.loadString('assets/url.txt');
      currentUrl = content.trim();
      if (!currentUrl!.startsWith('http')) currentUrl = 'https://$currentUrl';
      
      _fetchPage(currentUrl!);
    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  Future<void> _fetchPage(String url, {bool isBack = false}) async {
    if (url == currentUrl && htmlContent != null) return;
    
    try {
      ref.read(webProvider.notifier).setLoading(true);
      
      setState(() {
        htmlContent = null; 
        if (!isBack && currentUrl != null) {
          _history.add(currentUrl!);
        }
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
        
        // Navigation Management
        if (ref.read(webProvider).menuItems.length <= 1) {
           _parseNavigation(rawHtml);
        }
        ref.read(webProvider.notifier).setUrl(url);
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      ref.read(webProvider.notifier).setLoading(false);
    }
  }

  void _handleBack() {
    if (_history.isNotEmpty) {
      final prevUrl = _history.removeLast();
      _fetchPage(prevUrl, isBack: true);
    } else {
      SystemNavigator.pop(); // Exit app if no history
    }
  }

  void _extractPageTitle(String html) {
    var document = html_parser.parse(html);
    var titleTag = document.querySelector('title');
    if (titleTag != null && titleTag.text.isNotEmpty) {
      String rawTitle = titleTag.text.split('|').first.trim();
      setState(() {
        pageTitle = rawTitle.length > 20 ? "${rawTitle.substring(0, 17)}..." : rawTitle;
      });
    }
  }

  String _expertCleanHtml(String html) {
    var document = html_parser.parse(html);
    
    // 1. Surgical Noise Removal
    document.querySelectorAll('script, style, link, meta, iframe, noscript, .wpadminbar, .et_pb_menu, .mobile-menu').forEach((e) => e.remove());

    // 2. Remove Global UI (Sticky Headers/Footers)
    var siteUI = ['header', 'footer', 'nav', '.top-bar', '.footer-bottom', '#header', '#footer', '.site-header', '.site-footer', '.elementor-location-header', '.elementor-location-footer'];
    for (var sel in siteUI) {
      document.querySelectorAll(sel).forEach((e) => e.remove());
    }

    // 3. Universal Content Discovery (Catch-All Logic)
    var main = document.querySelector('main') ?? 
               document.querySelector('article') ?? 
               document.querySelector('.content') ??
               document.querySelector('#page-container') ?? 
               document.querySelector('.et-main-area') ?? 
               document.querySelector('.elementor') ??
               document.querySelector('#main-content') ??
               document.querySelector('.entry-content') ??
               document.querySelector('section') ??
               document.body;

    if (main == null) return "Engine Error: Content shell discovery failed.";

    // 4. Advanced Decoration Culling (Remove noise like %, K+, dots, blobs)
    main.querySelectorAll('*').forEach((e) {
      String cls = (e.className).toLowerCase();
      String id = (e.id).toLowerCase();
      String txt = e.text.trim();
      
      // Kill decorative patterns
      if (cls.contains('pattern') || cls.contains('shape') || cls.contains('decoration') || 
          cls.contains('divider') || cls.contains('spacer') || id.contains('dots') || id.contains('circle')) {
        if (txt.length < 50) e.remove();
      }
      
      // Kill junk tokens & isolated symbols
      if (txt == '%' || txt == 'K+' || txt == '+' || txt == '>' || txt == '»' || txt == '•') {
        e.remove();
      }

      // Kill excessively small or empty tags that bloat layout
      if (e.children.isEmpty && txt.isEmpty && e.localName != 'img') e.remove();
    });

    // 5. Image & Brand Discipline
    main.querySelectorAll('img').forEach((img) {
      String src = (img.attributes['src'] ?? '').toLowerCase();
      bool isIcon = src.contains('icon') || src.contains('logo') || src.contains('arrow') || 
                    src.contains('chevron') || (img.attributes['width'] != null && int.tryParse(img.attributes['width']!) != null && int.parse(img.attributes['width']!) < 50);
      
      if (isIcon) {
        img.attributes['style'] = 'width: 28px !important; height: 28px !important; object-fit: contain; vertical-align: middle; margin: 4px; display: inline-block;';
      } else {
        img.attributes['style'] = 'width: 100% !important; height: auto !important; border-radius: 20px; margin: 20px 0; display: block; box-shadow: 0 10px 40px rgba(0,0,0,0.06);';
      }
    });

    // 6. Sectioning: Convert List Groups to Native-Style Tiles
    main.querySelectorAll('ul').forEach((ul) {
      if (ul.text.length < 500) {
        ul.attributes['style'] = 'list-style: none; padding: 0; margin: 15px 0;';
        ul.querySelectorAll('li').forEach((li) {
          li.attributes['style'] = 'background: #F1F5F9; border: 1px solid #E2E8F0; padding: 18px; margin-bottom: 12px; border-radius: 16px; font-weight: 600; color: #334155;';
        });
      }
    });

    return main.innerHtml;
  }

  void _parseNavigation(String html) {
    var document = html_parser.parse(html);
    List<WebItem> allItems = [];
    Set<String> addedUrls = {};
    Set<String> addedLabels = {'home'};

    Uri base = Uri.parse(currentUrl!);
    String rootUrl = "${base.scheme}://${base.host}";
    
    // Always start with Home
    allItems.add(WebItem(label: 'Home', url: rootUrl, icon: Icons.home_rounded));
    addedUrls.add(rootUrl.toLowerCase().replaceAll(RegExp(r'/$'), ''));

    // Universal Nav Selectors
    var navSelectors = ['header a', 'nav a', '.menu a', '.nav-link', '.et-menu a', '.elementor-nav-menu a', '.sf-menu a'];
    
    for (var sel in navSelectors) {
      var links = document.querySelectorAll(sel);
      for (var link in links) {
        String label = link.text.trim();
        String? href = link.attributes['href'];
        
        // Advanced Filters: Exclude phone, email, and social media
        bool isNumerical = RegExp(r'[0-9]{5,}').hasMatch(label);
        bool isSocial = (href ?? '').contains('facebook.com') || (href ?? '').contains('instagram.com') || 
                        (href ?? '').contains('twitter.com') || (href ?? '').contains('linkedin.com');
        
        if (label.isEmpty || label.length > 20 || label.length < 2 || href == null || 
            href.startsWith('#') || href.contains('tel:') || href.contains('mailto:') || isNumerical || isSocial) continue;

        String absUrl = href.startsWith('http') ? href : "${base.scheme}://${base.host}/${href.startsWith('/') ? href.substring(1) : href}";
        String normUrl = absUrl.toLowerCase().replaceAll(RegExp(r'/$'), '');
        String normLabel = label.toLowerCase();

        if (addedUrls.contains(normUrl) || addedLabels.contains(normLabel)) continue;

        allItems.add(WebItem(
          label: label, 
          url: absUrl, 
          icon: _getUniversalIcon(label),
        ));
        
        addedUrls.add(normUrl);
        addedLabels.add(normLabel);
        if (allItems.length >= 10) break; 
      }
      if (allItems.length > 4) break;
    }

    if (allItems.length > 1) {
      ref.read(webProvider.notifier).updateMenu(allItems);
    }
  }

  IconData _getUniversalIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('home')) return Icons.home_rounded;
    if (l.contains('about')) return Icons.info_outline_rounded;
    if (l.contains('service')) return Icons.settings_suggest_rounded;
    if (l.contains('contact')) return Icons.alternate_email_rounded;
    if (l.contains('blog') || l.contains('news')) return Icons.article_rounded;
    if (l.contains('project') || l.contains('portfolio')) return Icons.grid_view_rounded;
    if (l.contains('career') || l.contains('team')) return Icons.people_outline_rounded;
    return Icons.explore_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webProvider);
    final isDesktop = Responsive.isSizeDesktop(context);
    final hPadding = Responsive.value(context, mobile: 16.0, tablet: 32.0, desktop: 80.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(pageTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          elevation: 0,
          backgroundColor: AppColors.appBarBg,
          surfaceTintColor: Colors.transparent,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppColors.primary, size: 28),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          actions: [
            IconButton(
              splashRadius: 24,
              icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary, size: 22),
              onPressed: () => _fetchPage(currentUrl!),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: AppColors.border.withValues(alpha: 0.3), height: 1),
          ),
        ),
        drawer: _buildPremiumDrawer(webState.menuItems),
        body: webState.isLoading 
            ? const LoadingWidget()
            : RefreshIndicator(
                onRefresh: () => _fetchPage(currentUrl!),
                color: AppColors.primary,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  child: Column(
                    children: [
                      Container(
                        constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : double.infinity),
                        padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 20),
                        child: htmlContent == null 
                            ? _buildEmptyState()
                            : HtmlWidget(
                                htmlContent!,
                                textStyle: AppTextStyles.bodyLarge.copyWith(height: 1.7, color: const Color(0xFF334155)),
                                onTapUrl: (url) {
                                  HapticFeedback.lightImpact();
                                  _fetchPage(url);
                                  return true;
                                },
                                customStylesBuilder: (el) {
                                  if (el.className.contains('native-decorative-image')) return {'display': 'none'};
                                  if (el.localName == 'h1') return {'font-size': '32px', 'font-weight': '900', 'color': '#0F172A', 'margin': '15px 0'};
                                  if (el.localName == 'h2') return {'font-size': '22px', 'font-weight': '800', 'color': '#1E293B', 'margin': '25px 0 10px'};
                                  if (el.localName == 'a') return {'color': '#4F46E5', 'text-decoration': 'none', 'font-weight': '700'};
                                  if (el.localName == 'p') return {'margin-bottom': '16px'};
                                  return null;
                                },
                              ),
                      ),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
        bottomNavigationBar: _buildPremiumBottomNav(webState),
        extendBody: true,
      ),
    );
  }

  Widget _buildPremiumDrawer(List<WebItem> items) {
    return Drawer(
      backgroundColor: AppColors.background,
      width: MediaQuery.of(context).size.width * 0.8,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(32))),
      child: Column(
        children: [
          _buildDrawerHeader(),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = item.url == currentUrl;
                return ListTile(
                  leading: Icon(item.icon ?? Icons.circle_outlined, color: isSelected ? AppColors.primary : AppColors.textSecondary, size: 24),
                  title: Text(item.label, style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, color: isSelected ? AppColors.primary : AppColors.textPrimary)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  selected: isSelected,
                  selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                  onTap: () {
                    Navigator.pop(context);
                    if (!isSelected) _fetchPage(item.url);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 70, 24, 30),
      color: AppColors.primary,
      child: const Text("Main Menu", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1)),
    );
  }

  Widget _buildEmptyState() => const Center(child: LoadingWidget());

  Widget _buildPremiumBottomNav(WebState state) {
    if (state.menuItems.isEmpty) return const SizedBox.shrink();
    final navItems = state.menuItems.take(5).toList();

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 30, offset: const Offset(0, 10))],
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: navItems.map((item) {
            final isSelected = item.url == state.currentUrl;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!isSelected) {
                    HapticFeedback.mediumImpact();
                    _fetchPage(item.url);
                  }
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: isSelected ? 1.2 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(item.icon ?? Icons.explore, color: isSelected ? AppColors.primary : const Color(0xFF94A3B8), size: 24),
                    ),
                    const SizedBox(height: 5),
                    Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, 
                      style: TextStyle(color: isSelected ? AppColors.primary : const Color(0xFF64748B), fontSize: 10, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}



