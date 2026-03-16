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
  final Dio _dio = Dio();

  @override
  void initState() {
    super.initState();
    _loadAndFetch();
  }

  Future<void> _loadAndFetch() async {
    String content = await rootBundle.loadString('assets/url.txt');
    currentUrl = content.trim();
    if (!currentUrl!.startsWith('http')) currentUrl = 'https://$currentUrl';
    
    ref.read(webProvider.notifier).setUrl(currentUrl!);
    await _fetchPage(currentUrl!);
  }

  Future<void> _fetchPage(String url) async {
    try {
      ref.read(webProvider.notifier).setLoading(true);
      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        setState(() {
          htmlContent = response.data.toString();
        });
        _parseNavigation(response.data.toString());
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      ref.read(webProvider.notifier).setLoading(false);
    }
  }

  void _parseNavigation(String html) {
    var document = html_parser.parse(html);
    List<dom.Element> links = document.querySelectorAll('a');
    List<WebItem> items = [];
    
    for (var link in links) {
      String text = link.text.trim();
      String? href = link.attributes['href'];
      if (text.length > 2 && text.length < 15 && href != null) {
        if (!href.startsWith('http')) {
           Uri base = Uri.parse(currentUrl!);
           href = "${base.scheme}://${base.host}$href";
        }
        items.add(WebItem(label: text, url: href));
        if (items.length >= 4) break;
      }
    }
    ref.read(webProvider.notifier).updateMenu(items);
  }

  @override
  Widget build(BuildContext context) {
    final webState = ref.watch(webProvider);
    final padding = Responsive.value(context, mobile: 16.0, tablet: 24.0, desktop: 32.0);

    return Scaffold(
      appBar: AppBar(
        title: Text("NATIVE WEB ENGINE", style: AppTextStyles.headlineMedium),
        leading: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _fetchPage(currentUrl!),
          ),
        ],
      ),
      body: webState.isLoading 
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: htmlContent == null 
                  ? const Center(child: Text("Unable to load native content"))
                  : SelectionArea(
                      child: HtmlWidget(
                        htmlContent!,
                        textStyle: AppTextStyles.bodyLarge,
                        onTapUrl: (url) {
                          _fetchPage(url);
                          return true;
                        },
                        // Expert Mapping: Mapping HTML tags to native looks
                        customStylesBuilder: (element) {
                          if (element.localName == 'header' || element.localName == 'footer' || element.className.contains('nav')) {
                            return {'display': 'none'}; // Absolute Law: Hide web nav parts
                          }
                          return null;
                        },
                      ),
                    ),
            ),
      bottomNavigationBar: webState.menuItems.isNotEmpty ? _buildNativeBottomNav(webState.menuItems) : null,
    );
  }

  Widget _buildNativeBottomNav(List<WebItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.map((item) => _buildNavItem(item)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(WebItem item) {
    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        _fetchPage(item.url);
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.navigation_rounded, color: AppColors.primary, size: 24),
            const SizedBox(height: 4),
            Text(item.label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
