import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/web_item.dart';
import '../providers/web_provider.dart';
import '../widgets/states/loading_error_widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _defaultTitle = 'Welcome';
  static const _defaultSubtitle = 'Secure app experience';
  static const _defaultSiteName = 'Business Portal';
  static const _prefsWebsiteUrlKey = 'website_url';
  static const _prefsMenuCachePrefix = 'website_menu_';

  String? htmlContent;
  String? currentUrl;
  String? initialUrl;
  String pageTitle = _defaultTitle;
  String pageSubtitle = _defaultSubtitle;
  String siteDisplayName = _defaultSiteName;
  String? errorMessage;
  int loadingProgress = 0;
  bool canGoBack = false;
  bool canGoForward = false;
  bool isPagePresentationReady = false;
  late Dio _dio;
  WebViewController? _controller;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<String> _history = [];
  String? _requestedUrl;
  String? _lastSuccessfulUrl;

  bool get _supportsWebViewPlatform {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return false;
    }
  }

  bool get _usesWebView => _supportsWebViewPlatform && _controller != null;

  bool get _canStepBack => _usesWebView ? canGoBack : _history.isNotEmpty;

  bool get _isOnHomePage {
    final home = Uri.tryParse(initialUrl ?? '');
    final current = Uri.tryParse(currentUrl ?? initialUrl ?? '');
    if (home == null || current == null) return true;
    if (home.host != current.host) return false;

    final homePath = home.path.isEmpty ? '/' : home.path;
    final currentPath = current.path.isEmpty ? '/' : current.path;
    return currentPath == homePath || currentPath == '/';
  }

  String get _appBarSupportingText {
    final cleanedTitle = pageTitle.trim();
    if (!_isOnHomePage &&
        cleanedTitle.isNotEmpty &&
        cleanedTitle != _defaultTitle) {
      return cleanedTitle;
    }
    return pageSubtitle;
  }

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36',
      },
    ));
    if (_supportsWebViewPlatform) {
      _controller = _buildWebViewController();
    }
    _loadAndFetch();
  }

  WebViewController _buildWebViewController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => loadingProgress = progress);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url == null || url.isEmpty) return;
            _requestedUrl = url;
            _updateCurrentUrl(url);
            unawaited(_refreshNativePresentation());
          },
          onPageStarted: (url) {
            _requestedUrl = url;
            _clearError();
            _setLoading(true);
            _updateCurrentUrl(url);
            setState(() {
              loadingProgress = 0;
              isPagePresentationReady = false;
            });
          },
          onPageFinished: (url) async {
            _requestedUrl = null;
            _lastSuccessfulUrl = url;
            _updateCurrentUrl(url);
            await _syncBrowserState();
            await _syncPageMetadata();
            await _syncNavigationMenu();
            await _preparePageForDisplay();
            _setLoading(false);
            if (mounted) {
              setState(() {
                loadingProgress = 100;
                isPagePresentationReady = true;
              });
            }
          },
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            final isWebUrl = uri.scheme == 'http' || uri.scheme == 'https';
            if (isWebUrl) return NavigationDecision.navigate;

            await _launchExternalUrl(uri);
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            final rawDescription = error.description.trim();
            final lower = rawDescription.toLowerCase();
            if (lower.contains('err_aborted')) return;
            if (error.errorType == WebResourceErrorType.unsupportedScheme) {
              final uri = Uri.tryParse(error.url ?? '');
              if (uri != null) {
                unawaited(_launchExternalUrl(uri));
              }
              return;
            }

            final failedKey = _urlKeyOrNull(error.url);
            final requestedKey = _urlKeyOrNull(_requestedUrl);
            final currentKey = _urlKeyOrNull(currentUrl);
            final successKey = _urlKeyOrNull(_lastSuccessfulUrl);
            final looksStaleFailure = failedKey != null &&
                failedKey != requestedKey &&
                failedKey != currentKey &&
                failedKey != successKey;
            if (looksStaleFailure) return;

            _setLoading(false);
            if (!mounted) return;
            setState(() {
              isPagePresentationReady = true;
              errorMessage = _friendlyErrorMessage(rawDescription);
            });
          },
        ),
      );
  }

  Future<void> _loadAndFetch() async {
    try {
      final url = await _resolveStartupUrl();
      await _applyWebsite(url, persist: false);
    } catch (e) {
      debugPrint("Init Error: $e");
      _setLoading(false);
      if (!mounted) return;
      setState(() {
        errorMessage = 'Could not find your website URL. Check assets/url.txt.';
        htmlContent = _buildErrorHtml(
          "Cloud Sync Error",
          "Could not find your website URL. Check assets/url.txt",
        );
      });
    }
  }

  Future<void> _fetchPage(String url, {bool addToHistory = true}) async {
    if (_usesWebView) {
      await _loadUrlInBrowser(url);
      return;
    }
    if (url.isEmpty) return;
    final normNew = url.toLowerCase().replaceAll(RegExp(r'/$'), '');
    final normCurrent = currentUrl?.toLowerCase().replaceAll(RegExp(r'/$'), '');

    if (normNew == normCurrent && htmlContent != null) return;

    try {
      _clearError();
      _setLoading(true);
      final previousUrl = currentUrl;

      setState(() {
        htmlContent = null;
        if (addToHistory && previousUrl != null && normNew != normCurrent) {
          _history.add(previousUrl);
        }
        currentUrl = url;
      });

      final response = await _dio.get(url);

      if (response.statusCode == 200) {
        final rawHtml = response.data.toString();
        final cleanedHtml = _expertCleanHtml(rawHtml, url);
        if (!mounted) return;
        setState(() {
          htmlContent = cleanedHtml;
        });
        _extractPageTitle(rawHtml);
        _applyMenuItems(_extractNavigationItemsFromHtml(rawHtml, url));
        ref.read(webProvider.notifier).setUrl(url);
        _updatePageSubtitle(url);
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
      String errTitle = "Connection issue";
      String errMsg =
          "The website is taking longer than expected. Tap retry to try again.";
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        errTitle = "No internet";
        errMsg = "Please check your network and try loading the page again.";
      } else if (e is DioException &&
          e.type == DioExceptionType.connectionTimeout) {
        errTitle = "Website timeout";
        errMsg =
            "The website did not respond in time. Tap retry to load it again.";
      }
      if (!mounted) return;
      setState(() {
        errorMessage = errMsg;
        htmlContent = _buildErrorHtml(errTitle, errMsg);
      });
    } finally {
      _setLoading(false);
    }
  }

  String _buildErrorHtml(String title, String msg) {
    return """
    <div style='padding:60px 20px; text-align:center; font-family: sans-serif; background:#F8FAFC; min-height:60vh;'>
      <h2 style='color:#1E293B; font-weight:900;'>$title</h2>
      <p style='color:#64748B; line-height:1.6;'>$msg</p>
      <div style='margin-top:20px; padding:12px 18px; background:#0F172A; color:white; border-radius:999px; display:inline-block; font-weight:700;'>TRY AGAIN</div>
    </div>
    """;
  }

  void _handleBack() {
    unawaited(_handleBackPressed());
  }

  Future<void> _handleBackPressed() async {
    if (ref.read(webProvider).isLoading) return;

    if (_isOnHomePage) {
      await SystemNavigator.pop();
      return;
    }

    if (_usesWebView) {
      final controller = _controller;
      if (controller != null && await controller.canGoBack()) {
        await controller.goBack();
        await _syncBrowserState();
        return;
      }
      await SystemNavigator.pop();
      return;
    }

    if (_history.isNotEmpty) {
      final previousUrl = _history.removeLast();
      await _fetchPage(previousUrl, addToHistory: false);
      return;
    }

    await SystemNavigator.pop();
  }

  void _extractPageTitle(String html) {
    try {
      var document = html_parser.parse(html);
      var rawTitle = document.querySelector('title')?.text ?? "";
      String title = rawTitle.split('|').first.split('-').first.trim();
      if (title.isEmpty) title = _defaultTitle;
      final nextTitle =
          title.length > 24 ? "${title.substring(0, 21)}..." : title;
      setState(() => pageTitle = nextTitle);
    } catch (_) {
      setState(() => pageTitle = _defaultTitle);
    }
  }

  String _expertCleanHtml(String html, String baseUrl) {
    var document = html_parser.parse(html);
    final baseUri = Uri.tryParse(baseUrl);

    // 1. Surgical Noise Removal
    document
        .querySelectorAll(
            'script, style, link, meta, iframe, noscript, .wpadminbar, .et_pb_menu, #wpadminbar, .mobile_menu, .et_mobile_menu, header, footer, .footer, .tp-bullets, .mobile_nav')
        .forEach((e) => e.remove());

    // 2. Clear Global Junk
    var siteUI = [
      'nav',
      '.top-bar',
      '.footer-bottom',
      '#main-header',
      '#main-footer',
      '.elementor-location-header',
      '.elementor-location-footer',
      '.mobile-header'
    ];
    for (var sel in siteUI) {
      document.querySelectorAll(sel).forEach((e) => e.remove());
    }

    // 3. Ultra-Greedy Shell Selection
    var selectors = [
      '#page-container',
      '.et-main-area',
      '.elementor',
      'main',
      '#main-content',
      '.entry-content',
      'article',
      '.content',
      '.site-content'
    ];
    dom.Element? main;
    for (var sel in selectors) {
      var found = document.querySelector(sel);
      if (found != null && found.text.trim().length > 100) {
        main = found;
        break;
      }
    }
    main ??= document.body;

    // Greedy Fallback: If standard shells fail, pick largest text-heavy div
    if (main == document.body) {
      int maxLen = 0;
      document.body?.querySelectorAll('div, section').forEach((el) {
        int len = el.text.trim().length;
        if (len > maxLen && len > 200) {
          maxLen = len;
          main = el;
        }
      });
    }

    if (main == null) return "Discovery Ready.";

    if (baseUri != null) {
      _absolutizeMediaAndLinks(main!, baseUri);
    }

    // 4. Pattern/Symbol Sterilization
    main!.querySelectorAll('*').forEach((e) {
      final txt = e.text.trim();
      final cls = e.className.toLowerCase();
      const noiseTokens = {'%', 'K+', '+', '>', 'Â»', 'â€¢', 'âœ“', '::', '|'};
      if (noiseTokens.contains(txt) ||
          txt == 'K+' ||
          txt == '+' ||
          txt == '>' ||
          txt == '»' ||
          txt == '•' ||
          txt == '✓' ||
          txt == '::' ||
          txt == '|') {
        e.remove();
      }
      if ((cls.contains('pattern') ||
              cls.contains('shape') ||
              cls.contains('dots') ||
              cls.contains('divider')) &&
          txt.length < 50) {
        e.remove();
      }
      if (e.attributes['style']?.contains('background-image') ?? false) {
        e.attributes['style'] = e.attributes['style']!
            .replaceAll(RegExp(r'background-image:[^;]+;'), '');
      }
    });

    // 5. Image & Card Aesthetic Transformation
    main!.querySelectorAll('img').forEach((img) {
      String src = (img.attributes['src'] ?? '').toLowerCase();
      bool small = src.contains('icon') ||
          src.contains('logo') ||
          src.contains('tick') ||
          (img.attributes['width'] != null &&
              int.tryParse(img.attributes['width']!) != null &&
              int.parse(img.attributes['width']!) < 60);
      if (small) {
        img.attributes['style'] =
            'width: 32px; height: 32px; object-fit: contain; display: inline-block; vertical-align: middle; margin: 4px;';
      } else {
        img.attributes['style'] =
            'width: 100%; height: auto; border-radius: 24px; margin: 24px 0; display: block; box-shadow: 0 16px 40px rgba(0,0,0,0.06);';
      }
    });

    main!.querySelectorAll('ul').forEach((ul) {
      if (ul.text.length < 600) {
        ul.attributes['style'] =
            'list-style: none; padding: 0; margin: 24px 0;';
        ul.querySelectorAll('li').forEach((li) {
          li.attributes['style'] =
              'background: #FFFFFF; border: 1.5px solid #F1F5F9; padding: 22px; margin-bottom: 14px; border-radius: 20px; font-weight: 700; color: #1E293B; box-shadow: 0 4px 10px rgba(0,0,0,0.03); display: flex; align-items: center;';
        });
      }
    });

    return main!.innerHtml;
  }

  void _absolutizeMediaAndLinks(dom.Element root, Uri baseUri) {
    for (final element in root.querySelectorAll('[src], [href]')) {
      final src = element.attributes['src'];
      if (src != null && src.isNotEmpty) {
        element.attributes['src'] = baseUri.resolve(src).toString();
      }

      final href = element.attributes['href'];
      if (href != null && href.isNotEmpty && !href.startsWith('#')) {
        element.attributes['href'] = baseUri.resolve(href).toString();
      }
    }
  }

  Future<void> _loadUrlInBrowser(String url) async {
    final controller = _controller;
    if (controller == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _setLoading(false);
      if (!mounted) return;
      setState(() {
        errorMessage =
            'The website address is not valid. Please update the website URL and try again.';
      });
      return;
    }

    _requestedUrl = url;
    _clearError();
    _setLoading(true);
    _updateCurrentUrl(url);
    if (mounted) {
      setState(() {
        loadingProgress = 0;
        isPagePresentationReady = false;
      });
    }
    try {
      await controller.loadRequest(uri);
    } catch (e) {
      debugPrint('Load request failed: $e');
      _setLoading(false);
      if (!mounted) return;
      setState(() {
        isPagePresentationReady = true;
        errorMessage =
            'The website could not be opened right now. Please try again in a moment.';
      });
    }
  }

  Future<String> _resolveStartupUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_prefsWebsiteUrlKey);
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      return _normalizeWebsiteUrl(savedUrl);
    }

    final fileContent = await rootBundle.loadString('assets/url.txt');
    return _normalizeWebsiteUrl(fileContent);
  }

  String _normalizeWebsiteUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw StateError('Website URL is empty.');
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    return 'https://$trimmed';
  }

  String _menuCacheKey(String url) {
    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? 'default').replaceAll('.', '_');
    return '$_prefsMenuCachePrefix$host';
  }

  Future<List<WebItem>> _readCachedMenu(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_menuCacheKey(url));
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = json.decode(raw);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .whereType<Map>()
          .map((item) {
            final label = (item['label'] ?? '').toString().trim();
            final itemUrl = (item['url'] ?? '').toString().trim();
            if (label.isEmpty || itemUrl.isEmpty) {
              return null;
            }
            return WebItem(
              label: label,
              url: itemUrl,
              icon: _iconForLabel(label),
            );
          })
          .whereType<WebItem>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _cacheMenuItems(String url, List<WebItem> items) async {
    if (items.length < 2) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final payload = items
        .map((item) => {
              'label': item.label,
              'url': item.url,
            })
        .toList();
    await prefs.setString(_menuCacheKey(url), json.encode(payload));
  }

  Future<void> _prefetchMenuItems(String url) async {
    try {
      final response = await _dio.get(url);
      if (response.statusCode != 200) {
        return;
      }

      final items = _buildMenuItemsFromRaw(
        _extractNavigationItemsFromHtml(response.data.toString(), url),
        activeUrl: url,
      );
      if (items.length < 2 || !mounted) {
        return;
      }

      ref.read(webProvider.notifier).updateMenu(items);
      unawaited(_cacheMenuItems(url, items));
    } catch (e) {
      debugPrint('Prefetch menu failed: $e');
    }
  }

  Future<void> _applyWebsite(String url, {required bool persist}) async {
    final normalizedUrl = _normalizeWebsiteUrl(url);
    final cachedMenu = await _readCachedMenu(normalizedUrl);

    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsWebsiteUrlKey, normalizedUrl);
    }

    _history.clear();
    ref.read(webProvider.notifier).updateMenu(cachedMenu);
    ref.read(webProvider.notifier).setUrl(normalizedUrl);

    if (!mounted) return;
    setState(() {
      initialUrl = normalizedUrl;
      currentUrl = normalizedUrl;
      htmlContent = null;
      pageTitle = _defaultTitle;
      siteDisplayName = _defaultSiteName;
      errorMessage = null;
      loadingProgress = 0;
      canGoBack = false;
      canGoForward = false;
      isPagePresentationReady = false;
    });
    _updatePageSubtitle(normalizedUrl);
    unawaited(_prefetchMenuItems(normalizedUrl));

    if (_usesWebView) {
      await _loadUrlInBrowser(normalizedUrl);
      return;
    }

    await _fetchPage(normalizedUrl, addToHistory: false);
  }

  Future<void> _syncPageMetadata() async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final title = await controller.getTitle();
    if (!mounted) return;

    setState(() {
      pageTitle = _sanitizeTitle(title);
    });
    _updatePageSubtitle(currentUrl ?? initialUrl);
  }

  Future<void> _syncNavigationMenu() async {
    final controller = _controller;
    final activeUrl = currentUrl ?? initialUrl;
    if (controller == null || activeUrl == null) return;

    try {
      const script = r'''
        (() => {
          const normalizeLabel = (value) => (value || '')
            .replace(/\s+/g, ' ')
            .trim();

          const invalidLabelPattern = /read more|learn more|view more|click here|book now|download|watch now|apply now|buy now|see all/i;
          const currentHost = window.location.host.replace(/^www\./i, '');

          const isSameSite = (url) => {
            const host = url.host.replace(/^www\./i, '');
            return host === currentHost ||
              host.endsWith(`.${currentHost}`) ||
              currentHost.endsWith(`.${host}`);
          };

          const toItem = (anchor) => {
            const label = normalizeLabel(
              anchor.innerText ||
              anchor.textContent ||
              anchor.getAttribute('aria-label') ||
              ''
            );
            const href = anchor.getAttribute('href') || anchor.href || '';
            if (!label || label.length < 2 || label.length > 24) return null;
            if (invalidLabelPattern.test(label)) return null;
            if (!href || href.startsWith('#') || /^mailto:|^tel:/i.test(href)) return null;

            try {
              const url = new URL(href, window.location.href);
              if (!/^https?:$/i.test(url.protocol)) return null;
              if (!isSameSite(url)) return null;
              if (/facebook|instagram|twitter|linkedin|youtube|whatsapp/i.test(url.toString())) return null;
              return { label, url: url.toString() };
            } catch (_) {
              return null;
            }
          };

          const collectItems = (container) => {
            const seen = new Set();
            const items = [];

            for (const anchor of Array.from(container.querySelectorAll('a[href]'))) {
              const item = toItem(anchor);
              if (!item) continue;

              const key = `${item.label.toLowerCase()}|${item.url.replace(/\/$/, '').toLowerCase()}`;
              if (seen.has(key)) continue;
              seen.add(key);
              items.push(item);
            }

            return items;
          };

          const scoreContainer = (container, items) => {
            if (items.length < 2 || items.length > 8) return -1;

            const rect = container.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) return -1;
            if (rect.height > window.innerHeight * 0.42) return -1;

            const identity = `${container.tagName.toLowerCase()} ${container.id || ''} ${typeof container.className === 'string' ? container.className : ''}`.toLowerCase();
            const text = normalizeLabel(container.innerText || '').toLowerCase();
            const computed = window.getComputedStyle(container);
            const shortLabels = items.filter((item) => item.label.length <= 14).length;
            const nearTop = rect.top <= Math.max(220, window.innerHeight * 0.22);
            const nearBottom = rect.bottom >= window.innerHeight - Math.max(220, window.innerHeight * 0.22);
            const pinned = computed.position === 'fixed' || computed.position === 'sticky';
            const keywordMatch = /nav|menu|tab|toolbar|bottom|footer|header|category|section/.test(identity);
            const textPenalty = Math.max(0, text.length - 180);

            return (items.length * 90) +
              (shortLabels * 20) +
              (nearTop ? 40 : 0) +
              (nearBottom ? 55 : 0) +
              (pinned ? 70 : 0) +
              (keywordMatch ? 80 : 0) -
              textPenalty;
          };

          const selectors = [
            'nav',
            '[role="navigation"]',
            'header',
            'footer',
            '.menu',
            '.navbar',
            '.nav',
            '.tab-bar',
            '.bottom-nav',
            '.bottom-navigation',
            '.mobile-nav',
            '.mobile-menu',
            '.elementor-nav-menu',
            '.et-menu',
            '[class*="nav"]',
            '[class*="menu"]',
            '[class*="tab"]',
            '[class*="bottom"]',
            '[id*="nav"]',
            '[id*="menu"]',
            '[id*="tab"]',
            '[id*="bottom"]'
          ];

          const containers = [];
          const seenNodes = new Set();
          for (const selector of selectors) {
            for (const node of Array.from(document.querySelectorAll(selector))) {
              if (seenNodes.has(node)) continue;
              seenNodes.add(node);
              containers.push(node);
            }
          }

          const ranked = containers
            .map((container) => {
              const items = collectItems(container);
              return {
                container,
                items,
                score: scoreContainer(container, items),
              };
            })
            .filter((entry) => entry.score > 0)
            .sort((a, b) => b.score - a.score);

          ranked.slice(0, 3).forEach((entry) => {
            entry.container.setAttribute('data-native-app-chrome', '1');
            const owner = entry.container.closest('header, nav, footer, [role="navigation"], [role="banner"], [role="contentinfo"]');
            if (owner) {
              owner.setAttribute('data-native-app-chrome', '1');
            }
          });

          const best = ranked[0]?.items ?? [];
          return JSON.stringify(best.slice(0, 12));
        })();
      ''';

      final result = await controller.runJavaScriptReturningResult(script);
      final links = _decodeNavigationItemsFromJsResult(result);
      _applyMenuItems(links, activeUrl: activeUrl);
    } catch (e) {
      debugPrint('Navigation sync failed: $e');
    }
  }

  Future<void> _applyNativeChromeHiding() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      const script = r'''
        (() => {
          const chromeSelectors = [
            'header',
            'nav',
            '[role="banner"]',
            '[role="navigation"]',
            '.top-bar',
            '.topbar',
            '.header-top',
            '.header-bottom',
            '.header-main',
            '.site-header',
            '.main-header',
            '.mobile-header',
            '.mobile_nav',
            '.mobile-menu',
            '.menu-toggle',
            '.navbar',
            '.et_mobile_menu',
            '.elementor-location-header',
            '.et-l--header',
            '.ast-above-header-wrap',
            '.ast-primary-header-bar',
            '.ast-mobile-header-wrap',
            '#main-header',
            '#masthead',
            '#top-bar',
            '#header',
            '#site-header',
            '[data-elementor-type="header"]'
          ];
          const viewportContent = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
          let viewport = document.querySelector('meta[name="viewport"]');
          if (!viewport) {
            viewport = document.createElement('meta');
            viewport.setAttribute('name', 'viewport');
            document.head.appendChild(viewport);
          }
          viewport.setAttribute('content', viewportContent);

          const styleId = 'native-app-shell-style';
          let style = document.getElementById(styleId);
          if (!style) {
            style = document.createElement('style');
            style.id = styleId;
            style.textContent = `
              * {
                box-sizing: border-box !important;
              }

              html {
                overflow-x: hidden !important;
                -webkit-text-size-adjust: 100% !important;
                text-size-adjust: 100% !important;
              }

              html, body, #page, #content, main, .site, .site-content {
                margin-top: 0 !important;
                padding-top: 0 !important;
                scroll-padding-top: 0 !important;
              }

              body {
                overflow-x: hidden !important;
                background: #FFFFFF !important;
                touch-action: pan-y !important;
              }

              img,
              picture,
              video,
              canvas,
              svg,
              iframe {
                max-width: 100% !important;
              }

              img,
              picture,
              video {
                height: auto !important;
              }
            `;
            document.head.appendChild(style);
          }

          const hideElement = (el) => {
            if (!el || el.dataset.nativeAppHidden === '1') return;
            el.dataset.nativeAppHidden = '1';
            el.style.setProperty('display', 'none', 'important');
            el.style.setProperty('visibility', 'hidden', 'important');
            el.style.setProperty('pointer-events', 'none', 'important');
            el.style.setProperty('max-height', '0px', 'important');
            el.style.setProperty('min-height', '0px', 'important');
            el.style.setProperty('height', '0px', 'important');
            el.style.setProperty('margin', '0px', 'important');
            el.style.setProperty('padding', '0px', 'important');
            el.style.setProperty('overflow', 'hidden', 'important');
          };

          const textFor = (el) => `${el.innerText || ''}`
            .replace(/\s+/g, ' ')
            .trim()
            .toLowerCase();

          const identityFor = (el) =>
            `${el.tagName.toLowerCase()} ${el.id || ''} ${typeof el.className === 'string' ? el.className : ''} ${textFor(el).slice(0, 120)}`.toLowerCase();

          const looksLikeContent = (el, rect, text) => {
            if (rect.height > window.innerHeight * 0.55) return true;
            if (text.length > 420) return true;
            if (el.querySelectorAll('main, article, form').length > 0) return true;
            if (el.querySelectorAll('p, h1, h2, h3, h4').length >= 6) return true;
            return false;
          };

          const isLikelyChromeBar = (el) => {
            if (!el) return false;
            const rect = el.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) return false;
            if (rect.width < window.innerWidth * 0.45) return false;

            const computed = window.getComputedStyle(el);
            const text = textFor(el);
            const identity = identityFor(el);
            if (looksLikeContent(el, rect, text)) return false;

            const nearTop = rect.top <= Math.max(180, window.innerHeight * 0.22);
            const nearBottom = rect.bottom >= window.innerHeight - Math.max(180, window.innerHeight * 0.22);
            const limitedHeight = rect.height <= Math.max(260, window.innerHeight * 0.36);
            const linkCount = el.querySelectorAll('a[href]').length;
            const actionCount = el.querySelectorAll('button, [role="button"]').length;
            const hasLogoImage = el.querySelector('img[src*="logo"], img[alt*="logo" i], [class*="logo"], [id*="logo"]') !== null;
            const pinned = computed.position === 'fixed' || computed.position === 'sticky';
            const keywordMatch = /header|topbar|top-bar|nav|menu|toolbar|masthead|branding|social|contact|phone|call|logo|footer|bottom|tabbar|tab-bar|bottomnav|bottom-nav/.test(identity);
            const socialMatch = /facebook|instagram|twitter|linkedin|pinterest|youtube|whatsapp/.test(identity);
            const phoneMatch = /\+?\d[\d\s\-()]{6,}/.test(text);
            const compactBrandBar = hasLogoImage && rect.height <= Math.max(220, window.innerHeight * 0.3) && (actionCount >= 1 || linkCount >= 1);
            const compactBottomBar = nearBottom && limitedHeight && (linkCount >= 2 || actionCount >= 1);

            return (nearTop || nearBottom || pinned) &&
              limitedHeight &&
              (keywordMatch || socialMatch || phoneMatch || compactBrandBar || compactBottomBar || linkCount >= 3 || (pinned && (linkCount >= 2 || actionCount >= 1)));
          };

          const findMainContent = () => {
            const selectors = [
              'main > *',
              '[role="main"] > *',
              '#content > *',
              '#main-content > *',
              '.site-content > *',
              '.entry-content > *',
              'article > *',
              '.elementor-section',
              'section',
              '[class*="hero"]',
              '[class*="banner"]'
            ];

            const candidates = [];
            for (const selector of selectors) {
              for (const el of Array.from(document.querySelectorAll(selector))) {
                candidates.push(el);
              }
            }

            let best = null;
            let bestScore = 0;

            for (const el of candidates) {
              const rect = el.getBoundingClientRect();
              if (rect.width <= 0 || rect.height <= 0) continue;
              const text = textFor(el);
              const nearTop = rect.top <= window.innerHeight * 1.2;
              const hasHeroMedia = el.querySelector('img, picture, video, canvas') !== null;
              if (!nearTop) continue;
              if (!hasHeroMedia && text.length < 80 && rect.height < 180) continue;
              if (isLikelyChromeBar(el)) continue;

              const score =
                (hasHeroMedia ? 320 : 0) +
                text.length +
                (rect.height * 2) +
                (el.querySelectorAll('img, p, h1, h2, h3, section, article').length * 20) -
                rect.top;
              if (score > bestScore) {
                best = el;
                bestScore = score;
              }
            }

            if (best) return best;

            for (const el of Array.from(document.body.children)) {
              const rect = el.getBoundingClientRect();
              if (rect.width <= 0 || rect.height <= 0) continue;
              const text = textFor(el);
              const score =
                text.length +
                (rect.height * 2) +
                (el.querySelectorAll('img, p, h1, h2, h3, section, article').length * 20);
              if (score > bestScore && !isLikelyChromeBar(el)) {
                best = el;
                bestScore = score;
              }
            }
            return best;
          };

          const hidePrecedingChrome = () => {
            const main = findMainContent();
            if (!main) return;

            let node = main;
            while (node && node !== document.body) {
              let sibling = node.previousElementSibling;
              let hiddenCount = 0;
              while (sibling && hiddenCount < 6) {
                const previous = sibling.previousElementSibling;
                if (isLikelyChromeBar(sibling)) {
                  hideElement(sibling);
                  hiddenCount += 1;
                }
                sibling = previous;
              }
              node = node.parentElement;
            }
          };

          const hideLeadingChildren = () => {
            const main = findMainContent();
            if (!main) return;

            const candidates = [];
            if (main.children.length > 0) {
              candidates.push(...Array.from(main.children).slice(0, 6));
            }
            if (main.parentElement && main.parentElement.children.length > 0) {
              candidates.push(...Array.from(main.parentElement.children).slice(0, 6));
            }

            let contentFound = false;
            for (const child of candidates) {
              if (!child || child === main) continue;
              const rect = child.getBoundingClientRect();
              const text = textFor(child);
              const hasStrongContent =
                rect.height > window.innerHeight * 0.35 ||
                text.length > 220 ||
                child.querySelector('h1, h2, article, main, [class*="hero"], [class*="banner"]') !== null;

              if (hasStrongContent && !isLikelyChromeBar(child)) {
                contentFound = true;
                break;
              }

              if (!contentFound && isLikelyChromeBar(child)) {
                hideElement(child);
              }
            }
          };

          const collapseTopSpacers = () => {
            const main = findMainContent();
            if (!main) return;

            let sibling = main.previousElementSibling;
            while (sibling) {
              const previous = sibling.previousElementSibling;
              const rect = sibling.getBoundingClientRect();
              const text = textFor(sibling);
              const hasMedia = sibling.querySelector('img, picture, video, svg, iframe, canvas, form, input, button') !== null;
              if (rect.height < 120 && text.length === 0 && !hasMedia) {
                hideElement(sibling);
              }
              sibling = previous;
            }
          };

          const hideFloatingWidgets = () => {
            const floatingKeywords = ['chat', 'whatsapp', 'call-now', 'support', 'help', 'messenger', 'tawk', 'crisp'];
            for (const el of Array.from(document.querySelectorAll('body *'))) {
              const computed = window.getComputedStyle(el);
              const name = `${el.id || ''} ${typeof el.className === 'string' ? el.className : ''}`.toLowerCase();
              const rect = el.getBoundingClientRect();
              const isFloating = computed.position === 'fixed' || computed.position === 'sticky';
              const looksLikeWidget = floatingKeywords.some((keyword) => name.includes(keyword));
              const isSmallFloatingWidget = isFloating &&
                rect.width > 0 &&
                rect.width < 220 &&
                rect.height > 0 &&
                rect.height < 220 &&
                rect.bottom > (window.innerHeight - 40);

              if (looksLikeWidget || isSmallFloatingWidget) {
                el.style.setProperty('display', 'none', 'important');
                el.style.setProperty('visibility', 'hidden', 'important');
                el.style.setProperty('pointer-events', 'none', 'important');
              }
            }
          };

          const hideChrome = () => {
            document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');
            document.body.style.setProperty('overflow-x', 'hidden', 'important');
            document.querySelectorAll('[data-native-app-chrome="1"]').forEach((el) => {
              hideElement(el);
            });
            document.querySelectorAll(chromeSelectors.join(',')).forEach((el) => {
              if (isLikelyChromeBar(el)) {
                hideElement(el);
              }
            });
            document.querySelectorAll('body *').forEach((el) => {
              if (isLikelyChromeBar(el)) {
                hideElement(el);
              }
            });
            document.querySelectorAll('body > div, body > section, body > header').forEach((el) => {
              if (isLikelyChromeBar(el)) {
                hideElement(el);
              }
            });
            hidePrecedingChrome();
            hideLeadingChildren();
            collapseTopSpacers();
            hideFloatingWidgets();
          };

          hideChrome();

          if (!window.__nativeAppShellObserver) {
            const observer = new MutationObserver(() =>
              window.requestAnimationFrame(hideChrome)
            );
            observer.observe(document.documentElement, {
              childList: true,
              subtree: true,
            });
            window.__nativeAppShellObserver = observer;
          }

          return true;
        })();
      ''';

      await controller.runJavaScript(script);
    } catch (e) {
      debugPrint('Native chrome hiding failed: $e');
    }
  }

  Future<void> _preparePageForDisplay() async {
    await _applyNativeChromeHiding();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await _applyNativeChromeHiding();

    final controller = _controller;
    if (controller == null) return;

    try {
      await controller.runJavaScript(
        'window.scrollTo({ top: 0, left: 0, behavior: "auto" });',
      );
    } catch (e) {
      debugPrint('Scroll reset failed: $e');
    }
  }

  Future<void> _refreshNativePresentation() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || !_usesWebView) return;
    await _syncBrowserState();
    await _syncPageMetadata();
    await _syncNavigationMenu();
    await _applyNativeChromeHiding();
  }

  Future<void> _syncBrowserState() async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
    if (!mounted) return;

    setState(() {
      canGoBack = back;
      canGoForward = forward;
    });
  }

  void _updateCurrentUrl(String url) {
    currentUrl = url;
    ref.read(webProvider.notifier).setUrl(url);
    _updatePageSubtitle(url);
  }

  void _updatePageSubtitle(String? url) {
    final uri = Uri.tryParse(url ?? '');
    final host = (uri?.host ?? '').replaceFirst(RegExp(r'^www\.'), '');
    if (!mounted) return;
    setState(() {
      pageSubtitle = host.isEmpty ? _defaultSubtitle : host;
      siteDisplayName = host.isEmpty ? _defaultSiteName : _formatSiteName(host);
    });
  }

  String _sanitizeTitle(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return _defaultTitle;
    final title = trimmed.split('|').first.split('-').first.trim();
    if (title.isEmpty) return _defaultTitle;
    return title.length > 24 ? '${title.substring(0, 21)}...' : title;
  }

  String _friendlyErrorMessage(String rawDescription) {
    final message = rawDescription.trim();
    final lower = message.toLowerCase();
    if (lower.contains('err_connection_reset')) {
      return 'Connection was interrupted while loading the website. Please retry.';
    }
    if (lower.contains('err_name_not_resolved')) {
      return 'The website address could not be reached. Please check the URL or internet connection.';
    }
    if (lower.contains('err_internet_disconnected')) {
      return 'No internet connection detected. Please reconnect and try again.';
    }
    if (lower.contains('timeout')) {
      return 'The website is taking too long to respond. Please retry in a moment.';
    }
    if (lower.contains('err_failed') || message.isEmpty) {
      return 'This page could not be opened right now. Tap retry to load it again.';
    }
    return message;
  }

  String _formatSiteName(String host) {
    final parts = host.split('.').where((part) => part.isNotEmpty).toList();
    if (parts.length > 1) {
      parts.removeLast();
    }

    final label = (parts.isEmpty ? host : parts.join(' '))
        .replaceAll(RegExp(r'[-_]'), ' ');
    return label
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Future<void> _refreshCurrentPage() async {
    final url = currentUrl ?? initialUrl;
    if (url == null) return;

    if (_usesWebView) {
      await _controller?.reload();
      return;
    }

    await _fetchPage(url);
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(currentUrl ?? initialUrl ?? '');
    if (uri == null) return;
    await _launchExternalUrl(uri);
  }

  Future<void> _launchExternalUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _setLoading(bool isLoading) {
    ref.read(webProvider.notifier).setLoading(isLoading);
  }

  void _clearError() {
    if (!mounted) return;
    setState(() => errorMessage = null);
  }

  Future<void> _showWebsiteSwitcher() async {
    final inputController =
        TextEditingController(text: currentUrl ?? initialUrl ?? '');
    String? validationMessage;

    final nextUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Open Website'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: inputController,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Website URL',
                      hintText: 'example.com',
                      errorText: validationMessage,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Paste a website URL and reopen the app with that site.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final raw = inputController.text.trim();
                    if (raw.isEmpty) {
                      setModalState(
                          () => validationMessage = 'Website URL is required.');
                      return;
                    }

                    try {
                      final normalized = _normalizeWebsiteUrl(raw);
                      final uri = Uri.tryParse(normalized);
                      if (uri == null || uri.host.isEmpty) {
                        throw const FormatException('Invalid host');
                      }
                      Navigator.of(dialogContext).pop(normalized);
                    } catch (_) {
                      setModalState(() =>
                          validationMessage = 'Enter a valid website URL.');
                    }
                  },
                  child: const Text('Open'),
                ),
              ],
            );
          },
        );
      },
    );

    inputController.dispose();
    if (nextUrl == null || !mounted) return;
    await _applyWebsite(nextUrl, persist: true);
  }

  List<Map<String, String>> _extractNavigationItemsFromHtml(
      String html, String baseUrl) {
    final document = html_parser.parse(html);
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null) return const [];

    final candidateContainers = <dom.Element>[
      ...document.querySelectorAll(
        'nav, [role="navigation"], header, footer, .menu, .navbar, .nav, .tab-bar, .bottom-nav, .bottom-navigation, .mobile-nav, .mobile-menu, .elementor-nav-menu, .et-menu, [class*="nav"], [class*="menu"], [class*="tab"], [class*="bottom"], [id*="nav"], [id*="menu"], [id*="tab"], [id*="bottom"]',
      ),
    ];

    List<Map<String, String>> extractFromContainer(dom.Element container) {
      final items = <Map<String, String>>[];
      final seen = <String>{};

      for (final anchor in container.querySelectorAll('a[href]')) {
        final label = anchor.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        final href = anchor.attributes['href'];
        if (label.isEmpty ||
            label.length < 2 ||
            label.length > 24 ||
            href == null ||
            href.isEmpty) {
          continue;
        }
        if (RegExp(
          r'read more|learn more|view more|click here|book now|download|watch now|apply now|buy now|see all',
          caseSensitive: false,
        ).hasMatch(label)) {
          continue;
        }
        if (href.startsWith('#') ||
            href.startsWith('mailto:') ||
            href.startsWith('tel:')) {
          continue;
        }

        final resolvedUrl = baseUri.resolve(href).toString();
        final uri = Uri.tryParse(resolvedUrl);
        if (uri == null || !_belongsToSameSite(baseUri, uri)) {
          continue;
        }
        if (_looksLikeExternalSocialLink(resolvedUrl)) {
          continue;
        }

        final key = '${label.toLowerCase()}|${_normalizeUrlKey(resolvedUrl)}';
        if (seen.contains(key)) {
          continue;
        }

        seen.add(key);
        items.add({'label': label, 'url': resolvedUrl});
      }

      return items;
    }

    List<Map<String, String>> bestItems = const [];
    var bestScore = -1;

    for (final container in candidateContainers) {
      final items = extractFromContainer(container);
      if (items.length < 2 || items.length > 8) {
        continue;
      }

      final identity =
          '${container.localName ?? ''} ${container.id} ${container.className}'
              .toLowerCase();
      var score = items.length * 10;
      if (RegExp(r'nav|menu|tab|bottom|footer|header').hasMatch(identity)) {
        score += 20;
      }
      score += items.where((item) => item['label']!.length <= 14).length * 2;

      if (score > bestScore) {
        bestScore = score;
        bestItems = items;
      }
    }

    return bestItems.take(12).toList();
  }

  List<Map<String, String>> _decodeNavigationItemsFromJsResult(Object result) {
    final normalized = _normalizeJsResult(result);
    try {
      final decoded = json.decode(normalized);
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map>()
          .map((item) => {
                'label': (item['label'] ?? '').toString(),
                'url': (item['url'] ?? '').toString(),
              })
          .where((item) => item['label']!.isNotEmpty && item['url']!.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _normalizeJsResult(Object result) {
    final raw = result.toString();
    try {
      final decoded = json.decode(raw);
      if (decoded is String) return decoded;
      return json.encode(decoded);
    } catch (_) {
      return raw;
    }
  }

  List<WebItem> _buildMenuItemsFromRaw(List<Map<String, String>> rawItems,
      {String? activeUrl}) {
    final siteUrl = activeUrl ?? currentUrl ?? initialUrl;
    final siteUri = Uri.tryParse(siteUrl ?? '');
    if (siteUri == null) {
      return const [];
    }

    final rootUri = Uri(
      scheme: siteUri.scheme,
      host: siteUri.host,
      port: siteUri.hasPort ? siteUri.port : null,
    );
    final rootUrl = rootUri.toString();

    final items = <WebItem>[
      WebItem(label: 'Home', url: rootUrl, icon: Icons.home_rounded),
    ];
    final seenLabels = <String>{'home'};
    final seenUrls = <String>{_normalizeUrlKey(rootUrl)};

    for (final item in rawItems) {
      final label = item['label']?.trim() ?? '';
      final url = item['url']?.trim() ?? '';
      if (label.isEmpty || url.isEmpty) {
        continue;
      }

      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        continue;
      }
      if (!_belongsToSameSite(siteUri, uri)) {
        continue;
      }

      final normalizedUrl = _normalizeUrlKey(uri.toString());
      final normalizedLabel = label.toLowerCase();
      if (seenUrls.contains(normalizedUrl) ||
          seenLabels.contains(normalizedLabel)) {
        continue;
      }

      seenUrls.add(normalizedUrl);
      seenLabels.add(normalizedLabel);
      items.add(WebItem(
          label: label, url: uri.toString(), icon: _iconForLabel(label)));
      if (items.length >= 12) break;
    }

    return items;
  }

  void _applyMenuItems(List<Map<String, String>> rawItems,
      {String? activeUrl}) {
    final items = _buildMenuItemsFromRaw(rawItems, activeUrl: activeUrl);
    final existing = ref.read(webProvider).menuItems;
    final shouldPreserveExisting = items.length <= 1 && existing.length > 1;
    final nextItems = shouldPreserveExisting ? existing : items;

    ref.read(webProvider.notifier).updateMenu(nextItems);
    final siteUrl = activeUrl ?? currentUrl ?? initialUrl;
    if (siteUrl != null) {
      unawaited(_cacheMenuItems(siteUrl, nextItems));
    }
  }

  bool _belongsToSameSite(Uri siteUri, Uri candidate) {
    if (siteUri.host == candidate.host) return true;
    return candidate.host.endsWith('.${siteUri.host}');
  }

  bool _looksLikeExternalSocialLink(String url) {
    final lower = url.toLowerCase();
    return lower.contains('facebook') ||
        lower.contains('instagram') ||
        lower.contains('twitter') ||
        lower.contains('linkedin') ||
        lower.contains('youtube') ||
        lower.contains('whatsapp');
  }

  String _normalizeUrlKey(String url) {
    return url.toLowerCase().replaceAll(RegExp(r'/$'), '');
  }

  String? _urlKeyOrNull(String? url) {
    final value = url?.trim();
    if (value == null || value.isEmpty) return null;
    return _normalizeUrlKey(value);
  }

  IconData _iconForLabel(String label) {
    final text = label.toLowerCase();
    if (text.contains('home')) return Icons.home_rounded;
    if (text.contains('about')) return Icons.info_rounded;
    if (text.contains('movie') ||
        text.contains('cinema') ||
        text.contains('show')) {
      return Icons.local_movies_rounded;
    }
    if (text.contains('event') || text.contains('ticket')) {
      return Icons.confirmation_number_rounded;
    }
    if (text.contains('profile') ||
        text.contains('account') ||
        text.contains('user')) {
      return Icons.person_rounded;
    }
    if (text.contains('service') ||
        text.contains('product') ||
        text.contains('shop')) {
      return Icons.grid_view_rounded;
    }
    if (text.contains('salesforce') || text.contains('cloud')) {
      return Icons.cloud_rounded;
    }
    if (text.contains('contact') || text.contains('support')) {
      return Icons.support_agent_rounded;
    }
    if (text.contains('blog') || text.contains('news')) {
      return Icons.article_rounded;
    }
    if (text.contains('portfolio') || text.contains('work')) {
      return Icons.workspaces_rounded;
    }
    return Icons.language_rounded;
  }

  bool _isSelectedMenuItem(WebItem item) {
    final active = currentUrl ?? initialUrl;
    if (active == null) return false;

    final itemUri = Uri.tryParse(item.url);
    final activeUri = Uri.tryParse(active);
    if (itemUri == null || activeUri == null) return false;

    if (_normalizeUrlKey(item.url) == _normalizeUrlKey(active)) return true;
    if (itemUri.host != activeUri.host) return false;

    final itemPath = itemUri.path.isEmpty ? '/' : itemUri.path;
    final activePath = activeUri.path.isEmpty ? '/' : activeUri.path;
    if (itemPath == '/') return activePath == '/';
    return activePath.startsWith(itemPath);
  }

  List<WebItem> _primaryNavigationItems(WebState state) {
    final items = state.menuItems;
    if (items.isEmpty) {
      return const [];
    }
    return items.take(5).toList();
  }

  Future<void> _showToolsSheet() async {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Widget _buildAppBarTitle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          siteDisplayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _appBarSupportingText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildAppDrawer(WebState state) {
    final primaryItems = _primaryNavigationItems(state);
    final primaryUrls =
        primaryItems.map((item) => _normalizeUrlKey(item.url)).toSet();
    final remainingMenuItems = state.menuItems
        .where((item) => !primaryUrls.contains(_normalizeUrlKey(item.url)))
        .toList();
    final hasCurrentUrl = (currentUrl ?? initialUrl) != null;
    final drawerWidth = MediaQuery.of(context).size.width > 420
        ? 360.0
        : MediaQuery.of(context).size.width * 0.88;

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x120F172A),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.asset('assets/images/logo.png',
                            fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            siteDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _appBarSupportingText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                children: [
                  if (remainingMenuItems.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(6, 4, 6, 8),
                      child: Text(
                        'More pages',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    ...remainingMenuItems.map(
                      (item) => ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        tileColor: _isSelectedMenuItem(item)
                            ? const Color(0xFFF1F5F9)
                            : Colors.transparent,
                        leading: Icon(
                          item.icon ?? Icons.language_rounded,
                          color: _isSelectedMenuItem(item)
                              ? AppColors.primary
                              : const Color(0xFF64748B),
                        ),
                        title: Text(
                          item.label,
                          style: TextStyle(
                            fontWeight: _isSelectedMenuItem(item)
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_fetchPage(item.url));
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 4, 6, 8),
                    child: Text(
                      'App tools',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  _DrawerActionTile(
                    icon: Icons.refresh_rounded,
                    label: 'Reload page',
                    enabled: hasCurrentUrl,
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_refreshCurrentPage());
                    },
                  ),
                  _DrawerActionTile(
                    icon: Icons.open_in_new_rounded,
                    label: 'Open in browser',
                    enabled: hasCurrentUrl,
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_openInBrowser());
                    },
                  ),
                  _DrawerActionTile(
                    icon: Icons.link_rounded,
                    label: 'Change website',
                    enabled: true,
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_showWebsiteSwitcher());
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowserSurface(WebState state) {
    if (_usesWebView) {
      final controller = _controller;
      if (controller == null) {
        return const Center(child: Text('Browser engine is not ready.'));
      }
      final showLoadingSkeleton =
          errorMessage == null && (state.isLoading || !isPagePresentationReady);

      return Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: controller)),
          if (showLoadingSkeleton)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xFFF8FAFC),
                child: IgnorePointer(
                  child: LoadingWidget(),
                ),
              ),
            ),
          if (state.isLoading && loadingProgress < 100)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: loadingProgress <= 0 ? null : loadingProgress / 100,
                minHeight: 3,
                color: AppColors.primary,
                backgroundColor: Colors.transparent,
              ),
            ),
          if (errorMessage != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.white,
                child: ErrorWidgetCustom(
                  message: errorMessage!,
                  onRetry: () => unawaited(_refreshCurrentPage()),
                ),
              ),
            ),
        ],
      );
    }

    if (state.isLoading && htmlContent == null) {
      return const Center(child: LoadingWidget());
    }

    if (errorMessage != null && htmlContent == null) {
      return ErrorWidgetCustom(
        message: errorMessage!,
        onRetry: () => unawaited(_refreshCurrentPage()),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCurrentPage,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: htmlContent == null
              ? const SizedBox.shrink()
              : HtmlWidget(
                  htmlContent!,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    height: 1.7,
                    color: Color(0xFF334155),
                  ),
                  onTapUrl: (url) {
                    final uri = Uri.tryParse(url);
                    final isWebUrl = uri != null &&
                        (uri.scheme == 'http' || uri.scheme == 'https');

                    if (isWebUrl) {
                      unawaited(_fetchPage(url));
                    } else if (uri != null) {
                      unawaited(_launchExternalUrl(uri));
                    }
                    return true;
                  },
                  customStylesBuilder: (el) {
                    if (el.localName == 'h1') {
                      return {
                        'font-size': '32px',
                        'font-weight': '900',
                        'color': '#0F172A',
                        'line-height': '1.1',
                        'margin': '20px 0',
                      };
                    }
                    if (el.localName == 'h2') {
                      return {
                        'font-size': '24px',
                        'font-weight': '800',
                        'color': '#1E293B',
                        'margin': '32px 0 16px',
                      };
                    }
                    if (el.localName == 'a') {
                      return {
                        'color': '#4F46E5',
                        'text-decoration': 'none',
                        'font-weight': '800',
                      };
                    }
                    return null;
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation(WebState state) {
    final primaryItems = _primaryNavigationItems(state);
    if (primaryItems.length <= 1) {
      return const SizedBox.shrink();
    }
    final items = primaryItems
        .map(
          (item) => _BottomBarItem(
            icon: item.icon ?? Icons.language_rounded,
            label: item.label,
            selected: _isSelectedMenuItem(item),
            enabled: true,
            onTap: () => unawaited(_fetchPage(item.url)),
          ),
        )
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF162033)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260F172A),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: items
              .map(
                (item) => Expanded(
                  child: _BottomNavButton(item: item),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webProvider);
    final showBackButton = _canStepBack && !_isOnHomePage;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF8FAFC),
        endDrawer: _buildAppDrawer(state),
        appBar: AppBar(
          title: _buildAppBarTitle(),
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          leading: showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.primary, size: 24),
                  onPressed: _handleBack,
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF94A3B8), size: 22),
              onPressed: () => unawaited(_refreshCurrentPage()),
            ),
            IconButton(
              icon: const Icon(Icons.menu_rounded,
                  color: Color(0xFF94A3B8), size: 22),
              onPressed: () => unawaited(_showToolsSheet()),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _buildBrowserSurface(state),
        bottomNavigationBar: _buildBottomNavigation(state),
      ),
    );
  }
}

class _DrawerActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _DrawerActionTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        enabled ? const Color(0xFF0F172A) : const Color(0xFF94A3B8);
    return ListTile(
      enabled: enabled,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: Icon(icon, color: foreground),
      title: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: enabled
          ? const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8))
          : null,
      onTap: enabled ? onTap : null,
    );
  }
}

class _BottomBarItem {
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _BottomBarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
}

class _BottomNavButton extends StatelessWidget {
  final _BottomBarItem item;

  const _BottomNavButton({required this.item});

  @override
  Widget build(BuildContext context) {
    final foreground = item.enabled
        ? (item.selected ? Colors.white : const Color(0xFFD6DEEA))
        : const Color(0xFF64748B);
    final background = item.selected
        ? const Color(0xFF182338)
        : item.enabled
            ? Colors.transparent
            : const Color(0xFF0F172A);

    return InkWell(
      onTap: item.enabled ? item.onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.selected
                    ? const Color(0xFF243452)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: foreground, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: foreground,
                fontSize: 9.5,
                fontWeight: item.selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
