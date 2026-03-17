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
    
    // 1. Extreme Cleanup: Remove EVERYTHING that isn't core content
    document.querySelectorAll('script, style, link, meta, iframe, noscript, .wpadminbar, svg, canvas').forEach((e) => e.remove());

    // 2. Hide all common background decorative elements by class/id name
    const bgs = ['pattern', 'shape', 'dots', 'decoration', 'bg-', 'background', 'divider', 'spacer', 'overlay', 'mask', 'blob'];
    document.querySelectorAll('*').forEach((e) {
      String classes = e.className.toLowerCase();
      String id = e.id.toLowerCase();
      if (bgs.any((pattern) => classes.contains(pattern) || id.contains(pattern))) {
        // Only remove if it doesn't contain a significant amount of text
        if (e.text.trim().length < 50) e.remove();
      }
    });

    // 3. Find the meat of the page
    var main = document.querySelector('main') ?? 
               document.querySelector('article') ?? 
               document.querySelector('.content') ??
               document.querySelector('#content') ??
               document.body;

    if (main == null) return "No content found";

    // 4. Force Small Icon Sizes: Fix for the "Giant Arrow" problem
    main.querySelectorAll('img').forEach((img) {
      String src = img.attributes['src']?.toLowerCase() ?? '';
      String alt = img.attributes['alt']?.toLowerCase() ?? '';
      
      // Detection for icons/arrows/small decorators
      bool isIcon = src.contains('arrow') || src.contains('icon') || src.contains('logo') || src.contains('symbol') || 
                    src.contains('chevron') || alt.contains('arrow') || alt.contains('icon');
      
      if (isIcon) {
        img.attributes['style'] = 'width: 24px !important; height: 24px !important; object-fit: contain; margin-top: 8px;';
        img.attributes['class'] = 'native-small-icon';
      } else {
        // Real content photos get full width with rounded corners
        img.attributes['style'] = 'width: 100%; height: auto; border-radius: 16px; margin: 16px 0;';
      }
    });

    // 5. Clean up lists and empty containers that break layout
    main.querySelectorAll('div:empty, p:empty, span:empty').forEach((e) => e.remove());

    return main.innerHtml;
  }

  void _parseNavigation(String html) {
    var document = html_parser.parse(html);
    
    // 1. Universal Pro Selector: Find any standard navbar, header or menu container
    var navContainer = document.querySelector('nav') ?? 
                       document.querySelector('.menu-container') ?? 
                       document.querySelector('#main-nav') ??
                       document.querySelector('.nav-menu') ??
                       document.querySelector('.elementor-nav-menu') ??
                       document.querySelector('.et_pb_menu');

    List<dom.Element> topLevelList = [];
    if (navContainer != null) {
      // Find direct list items representing the main menu
      topLevelList = navContainer.querySelectorAll(':scope > ul > li, :scope > div > ul > li, .menu-item');
    }
    
    // Fallback: If no container, search for any list items that look like menu items
    if (topLevelList.isEmpty) {
      topLevelList = document.querySelectorAll('li.menu-item, li.nav-item, .nav-link-item');
    }

    List<WebItem> allItems = [];
    Set<String> addedUrls = {};

    Uri base = Uri.parse(currentUrl!);
    String homeUrl = "${base.scheme}://${base.host}";
    
    // Always leading with Home
    allItems.add(WebItem(label: 'Home', url: homeUrl, icon: Icons.home_rounded));
    addedUrls.add(homeUrl);

    for (var li in topLevelList) {
      var anchor = li.querySelector('a');
      if (anchor == null) continue;

      String label = anchor.text.trim();
      String? href = anchor.attributes['href'];
      
      // Filter out utility links or empty ones
      if (label.isEmpty || label.length > 20 || href == null || href.startsWith('#') || href.contains('javascript')) continue;
      
      String absUrl = href.startsWith('http') ? href : "${base.scheme}://${base.host}/${href.startsWith('/') ? href.substring(1) : href}";
      if (addedUrls.contains(absUrl)) continue;

      // Extract Sub-items (Dropdowns) for the Drawer
      List<WebItem> subItems = [];
      var subMenu = li.querySelector('ul, .dropdown, .sub-menu, .elementor-nav-menu--dropdown');
      if (subMenu != null) {
        var subAnchors = subMenu.querySelectorAll('a');
        for (var sa in subAnchors) {
          String sLabel = sa.text.trim();
          String? sHref = sa.attributes['href'];
          if (sLabel.isNotEmpty && sHref != null && !sHref.startsWith('#')) {
            String sUrl = sHref.startsWith('http') ? sHref : "${base.scheme}://${base.host}/${sHref.startsWith('/') ? sHref.substring(1) : sHref}";
            subItems.add(WebItem(label: sLabel, url: sUrl, icon: _getUniversalIcon(sLabel)));
          }
        }
      }

      allItems.add(WebItem(
        label: label, 
        url: absUrl, 
        icon: _getUniversalIcon(label),
        subItems: subItems,
      ));
      addedUrls.add(absUrl);
      
      // Limit to 12 total items to keep drawer clean but comprehensive
      if (allItems.length >= 12) break; 
    }

    // Pro State Management: Store all items in provider
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
    if (l.contains('quote') || l.contains('started')) return Icons.rocket_launch_rounded;
    if (l.contains('project')) return Icons.work_outline_rounded;
    if (l.contains('career') || l.contains('job')) return Icons.card_travel_rounded;
    if (l.contains('team')) return Icons.groups_rounded;
    if (l.contains('search')) return Icons.search_rounded;
    return Icons.explore_rounded;
  }


  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webProvider);
    final isDesktop = Responsive.isSizeDesktop(context);
    final horizontalPadding = Responsive.value(context, mobile: 20.0, tablet: 40.0, desktop: 80.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(pageTitle, style: AppTextStyles.headlineMedium.copyWith(fontSize: 18)),
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.appBarBg,
        surfaceTintColor: Colors.transparent,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppColors.primary),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            splashRadius: 24,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary, size: 22),
            onPressed: () {
              HapticFeedback.lightImpact();
              _fetchPage(currentUrl!);
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border.withValues(alpha: 0.5), height: 1),
        ),
      ),
      drawer: _buildPremiumDrawer(webState.menuItems),
      body: webState.isLoading 
          ? const LoadingWidget()
          : RefreshIndicator(
              onRefresh: () => _fetchPage(currentUrl!),
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                child: Column(
                  children: [
                    Container(
                      constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : double.infinity),
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
                      child: htmlContent == null 
                          ? _buildEmptyState()
                          : SelectionArea(
                              child: HtmlWidget(
                                htmlContent!,
                                textStyle: AppTextStyles.bodyLarge.copyWith(height: 1.6, color: AppColors.textPrimary),
                                onTapUrl: (url) {
                                  HapticFeedback.lightImpact();
                                  _fetchPage(url);
                                  return true;
                                },
                                // Native-to-Expert Mapping: Styling for Premium Look
                                customStylesBuilder: (element) {
                                  // 1. Hide decorative background patterns
                                  if (element.className.contains('native-decorative-image')) {
                                    return {'display': 'none'};
                                  }

                                  // 2. Heading Refinement
                                  if (element.localName == 'h1') return {'font-size': '26px', 'font-weight': '900', 'color': '#111827', 'margin-bottom': '12px', 'line-height': '1.2'};
                                  if (element.localName == 'h2') return {'font-size': '20px', 'font-weight': '800', 'color': '#111827', 'margin-top': '24px', 'margin-bottom': '10px'};
                                  if (element.localName == 'h3') return {'font-size': '18px', 'font-weight': 'bold', 'color': '#111827'};
                                  
                                  // 3. Section/Container Handling (Card Look)
                                  if (element.classes.contains('column') || element.classes.contains('row') || element.localName == 'section') {
                                    return {
                                      'background-color': '#FFFFFF',
                                      'padding': '16px',
                                      'border-radius': '16px',
                                      'margin': '12px 0',
                                      'border': '1px solid #F1F5F9'
                                    };
                                  }

                                  // 4. CTA Detection: Turn links into Premium Chips
                                  final text = element.text.toLowerCase();
                                  final isCTA = text.contains('details') || text.contains('touch') || text.contains('learn more') || text.contains('read more');
                                  
                                  if (isCTA && element.localName == 'a') {
                                    return {
                                      'background-color': '#EEF2FF',
                                      'color': '#4F46E5',
                                      'padding': '8px 16px',
                                      'border-radius': '20px',
                                      'display': 'inline-block',
                                      'font-weight': 'bold',
                                      'font-size': '13px',
                                      'text-decoration': 'none'
                                    };
                                  }

                                  // 5. Default Link styling
                                  if (element.localName == 'a') {
                                    return {'color': '#6366F1', 'text-decoration': 'none', 'font-weight': '600'};
                                  }
                                  
                                  return null;
                                },


                              ),
                            ),
                    ),

                    const SizedBox(height: 120), // Bottom padding for Nav
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



