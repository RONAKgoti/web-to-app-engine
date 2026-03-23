import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:go_router/go_router.dart';
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
  static const _nativeActionScheme = 'native-action://';

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
            unawaited(_recoverNavigationShell(url));
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
    if (_isNativeActionUrl(url)) {
      await _triggerNativeAction(url);
      return;
    }
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

  bool _isNativeActionUrl(String url) => url.startsWith(_nativeActionScheme);

  bool _isWebUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  String? _nativeActionId(String url) {
    if (!_isNativeActionUrl(url)) return null;
    final uri = Uri.tryParse(url);
    final host = uri?.host.trim();
    if (host != null && host.isNotEmpty) return host;
    final fallback = url.substring(_nativeActionScheme.length).trim();
    return fallback.isEmpty ? null : fallback;
  }

  Future<void> _triggerNativeAction(String url) async {
    final controller = _controller;
    final actionId = _nativeActionId(url);
    if (controller == null || actionId == null || actionId.isEmpty) return;

    try {
      await controller.runJavaScript('''
        (() => {
          const actionId = ${json.encode(actionId)};
          const target = document.querySelector('[data-native-app-action-id="' + actionId + '"]');
          if (!target) return false;

          if (typeof target.click === 'function') {
            target.click();
          } else {
            target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          }

          target.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        })();
      ''');
    } catch (e) {
      debugPrint('Native action trigger failed: $e');
      return;
    }

    final active = currentUrl ?? initialUrl;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await _refreshNativePresentation();
    if (active != null) {
      unawaited(_recoverNavigationShell(active));
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
    final cacheableItems = items.where((item) => _isWebUrl(item.url)).toList();
    if (cacheableItems.length < 2) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final payload = cacheableItems
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

      final rawItems =
          _extractNavigationItemsFromHtml(response.data.toString(), url);
      final items = _buildMenuItemsFromRaw(rawItems, activeUrl: url);
      if (items.length < 2 || !mounted) {
        return;
      }

      _applyMenuItems(rawItems, activeUrl: url);
    } catch (e) {
      debugPrint('Prefetch menu failed: $e');
    }
  }

  Future<void> _recoverNavigationShell(String url) async {
    const recoveryDelays = [350, 900, 1600];
    for (final delay in recoveryDelays) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted || !_usesWebView) return;
      if (_urlKeyOrNull(currentUrl) != _urlKeyOrNull(url)) return;

      if (ref.read(webProvider).menuItems.length >= 4) {
        return;
      }

      await _syncNavigationMenu();
      if (ref.read(webProvider).menuItems.length < 3) {
        await _prefetchMenuItems(url);
      }
      await _applyNativeChromeHiding();
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

          const invalidLabelPattern = /read more|learn more|view more|click here|book now|download|watch now|apply now|buy now|see all|menu|back|next|previous|prev|close/i;
          const currentHost = window.location.host.replace(/^www\./i, '');

          const isSameSite = (url) => {
            const host = url.host.replace(/^www\./i, '');
            return host === currentHost ||
              host.endsWith(`.${currentHost}`) ||
              currentHost.endsWith(`.${host}`);
          };

          const createActionItem = (element, label) => {
            if (!element.dataset.nativeAppActionId) {
              element.dataset.nativeAppActionId =
                `native-${Math.random().toString(36).slice(2, 10)}`;
            }
            return {
              label,
              url: `native-action://${element.dataset.nativeAppActionId}`,
            };
          };

          const resolveHref = (element) =>
            element.getAttribute('href') ||
            element.href ||
            element.getAttribute('data-url') ||
            element.getAttribute('data-href') ||
            element.getAttribute('routerlink') ||
            element.getAttribute('routerLink') ||
            element.getAttribute('ng-reflect-router-link') ||
            '';

          const toItem = (element) => {
            const label = normalizeLabel(
              element.innerText ||
              element.textContent ||
              element.getAttribute('aria-label') ||
              ''
            );
            if (!label || label.length < 2 || label.length > 24) return null;
            if (invalidLabelPattern.test(label)) return null;

            const href = resolveHref(element);
            if (!href &&
                (element.matches('button, [role="button"], [role="tab"]') ||
                 element.getAttribute('tabindex') === '0')) {
              return createActionItem(element, label);
            }
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

            for (const element of Array.from(container.querySelectorAll(
              'a[href], button, [role="button"], [role="tab"], [tabindex="0"]'
            ))) {
              const item = toItem(element);
              if (!item) continue;

              const key = `${item.label.toLowerCase()}|${item.url.replace(/\/$/, '').toLowerCase()}`;
              if (seen.has(key)) continue;
              seen.add(key);
              items.push(item);
            }

            return items;
          };

          const scoreContainer = (container, items) => {
            if (items.length < 2 || items.length > 12) return -1;

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
            const sizePenalty = items.length > 8 ? (items.length - 8) * 24 : 0;

            return (items.length * 90) +
              (shortLabels * 20) +
              (nearTop ? 40 : 0) +
              (nearBottom ? 55 : 0) +
              (pinned ? 70 : 0) +
              (keywordMatch ? 80 : 0) -
              textPenalty -
              sizePenalty;
          };

          const selectors = [
            'nav',
            '[role="navigation"]',
            '[role="tablist"]',
            'header',
            'footer',
            '.menu',
            '.navbar',
            '.navigation',
            '.nav',
            '.tab-bar',
            '.tabbar',
            '.bottom-nav',
            '.bottom-navigation',
            '.bottomNavigation',
            '.mobile-nav',
            '.mobile-menu',
            '.elementor-nav-menu',
            '.et-menu',
            '[data-testid*="nav"]',
            '[data-testid*="tab"]',
            '[data-test*="nav"]',
            '[data-test*="tab"]',
            '[class*="nav"]',
            '[class*="navigation"]',
            '[class*="menu"]',
            '[class*="tab"]',
            '[class*="bottom"]',
            '[id*="nav"]',
            '[id*="navigation"]',
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

          for (const node of Array.from(document.querySelectorAll('body div, body section, body ul, body ol'))) {
            if (containers.length >= 220) break;
            if (seenNodes.has(node)) continue;

            const rect = node.getBoundingClientRect();
            if (rect.width <= window.innerWidth * 0.45 || rect.height <= 0) continue;
            if (rect.height > window.innerHeight * 0.48) continue;

            const computed = window.getComputedStyle(node);
            const nearTop = rect.top <= Math.max(260, window.innerHeight * 0.3);
            const nearBottom = rect.bottom >= window.innerHeight - Math.max(260, window.innerHeight * 0.3);
            const pinned = computed.position === 'fixed' || computed.position === 'sticky';
            const interactiveCount = node.querySelectorAll(
              'a[href], button, [role="button"], [role="tab"], [role="link"], [tabindex="0"], [routerlink], [routerLink], [data-url], [data-href], [ng-reflect-router-link]'
            ).length;
            const directClickableChildren = Array.from(node.children).filter((child) =>
              child.matches('a[href], button, [role="button"], [role="tab"], [role="link"], [routerlink], [routerLink], [data-url], [data-href], [ng-reflect-router-link]') ||
              child.querySelector('a[href], button, [role="button"], [role="tab"], [role="link"], [routerlink], [routerLink], [data-url], [data-href], [ng-reflect-router-link]')
            ).length;

            if (interactiveCount < 2 || interactiveCount > 12) continue;
            if (!nearTop && !nearBottom && !pinned && directClickableChildren < 3) continue;

            seenNodes.add(node);
            containers.push(node);
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

  Future<void> _preparePageForDisplay() async {
    await _applyNativeChromeHiding();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _applyNativeChromeHiding();
    await Future<void>.delayed(const Duration(milliseconds: 350));
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

  Future<void> _applyNativeChromeHiding() async {
    final controller = _controller;
    if (controller == null || !mounted) return;

    try {
      // UNIVERSAL SURGICAL CLEANING SCRIPT v10 (Multi-Engine)
      // Targeted selectors for common website headers, footers, mobile menus, and popups
      const js = r'''
        (() => {
          const hideSelectors = [
            'header', 'footer', '.header', '.footer', '#header', '#footer',
            '.nav', 'nav', '.navigation', '.navbar', '.top-bar', '.top-nav',
            '.mobile-menu', '.mobile-nav', '.et_mobile_menu', '.et_pb_menu',
            '.elementor-location-header', '.elementor-location-footer',
            '.wpadminbar', '#wpadminbar', '.sticky-header', '.main-header',
            '.site-header', '.site-footer', '.td-header-wrap', '.td-footer-wrap',
            '.mobile_header', '.mobile_footer', '.bottom-navigation',
            'div[class*="header"]', 'div[class*="footer"]', 'div[class*="nav"]',
            'section[class*="header"]', 'section[class*="footer"]',
            '.burger', '.hamburger', '.menu-toggle', '.nav-toggle', 
            '.mobile-nav-toggle', '.header-inner', '.footer-inner'
          ];

          hideSelectors.forEach(selector => {
            document.querySelectorAll(selector).forEach(el => {
              if (el) {
                el.style.display = 'none';
                el.style.height = '0';
                el.style.visibility = 'hidden';
                el.style.opacity = '0';
                el.style.pointerEvents = 'none';
              }
            });
          });

          // Disable sticky position for any remaining elements that might overlap
          document.querySelectorAll('*').forEach(el => {
            const style = window.getComputedStyle(el);
            if (style.position === 'fixed' || style.position === 'sticky') {
               // Only hide if it's near top/bottom (likely header/footer)
               const rect = el.getBoundingClientRect();
               if (rect.top < 100 || rect.bottom > (window.innerHeight - 100)) {
                   el.style.display = 'none';
               }
            }
          });

          // Also inject persistent CSS override
          if (!document.getElementById('native-app-chrome-hider-v2')) {
            const style = document.createElement('style');
            style.id = 'native-app-chrome-hider-v2';
            style.innerHTML = `
              header, footer, nav, .header, .footer, .nav, .navigation, 
              [class*="header"], [class*="footer"], [id*="header"], [id*="footer"], 
              .wpadminbar, #wpadminbar, .et_mobile_menu, .elementor-location-header,
              .mobile-menu, .mobile-nav, .burger, .hamburger {
                display: none !important;
                height: 0 !important;
                visibility: hidden !important;
                opacity: 0 !important;
                pointer-events: none !important;
              }
              body { 
                padding-top: 0 !important; padding-bottom: 0 !important; 
                margin-top: 0 !important; margin-bottom: 0 !important; 
              }
              html, body { overflow-x: hidden !important; }
            `;
            document.head.appendChild(style);
          }
        })();
      ''';
      await controller.runJavaScript(js);
    } catch (e) {
      debugPrint('Chrome hiding failed: $e');
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

    final candidateContainers = <dom.Element>[];
    final seenContainers = <dom.Element>{};

    void addCandidate(dom.Element element) {
      if (seenContainers.add(element)) {
        candidateContainers.add(element);
      }
    }

    for (final element in document.querySelectorAll(
      'nav, [role="navigation"], [role="tablist"], header, footer, .menu, .navbar, .navigation, .nav, .tab-bar, .tabbar, .bottom-nav, .bottom-navigation, .bottomNavigation, .mobile-nav, .mobile-menu, .elementor-nav-menu, .et-menu, [data-testid*="nav"], [data-testid*="tab"], [data-test*="nav"], [data-test*="tab"], [class*="nav"], [class*="navigation"], [class*="menu"], [class*="tab"], [class*="bottom"], [id*="nav"], [id*="navigation"], [id*="menu"], [id*="tab"], [id*="bottom"]',
    )) {
      addCandidate(element);
    }

    for (final element in document
        .querySelectorAll('body div, body section, body ul, body ol')) {
      if (candidateContainers.length >= 220) break;
      final interactiveCount = element
          .querySelectorAll(
            'a[href], button, [role="button"], [role="tab"], [role="link"], [routerlink], [routerLink], [data-url], [data-href], [ng-reflect-router-link]',
          )
          .length;
      final directClickableChildren = element.children
          .where((child) =>
              child.localName == 'a' ||
              child.localName == 'button' ||
              child.querySelector(
                    'a[href], button, [role="button"], [role="tab"], [role="link"], [routerlink], [routerLink], [data-url], [data-href], [ng-reflect-router-link]',
                  ) !=
                  null)
          .length;
      if (interactiveCount < 2 || interactiveCount > 12) {
        continue;
      }
      if (directClickableChildren < 3 &&
          !RegExp(
            r'nav|menu|tab|bottom|footer|header|category|section',
            caseSensitive: false,
          ).hasMatch(
            '${element.localName ?? ''} ${element.id} ${element.className}',
          )) {
        continue;
      }
      addCandidate(element);
    }

    List<Map<String, String>> extractFromContainer(dom.Element container) {
      final items = <Map<String, String>>[];
      final seen = <String>{};

      for (final node in container.querySelectorAll(
        'a[href], [routerlink], [routerLink], [data-url], [data-href], [ng-reflect-router-link]',
      )) {
        final label = node.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        final href = node.attributes['href'] ??
            node.attributes['data-url'] ??
            node.attributes['data-href'] ??
            node.attributes['routerlink'] ??
            node.attributes['routerLink'] ??
            node.attributes['ng-reflect-router-link'];
        if (label.isEmpty ||
            label.length < 2 ||
            label.length > 24 ||
            href == null ||
            href.isEmpty) {
          continue;
        }
        if (RegExp(
          r'read more|learn more|view more|click here|book now|download|watch now|apply now|buy now|see all|menu|back|next|previous|prev|close',
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
      if (items.length < 2 || items.length > 12) {
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
      if (identity.contains('navigation')) {
        score += 8;
      }
      if (items.length > 8) {
        score -= (items.length - 8) * 3;
      }

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

      final isActionItem = _isNativeActionUrl(url);
      Uri? uri;
      if (!isActionItem) {
        uri = Uri.tryParse(url);
        if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
          continue;
        }
        if (!_belongsToSameSite(siteUri, uri)) {
          continue;
        }
      }

      final normalizedUrl =
          isActionItem ? url.toLowerCase() : _normalizeUrlKey(uri.toString());
      final normalizedLabel = label.toLowerCase();
      if (seenUrls.contains(normalizedUrl) ||
          seenLabels.contains(normalizedLabel)) {
        continue;
      }

      seenUrls.add(normalizedUrl);
      seenLabels.add(normalizedLabel);
      items.add(WebItem(
          label: label,
          url: isActionItem ? url : uri.toString(),
          icon: _iconForLabel(label)));
      if (items.length >= 12) break;
    }

    return items;
  }

  void _applyMenuItems(List<Map<String, String>> rawItems,
      {String? activeUrl}) {
    final items = _buildMenuItemsFromRaw(rawItems, activeUrl: activeUrl);
    final existing = ref.read(webProvider).menuItems;

    // RULE: Stability First.
    // If we already have a healthy menu (4+ items) and we are not on the home page,
    // we do not let a sub-page overwrite our main navigation.
    final bool isHome = _isOnHomePage;
    final bool hasDecentExisting = existing.length >= 3;

    // Only update if:
    // 1. Current menu is tiny/empty
    // 2. We are on the home page (the definitive source of truth)
    // 3. The new menu is objectively better/larger than a non-home menu
    final bool shouldOverwrite = !hasDecentExisting || isHome || (items.length >= existing.length && existing.length < 5);

    final nextItems = shouldOverwrite ? items : existing;

    // Final sanity check: don't downgrade to nothingness
    final finalItems = (nextItems.length < 2 && existing.length >= 2) ? existing : nextItems;

    if (finalItems.isNotEmpty && finalItems != existing) {
      ref.read(webProvider.notifier).updateMenu(finalItems);
      final siteUrl = activeUrl ?? currentUrl ?? initialUrl;
      if (siteUrl != null) {
        unawaited(_cacheMenuItems(siteUrl, finalItems));
      }
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

  int _urlDepth(Uri uri) {
    return uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .length;
  }

  bool _isLikelyPrimaryNavigationItem(WebItem item, Uri siteUri) {
    final label = item.label.trim().toLowerCase();
    final isActionItem = _isNativeActionUrl(item.url);
    final uri = isActionItem ? null : Uri.tryParse(item.url);
    if (label.isEmpty) {
      return false;
    }
    if (!isActionItem && (uri == null || !_belongsToSameSite(siteUri, uri))) {
      return false;
    }

    if (label == 'home') return true;
    if (RegExp(
      r'read more|learn more|view more|see all|book now|watch now|apply now|download|share|next|previous|prev|login|sign in|sign up|logout|menu',
      caseSensitive: false,
    ).hasMatch(label)) {
      return false;
    }

    if (label.length > 22) return false;
    if (RegExp(r'^\d').hasMatch(label)) return false;

    if (isActionItem) {
      return label.split(RegExp(r'\s+')).length <= 3 &&
          !label.contains(':') &&
          !label.contains('/');
    }

    final resolvedUri = uri!;
    final depth = _urlDepth(resolvedUri);
    final hasGenericSectionKeyword = RegExp(
      r'home|about|service|solution|product|feature|category|movie|show|event|ticket|profile|account|user|contact|support|pricing|plan|blog|news|portfolio|work|salesforce|cloud',
      caseSensitive: false,
    ).hasMatch(label);

    if (resolvedUri.query.isNotEmpty && !hasGenericSectionKeyword) {
      return false;
    }

    if (depth <= 1) return true;
    if (depth == 2 && hasGenericSectionKeyword) return true;
    if (depth >= 3 && !hasGenericSectionKeyword) return false;

    final segments = resolvedUri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    return segments.every(
      (segment) =>
          segment.length <= 24 &&
          !RegExp(r'^\d+$').hasMatch(segment) &&
          !segment.contains('_') &&
          !segment.contains('%'),
    );
  }

  int _menuPriorityScore(WebItem item, Uri siteUri) {
    final label = item.label.trim().toLowerCase();
    final isActionItem = _isNativeActionUrl(item.url);
    final uri = isActionItem ? null : Uri.tryParse(item.url);
    final depth = isActionItem ? 1 : (uri == null ? 10 : _urlDepth(uri));
    var score = 100;

    if (label.contains('home')) score += 600;
    if (label.contains('about')) score += 420;
    if (label.contains('service') ||
        label.contains('solution') ||
        label.contains('product') ||
        label.contains('feature') ||
        label.contains('category')) {
      score += 390;
    }
    if (label.contains('movie') ||
        label.contains('show') ||
        label.contains('event') ||
        label.contains('ticket')) {
      score += 370;
    }
    if (label.contains('profile') ||
        label.contains('account') ||
        label.contains('user')) {
      score += 350;
    }
    if (label.contains('salesforce') || label.contains('cloud')) {
      score += 330;
    }
    if (label.contains('contact') || label.contains('support')) {
      score += 320;
    }
    if (label.contains('pricing') || label.contains('plan')) {
      score += 300;
    }
    if (label.contains('blog') || label.contains('news')) {
      score += 250;
    }

    if (isActionItem) {
      score += 80;
    } else if (uri != null && _belongsToSameSite(siteUri, uri)) {
      if (depth == 0) {
        score += 140;
      } else if (depth == 1) {
        score += 110;
      } else if (depth == 2) {
        score += 50;
      }

      if (uri.query.isEmpty) score += 24;
      if (uri.fragment.isEmpty) score += 12;
    }

    if (item.label.length <= 14) score += 28;
    if (item.label.length <= 10) score += 14;

    return score - (depth * 18);
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

    // STABILITY FIX: Use initialUrl (Home) as the anchor for scoring.
    // Using currentUrl causes the order and selection of tabs to jump around as user navigates.
    final siteUrl = initialUrl ?? state.currentUrl;
    final siteUri = Uri.tryParse(siteUrl ?? '');
    if (siteUri == null) {
      return items.take(5).toList();
    }

    final filtered = items
        .where((item) => _isLikelyPrimaryNavigationItem(item, siteUri))
        .toList();
    final candidates = filtered.length >= 2 ? filtered : items.toList();

    candidates.sort((a, b) {
      final scoreCompare = _menuPriorityScore(b, siteUri)
          .compareTo(_menuPriorityScore(a, siteUri));
      if (scoreCompare != 0) return scoreCompare;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    final ordered = <WebItem>[];
    final seenUrls = <String>{};
    for (final item in candidates) {
      final key = _normalizeUrlKey(item.url);
      if (!seenUrls.add(key)) continue;
      ordered.add(item);
      if (ordered.length == 5) break;
    }

    return ordered;
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
    final hasCurrentUrl = (currentUrl ?? initialUrl) != null;
    final drawerWidth = MediaQuery.of(context).size.width > 420
        ? 340.0
        : MediaQuery.of(context).size.width * 0.85;

    final websiteMenuItems = state.menuItems;
    final displayHost = pageSubtitle.replaceFirst('https://', '').split('/').first;

    // Identify which pillars are ALREADY in the bottom bar so we don't duplicate them in drawer
    final bottomBarUrls = state.stableMenu.map((e) => _normalizeUrlKey(e.url)).toSet();
    final bottomBarLabels = state.stableMenu.map((e) => e.label.toLowerCase()).toSet();
    
    // Filter website menu to NOT show what's already in the bottom bar
    final filteredWebsiteMenu = websiteMenuItems.where((item) {
       final key = _normalizeUrlKey(item.url);
       final isHome = key == _normalizeUrlKey(initialUrl ?? '');
       return !isHome && !bottomBarUrls.contains(key) && !bottomBarLabels.contains(item.label.toLowerCase());
    }).toList();

    const appPillarLabels = {'ai tools', 'hub', 'profile', 'ai assistant', 'product hub', 'my profile'};
    final bool showAI = !bottomBarLabels.any((l) => appPillarLabels.contains(l));
    final bool showHub = !bottomBarLabels.any((l) => appPillarLabels.contains(l));
    final bool showProfile = !bottomBarLabels.any((l) => appPillarLabels.contains(l));

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ── Premium Brand Header ────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: initialUrl != null 
                          ? Image.network(
                              'https://www.google.com/s2/favicons?sz=128&domain=${Uri.tryParse(initialUrl!)?.host ?? displayHost}',
                              errorBuilder: (_, __, ___) => const Icon(Icons.language_rounded, color: Colors.white70),
                            )
                          : const Icon(Icons.language_rounded, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            siteDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            displayHost,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white54,
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
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                children: [
                   // ── NAVIGATION: All Website Pages ───────────
                  if (filteredWebsiteMenu.isNotEmpty) ...[
                    const _DrawerSectionHeader(title: 'Website Directory'),
                    ...filteredWebsiteMenu.map((item) => _DrawerPageTile(
                      icon: item.icon ?? Icons.auto_awesome_mosaic_outlined,
                      label: item.label,
                      isActive: _isActiveUrl(item.url),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(context);
                        unawaited(_fetchPage(item.url));
                      },
                    )),
                    const SizedBox(height: 14),
                  ],

                  // ── APP FEATURES: DYNAMIC SMART OPTIONS ─────
                  const _DrawerSectionHeader(title: 'Smart Features'),
                  _DrawerPageTile(
                    icon: Icons.home_outlined,
                    label: 'Go to Homepage',
                    isActive: _isOnHomePage,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                      unawaited(_applyWebsite(initialUrl ?? '', persist: false));
                    },
                  ),
                  if (showAI)
                    _DrawerPageTile(
                      icon: Icons.assistant_outlined,
                      label: 'AI Assistant',
                      isActive: false,
                      onTap: () {
                        Navigator.pop(context);
                        context.go('/ai');
                      },
                    ),
                  if (showHub)
                    _DrawerPageTile(
                      icon: Icons.grid_view_outlined,
                      label: 'Product Hub',
                      isActive: false,
                      onTap: () {
                        Navigator.pop(context);
                        context.go('/hub');
                      },
                    ),
                   if (showProfile)
                    _DrawerPageTile(
                      icon: Icons.person_outline_rounded,
                      label: 'My Profile',
                      isActive: false,
                      onTap: () {
                        Navigator.pop(context);
                        context.go('/profile');
                      },
                    ),

                  const SizedBox(height: 14),

                  // ── SYSTEM: APP UTILITIES ──────────────────
                  const _DrawerSectionHeader(title: 'Configuration'),
                  _DrawerActionTile(
                    icon: Icons.refresh_rounded,
                    label: 'Sync Content',
                    enabled: hasCurrentUrl,
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_refreshCurrentPage());
                    },
                  ),
                  _DrawerActionTile(
                    icon: Icons.open_in_new_rounded,
                    label: 'Native Browser',
                    enabled: hasCurrentUrl,
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_openInBrowser());
                    },
                  ),
                  _DrawerActionTile(
                    icon: Icons.code_rounded,
                    label: 'Clean Cache',
                    enabled: true,
                    onTap: () {
                       _syncNavigationMenu();
                       Navigator.pop(context);
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

  bool _isActiveUrl(String url) {
    final active = currentUrl ?? initialUrl;
    if (active == null) return false;
    return _normalizeUrlKey(url) == _normalizeUrlKey(active);
  }

  Widget _buildBrowserSurface(WebState state) {
    if (_usesWebView) {
      final controller = _controller;
      if (controller == null) {
        return const Center(child: Text('Browser engine is not ready.'));
      }
      // PERFORMANCE FIX: Show web content as soon as it's 75% loaded 
      // This prevents the "permanent white screen" if onPageFinished is delayed
      final showLoadingSkeleton =
          errorMessage == null && (state.isLoading || !isPagePresentationReady) && loadingProgress < 75;

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webProvider);
    final showBackButton = _canStepBack && !_isOnHomePage;

    // 1. Listen for navigation requests from the dynamic bottom bar (Stability Fix)
    ref.listen(webProvider.select((s) => s.targetUrl), (previous, next) {
      if (next != null && next.isNotEmpty) {
        if (next == 'HOME') {
           unawaited(_applyWebsite(initialUrl ?? '', persist: false));
        } else {
           unawaited(_fetchPage(next));
        }
      }
    });

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
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              border: Border(
                bottom: BorderSide(
                  color: Colors.black.withValues(alpha: 0.05),
                  width: 0.8,
                ),
              ),
            ),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: AppBar(
                  title: _buildAppBarTitle(),
                  elevation: 0,
                  centerTitle: true,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  leading: showBackButton
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: AppColors.primary, size: 24),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _handleBack();
                          },
                        )
                      : null,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: Color(0xFF94A3B8), size: 22),
                      onPressed: () {
                         HapticFeedback.lightImpact();
                         unawaited(_refreshCurrentPage());
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.menu_rounded,
                          color: Color(0xFF94A3B8), size: 22),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        unawaited(_showToolsSheet());
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: _buildBrowserSurface(state),
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
    final foreground = enabled ? const Color(0xFF0F172A) : const Color(0xFF94A3B8);
    return ListTile(
      enabled: enabled,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: foreground, size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      trailing: enabled
          ? const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 18)
          : null,
      onTap: enabled ? onTap : null,
    );
  }
}

// ── Drawer Section Header ─────────────────────────────────────
class _DrawerSectionHeader extends StatelessWidget {
  final String title;
  const _DrawerSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF94A3B8),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Drawer Page Navigation Tile ───────────────────────────────
class _DrawerPageTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DrawerPageTile({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: isActive ? const Color(0xFFEEF2FF) : Colors.transparent,
        leading: Icon(
          icon,
          color: isActive ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? const Color(0xFF1E293B) : const Color(0xFF334155),
            fontSize: 14.5,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: isActive ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1),
          size: 18,
        ),
        onTap: onTap,
      ),
    );
  }
}

