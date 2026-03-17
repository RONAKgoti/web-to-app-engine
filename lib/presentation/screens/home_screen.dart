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
    
    // 1. Remove ALL technical noise and web-specific blocks
    document.querySelectorAll('script, style, link, meta, iframe, noscript, svg, header, footer, nav, aside, .sidebar, #sidebar, .widget-area').forEach((e) => e.remove());

    // 2. Identify the "Main" content area (usually where the meat is)
    var main = document.querySelector('main') ?? 
               document.querySelector('article') ?? 
               document.querySelector('[role="main"]') ??
               document.querySelector('.page-content') ??
               document.querySelector('#content') ??
               document.body;

    if (main == null) return "No content found";

    // 3. Remove crumbs like breadcrumbs or social share bars
    main.querySelectorAll('.breadcrumbs, .sharedaddy, .social-sharing, .entry-meta').forEach((e) => e.remove());

    // 4. Force specific attributes for responsive rendering
    main.querySelectorAll('img').forEach((img) {
      img.attributes.remove('width');
      img.attributes.remove('height');
      img.attributes['style'] = 'width:100% !important; height:auto !important; display:block;';
    });

    return main.innerHtml;
  }

  void _parseNavigation(String html) {
    var document = html_parser.parse(html);
    
    // Try to find the actual site menu first
    List<dom.Element> menuLinks = document.querySelectorAll('.menu-item a, .nav-link, .nav a');
    if (menuLinks.isEmpty) {
      menuLinks = document.querySelectorAll('a');
    }

    List<WebItem> items = [];
    Set<String> addedLabels = {'home'}; // Start with Home
    
    // Always add Home
    Uri base = Uri.parse(currentUrl!);
    String homeUrl = "${base.scheme}://${base.host}";
    items.add(WebItem(label: 'Home', url: homeUrl, icon: Icons.home_rounded));

    for (var link in menuLinks) {
      String text = link.text.trim();
      String? href = link.attributes['href'];
      
      if (text.length > 2 && text.length < 15 && href != null && !addedLabels.contains(text.toLowerCase())) {
        if (!href.startsWith('http')) {
           href = "${base.scheme}://${base.host}/${href.startsWith('/') ? href.substring(1) : href}";
        }
        
        items.add(WebItem(
          label: text, 
          url: href, 
          icon: _getIconForLabel(text),
        ));
        addedLabels.add(text.toLowerCase());
        if (items.length >= 4) break;
      }
    }
    ref.read(webProvider.notifier).updateMenu(items);
  }

  IconData _getIconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('home')) return Icons.home_rounded;
    if (l.contains('about')) return Icons.info_outline_rounded;
    if (l.contains('service')) return Icons.auto_graph_rounded;
    if (l.contains('contact')) return Icons.email_rounded;
    if (l.contains('blog') || l.contains('news')) return Icons.article_rounded;
    if (l.contains('salesforce') || l.contains('cloud')) return Icons.cloud_rounded;
    if (l.contains('project')) return Icons.dashboard_customize_rounded;
    if (l.contains('team') || l.contains('career')) return Icons.people_outline_rounded;
    return Icons.arrow_forward_ios_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webProvider);
    final isDesktop = Responsive.isSizeDesktop(context);
    final horizontalPadding = Responsive.value(context, mobile: 20.0, tablet: 40.0, desktop: 80.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(pageTitle, style: AppTextStyles.headlineMedium.copyWith(fontSize: 20)),
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.appBarBg,
        surfaceTintColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 18),
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
                                  // 1. Heading Refinement
                                  if (element.localName == 'h1') return {'font-size': '32px', 'font-weight': '900', 'color': '#111827', 'margin-bottom': '20px', 'line-height': '1.1'};
                                  if (element.localName == 'h2') return {'font-size': '24px', 'font-weight': '800', 'color': '#111827', 'margin-top': '32px', 'margin-bottom': '16px'};
                                  if (element.localName == 'h3') return {'font-size': '20px', 'font-weight': '700', 'color': '#111827'};
                                  
                                  // 2. Button Detection (Native Look)
                                  final isButton = element.classes.contains('button') || element.classes.contains('btn') || element.classes.contains('wp-block-button__link');
                                  if (isButton || element.localName == 'button') {
                                    return {
                                      'background-color': '#6366F1',
                                      'color': '#FFFFFF',
                                      'padding': '16px 32px',
                                      'border-radius': '12px',
                                      'text-align': 'center',
                                      'display': 'block',
                                      'font-weight': 'bold',
                                      'margin': '24px 0',
                                      'font-size': '16px',
                                      'text-decoration': 'none'
                                    };
                                  }

                                  // 3. Section/Container Handling (Card Look)
                                  if (element.classes.contains('et_pb_column') || element.classes.contains('wp-block-column') || element.classes.contains('elementor-column')) {
                                    return {
                                      'background-color': '#FFFFFF',
                                      'padding': '24px',
                                      'border-radius': '20px',
                                      'margin': '12px 0',
                                      'box-shadow': '0 4px 6px -1px rgba(0, 0, 0, 0.1)',
                                      'border': '1px solid #F3F4F6'
                                    };
                                  }

                                  // 4. Link Cleaning
                                  if (element.localName == 'a') {
                                    return {'color': '#4F46E5', 'text-decoration': 'none', 'font-weight': '600'};
                                  }

                                  // 5. Image Decoration
                                  if (element.localName == 'img') {
                                    return {'border-radius': '16px', 'margin': '20px 0'};
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
            children: state.menuItems.map((item) {
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



