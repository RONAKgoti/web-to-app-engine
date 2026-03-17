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
      
      ref.read(webProvider.notifier).setUrl(currentUrl!);
      await _fetchPage(currentUrl!);
    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  Future<void> _fetchPage(String url) async {
    if (url == currentUrl && htmlContent != null) return;
    
    try {
      ref.read(webProvider.notifier).setLoading(true);
      ref.read(webProvider.notifier).setUrl(url); // Update global state
      
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
        _parseNavigation(rawHtml);
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      ref.read(webProvider.notifier).setLoading(false);
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
    
    // 1. Core Technical Cleanup
    document.querySelectorAll('script, style, link, meta, iframe, noscript, .wpadminbar, #wpadminbar').forEach((e) => e.remove());

    // 2. Surgical Removal of Global UI Elements (Header/Footer/TopBar)
    const globalUI = [
      'header', 'footer', 'nav', '.nav', '.header', '.footer', 
      '.top-header', '.top-bar', '.et-top-navigation', '#top-header', 
      '.et_pb_menu', '.main-header', '.site-header', '.site-footer',
      '.footer-copy', '.copyright', '.social-links', '.widget-area',
      '.top-bar-left', '.top-bar-right', '.footer-widgets'
    ];
    for (var selector in globalUI) {
      document.querySelectorAll(selector).forEach((e) => e.remove());
    }

    // 3. Find the Unique Page Body
    var content = document.querySelector('.entry-content') ?? 
                  document.querySelector('.page-content') ??
                  document.querySelector('.et_pb_section') ?? 
                  document.querySelector('.elementor-section') ??
                  document.querySelector('article') ??
                  document.querySelector('#main-content') ??
                  document.querySelector('main');

    if (content == null) content = document.body;
    if (content == null) return "Content not found.";

    // 4. Ultra-Strict Image & Icon Scaling
    content.querySelectorAll('img, svg').forEach((img) {
      String src = (img.attributes['src'] ?? '').toLowerCase();
      String classes = (img.className).toLowerCase();
      String alt = (img.attributes['alt'] ?? '').toLowerCase();
      String id = (img.id).toLowerCase();
      
      // Heuristic: If it's a social icon, brand logo, or utility glyph
      bool isMiniElement = src.contains('facebook') || src.contains('twitter') || 
                           src.contains('instagram') || src.contains('linkedin') || 
                           src.contains('icon') || src.contains('logo') || 
                           src.contains('chevron') || src.contains('arrow') ||
                           classes.contains('social') || alt.contains('social') ||
                           id.contains('icon') || id.contains('social');
      
      if (isMiniElement) {
        // Strict native size for icons
        img.attributes['style'] = 'width: 32px !important; height: 32px !important; object-fit: contain !important; display: inline-block !important; margin: 6px !important;';
        img.attributes['class'] = 'native-small-icon';
      } else {
        // High-Quality content images
        img.attributes['style'] = 'width: 100% !important; height: auto !important; border-radius: 16px !important; margin: 20px 0 !important; display: block !important; box-shadow: 0 4px 20px rgba(0,0,0,0.06);';
      }
    });

    // 5. Native Hygiene: Remove disruptive web-only inline styles
    content.querySelectorAll('*').forEach((e) {
      if (e.localName != 'img') {
        e.attributes.remove('style');
        e.attributes.remove('width');
        e.attributes.remove('height');
      }
    });

    return content.innerHtml;
  }

  void _parseNavigation(String html) {
    var document = html_parser.parse(html);
    List<WebItem> allItems = [];
    Set<String> addedUrls = {};
    Set<String> addedLabels = {'home'};

    Uri base = Uri.parse(currentUrl!);
    String rootUrl = "${base.scheme}://${base.host}";
    
    allItems.add(WebItem(label: 'Home', url: rootUrl, icon: Icons.home_rounded));
    addedUrls.add(rootUrl.toLowerCase().replaceAll(RegExp(r'/$'), ''));

    var navSelectors = ['nav ul li a', 'header ul li a', '.menu-item a', '.nav-link', '.et-menu a', '.elementor-nav-menu a'];

    for (var selector in navSelectors) {
      var links = document.querySelectorAll(selector);
      for (var link in links) {
        String label = link.text.trim();
        String? href = link.attributes['href'];
        if (label.isEmpty || label.length > 25 || label.length < 2 || href == null || href.startsWith('#')) continue;
        String absUrl = href.startsWith('http') ? href : "${base.scheme}://${base.host}/${href.startsWith('/') ? href.substring(1) : href}";
        String normUrl = absUrl.toLowerCase().replaceAll(RegExp(r'/$'), '');
        String normLabel = label.toLowerCase();
        if (addedUrls.contains(normUrl) || addedLabels.contains(normLabel)) continue;
        allItems.add(WebItem(label: label, url: absUrl, icon: _getUniversalIcon(label)));
        addedUrls.add(normUrl); addedLabels.add(normLabel);
        if (allItems.length >= 12) break; 
      }
      if (allItems.length > 4) break;
    }
    ref.read(webProvider.notifier).updateMenu(allItems);
  }

  IconData _getUniversalIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('home')) return Icons.home_rounded;
    if (l.contains('about')) return Icons.info_outline_rounded;
    if (l.contains('service')) return Icons.auto_graph_rounded;
    if (l.contains('contact')) return Icons.email_rounded;
    if (l.contains('blog') || l.contains('news')) return Icons.article_rounded;
    if (l.contains('salesforce')) return Icons.cloud_queue_rounded;
    return Icons.explore_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webProvider);
    final isDesktop = Responsive.isSizeDesktop(context);
    final horizontalPadding = Responsive.value(context, mobile: 18.0, tablet: 36.0, desktop: 72.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(pageTitle, style: AppTextStyles.headlineMedium.copyWith(fontSize: 17, letterSpacing: -0.5)),
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.appBarBg,
        surfaceTintColor: Colors.transparent,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort_rounded, color: AppColors.primary, size: 26), // Premium icon
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            splashRadius: 24,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary, size: 22),
            onPressed: () {
              HapticFeedback.mediumImpact();
              _fetchPage(currentUrl!);
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border.withValues(alpha: 0.4), height: 1),
        ),
      ),
      drawer: _buildPremiumDrawer(webState.menuItems),
      body: webState.isLoading 
          ? const LoadingWidget()
          : RefreshIndicator(
              onRefresh: () => _fetchPage(currentUrl!),
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    Container(
                      constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : double.infinity),
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 20),
                      child: htmlContent == null 
                          ? _buildEmptyState()
                          : SelectionArea(
                              child: HtmlWidget(
                                htmlContent!,
                                textStyle: AppTextStyles.bodyLarge.copyWith(height: 1.5, color: AppColors.textPrimary, fontSize: 15),
                                onTapUrl: (url) {
                                  HapticFeedback.lightImpact();
                                  _fetchPage(url);
                                  return true;
                                },
                                customStylesBuilder: (element) {
                                  // 1. Force Scaling for Heading Elements
                                  if (element.localName == 'h1') return {'font-size': '24px', 'font-weight': '800', 'color': '#1E293B', 'margin': '16px 0 8px 0', 'line-height': '1.2'};
                                  if (element.localName == 'h2') return {'font-size': '20px', 'font-weight': '700', 'color': '#334155', 'margin': '24px 0 8px 0'};
                                  if (element.localName == 'h3') return {'font-size': '18px', 'font-weight': '600', 'color': '#475569'};
                                  
                                  // 2. Native Cards for Sections
                                  if (element.localName == 'section' || element.classes.contains('et_pb_section')) {
                                    return {'padding': '0', 'margin': '0 0 24px 0', 'background': 'transparent'};
                                  }
                                  
                                  if (element.classes.contains('et_pb_column')) {
                                    return {
                                      'background-color': '#FFFFFF',
                                      'padding': '20px',
                                      'border-radius': '20px',
                                      'margin': '12px 0',
                                      'box-shadow': '0 2px 15px rgba(0,0,0,0.03)',
                                      'border': '1px solid #F1F5F9'
                                    };
                                  }

                                  // 3. Prevent Oversized Social Icons (Fallback CSS)
                                  if (element.localName == 'img') {
                                     final src = (element.attributes['src'] ?? '').toLowerCase();
                                     if (src.contains('facebook') || src.contains('twitter') || src.contains('logo')) {
                                       return {'width': '32px', 'height': '32px', 'object-fit': 'contain'};
                                     }
                                  }

                                  // 4. Clean CTA Buttons
                                  if (element.localName == 'a' && (element.text.length < 20)) {
                                    final text = element.text.toLowerCase();
                                    if (text.contains('more') || text.contains('touch') || text.contains('get')) {
                                      return {
                                        'background-color': '#4F46E5',
                                        'color': '#FFFFFF',
                                        'padding': '10px 20px',
                                        'border-radius': '25px',
                                        'display': 'inline-block',
                                        'font-weight': '600',
                                        'font-size': '14px',
                                        'text-decoration': 'none',
                                        'margin': '8px 0'
                                      };
                                    }
                                  }

                                  return null;
                                },
                              ),
                            ),
                    ),
                    const SizedBox(height: 120), 
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _buildPremiumBottomNav(webState),
      extendBody: true,
    );
  }

  Widget _buildPremiumDrawer(List<WebItem> items) {
    return Drawer(
      backgroundColor: AppColors.background,
      width: MediaQuery.of(context).size.width * 0.85,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
      child: Column(
        children: [
          _buildDrawerHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: items.map((item) => _buildDrawerItem(item)).toList(),
            ),
          ),
          _buildDrawerFooter(),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: BoxDecoration(
        color: AppColors.primary,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            "Native Pro Navigation", 
            style: AppTextStyles.headlineMedium.copyWith(color: Colors.white, fontSize: 18)
          ),
          Text(
            "Universal Website Mapping", 
            style: AppTextStyles.labelSmall.copyWith(color: Colors.white.withValues(alpha: 0.7))
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(WebItem item) {
    if (item.subItems.isNotEmpty) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(item.icon ?? Icons.explore_rounded, color: AppColors.primary, size: 22),
          title: Text(item.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          childrenPadding: const EdgeInsets.only(left: 32),
          children: item.subItems.map((sub) => _buildDrawerSubItem(sub)).toList(),
        ),
      );
    }

    return ListTile(
      leading: Icon(item.icon ?? Icons.circle, color: AppColors.primary, size: 22),
      title: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () {
        Navigator.pop(context);
        _fetchPage(item.url);
      },
    );
  }

  Widget _buildDrawerSubItem(WebItem sub) {
    return ListTile(
      dense: true,
      title: Text(sub.label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
      onTap: () {
        Navigator.pop(context);
        _fetchPage(sub.url);
      },
    );
  }

  Widget _buildDrawerFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Text("Version 2.0.0", style: AppTextStyles.labelSmall.copyWith(fontSize: 10)),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 64, color: AppColors.textHint),
          SizedBox(height: 16),
          Text("Waiting for content...", style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildPremiumBottomNav(WebState state) {
    if (state.menuItems.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10), // Perfectly floating
        height: 68,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.9), // Glass feel
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 25,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: state.menuItems.take(5).map((item) {
              final isSelected = item.url == state.currentUrl;
              return _buildNavItem(item, isSelected);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(WebItem item, bool isSelected) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (!isSelected) {
              HapticFeedback.lightImpact();
              _fetchPage(item.url);
            }
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                padding: EdgeInsets.symmetric(horizontal: isSelected ? 18 : 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item.icon ?? Icons.circle, 
                  color: isSelected ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.7),
                  size: isSelected ? 24 : 22,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label, 
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 10,
                  letterSpacing: 0.2,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



