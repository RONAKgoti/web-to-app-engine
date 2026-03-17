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
  static const _defaultTitle = 'WEBSITE APP';
  static const _defaultSubtitle = 'Adaptive Native Shell';
  static const _prefsWebsiteUrlKey = 'website_url';

  String? htmlContent;
  String? currentUrl;
  String? initialUrl;
  String pageTitle = _defaultTitle;
  String pageSubtitle = _defaultSubtitle;
  String? errorMessage;
  int loadingProgress = 0;
  bool canGoBack = false;
  bool canGoForward = false;
  bool isPagePresentationReady = false;
  late Dio _dio;
  WebViewController? _controller;
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

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36',
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
              errorMessage = rawDescription.isNotEmpty && !lower.contains('err_failed')
                  ? rawDescription
                  : 'This page could not be opened right now. Tap retry to load it again.';
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
        if (addToHistory &&
            previousUrl != null &&
            normNew != normCurrent) {
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
      String errTitle = "Connection Stuck";
      String errMsg = "The website is taking too long to respond. Tap refresh to try again.";
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        errTitle = "No Internet";
        errMsg = "Please check your network connection and try again.";
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
    <div style='padding:60px 20px; text-align:center; font-family: sans-serif;'>
      <h2 style='color:#1E293B; font-weight:900;'>$title</h2>
      <p style='color:#64748B; line-height:1.6;'>$msg</p>
      <div style='margin-top:20px; padding:12px; background:#4F46E5; color:white; border-radius:12px; display:inline-block; font-weight:bold;'>READY TO SYNC</div>
    </div>
    """;
  }

  void _handleBack() {
    unawaited(_handleBackPressed());
  }

  Future<void> _handleBackPressed() async {
    if (ref.read(webProvider).isLoading) return;

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
      if (title.isEmpty) title = "DASHBOARD";
      final nextTitle = title.length > 24 ? "${title.substring(0, 21)}..." : title;
      setState(() => pageTitle = nextTitle);
    } catch (_) {
      setState(() => pageTitle = "DASHBOARD");
    }
  }

  String _expertCleanHtml(String html, String baseUrl) {
    var document = html_parser.parse(html);
    final baseUri = Uri.tryParse(baseUrl);
    
    // 1. Surgical Noise Removal
    document.querySelectorAll('script, style, link, meta, iframe, noscript, .wpadminbar, .et_pb_menu, #wpadminbar, .mobile_menu, .et_mobile_menu, header, footer, .footer, .tp-bullets, .mobile_nav').forEach((e) => e.remove());

    // 2. Clear Global Junk
    var siteUI = ['nav', '.top-bar', '.footer-bottom', '#main-header', '#main-footer', '.elementor-location-header', '.elementor-location-footer', '.mobile-header'];
    for (var sel in siteUI) {
      document.querySelectorAll(sel).forEach((e) => e.remove());
    }

    // 3. Ultra-Greedy Shell Selection
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
      String txt = e.text.trim();
      String cls = e.className.toLowerCase();
      // Expanded culling
      if (txt == '%' || txt == 'K+' || txt == '+' || txt == '>' || txt == '»' || txt == '•' || txt == '✓' || txt == '::' || txt == '|') e.remove();
      if ((cls.contains('pattern') || cls.contains('shape') || cls.contains('dots') || cls.contains('divider')) && txt.length < 50) e.remove();
      if (e.attributes['style']?.contains('background-image') ?? false) {
        e.attributes['style'] = e.attributes['style']!.replaceAll(RegExp(r'background-image:[^;]+;'), '');
      }
    });

    // 5. Image & Card Aesthetic Transformation
    main!.querySelectorAll('img').forEach((img) {
      String src = (img.attributes['src'] ?? '').toLowerCase();
      bool small = src.contains('icon') || src.contains('logo') || src.contains('tick') || (img.attributes['width'] != null && int.tryParse(img.attributes['width']!) != null && int.parse(img.attributes['width']!) < 60);
      if (small) {
        img.attributes['style'] = 'width: 32px; height: 32px; object-fit: contain; display: inline-block; vertical-align: middle; margin: 4px;';
      } else {
        img.attributes['style'] = 'width: 100%; height: auto; border-radius: 24px; margin: 24px 0; display: block; box-shadow: 0 16px 40px rgba(0,0,0,0.06);';
      }
    });

    main!.querySelectorAll('ul').forEach((ul) {
      if (ul.text.length < 600) {
        ul.attributes['style'] = 'list-style: none; padding: 0; margin: 24px 0;';
        ul.querySelectorAll('li').forEach((li) {
          li.attributes['style'] = 'background: #FFFFFF; border: 1.5px solid #F1F5F9; padding: 22px; margin-bottom: 14px; border-radius: 20px; font-weight: 700; color: #1E293B; box-shadow: 0 4px 10px rgba(0,0,0,0.03); display: flex; align-items: center;';
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
    await controller.loadRequest(Uri.parse(url));
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

  Future<void> _applyWebsite(String url, {required bool persist}) async {
    final normalizedUrl = _normalizeWebsiteUrl(url);

    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsWebsiteUrlKey, normalizedUrl);
    }

    _history.clear();
    ref.read(webProvider.notifier).updateMenu(const []);
    ref.read(webProvider.notifier).setUrl(normalizedUrl);

    if (!mounted) return;
    setState(() {
      initialUrl = normalizedUrl;
      currentUrl = normalizedUrl;
      htmlContent = null;
      pageTitle = _defaultTitle;
      errorMessage = null;
      loadingProgress = 0;
      canGoBack = false;
      canGoForward = false;
      isPagePresentationReady = false;
    });
    _updatePageSubtitle(normalizedUrl);

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
          const selectors = [
            'header a',
            'nav a',
            '[role="navigation"] a',
            '.menu a',
            '.navbar a',
            '.nav a',
            '.elementor-nav-menu a',
            '.et-menu a'
          ];
          const anchors = document.querySelectorAll(selectors.join(','));
          const seen = new Set();
          const items = [];

          for (const anchor of anchors) {
            const label = (anchor.innerText || anchor.textContent || '')
              .replace(/\s+/g, ' ')
              .trim();
            const href = anchor.href || anchor.getAttribute('href') || '';

            if (!label || label.length < 2 || label.length > 22 || !href) continue;
            if (!/^https?:/i.test(href)) continue;
            if (/facebook|instagram|twitter|linkedin|youtube|whatsapp|mailto:|tel:/i.test(href)) continue;

            const key = `${label.toLowerCase()}|${href.replace(/\/$/, '').toLowerCase()}`;
            if (seen.has(key)) continue;
            seen.add(key);

            items.push({ label, url: href });
            if (items.length >= 8) break;
          }

          return JSON.stringify(items);
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
              header,
              nav,
              [role="banner"],
              [role="navigation"],
              .top-bar,
              .topbar,
              .header-top,
              .site-header,
              .main-header,
              .mobile-header,
              .mobile_nav,
              .et_mobile_menu,
              .elementor-location-header,
              .elementor-sticky--active,
              .et-l--header,
              .ast-above-header-wrap,
              .ast-primary-header-bar,
              .ast-mobile-header-wrap,
              #main-header,
              #masthead,
              #top-bar,
              #header,
              #site-header,
              .menu-toggle,
              .hamburger,
              .navbar,
              .offcanvas-menu,
              .elementor-nav-menu--dropdown,
              [data-elementor-type="header"] {
                display: none !important;
                visibility: hidden !important;
                max-height: 0 !important;
                min-height: 0 !important;
                opacity: 0 !important;
                pointer-events: none !important;
                margin: 0 !important;
                padding: 0 !important;
                overflow: hidden !important;
              }

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
            el.setAttribute('aria-hidden', 'true');
          };

          const looksLikeTopChrome = (el) => {
            const computed = window.getComputedStyle(el);
            const rect = el.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) return false;

            const name = `${el.id || ''} ${typeof el.className === 'string' ? el.className : ''}`.toLowerCase();
            const text = `${el.innerText || ''} ${name}`.replace(/\s+/g, ' ').trim().toLowerCase();
            const keywordMatch = /header|topbar|top-bar|navbar|nav|menu|toolbar|masthead|social|contact-bar/.test(name);
            const hasPhoneOrSocial = /facebook|instagram|twitter|linkedin|pinterest|youtube|\+\d|\bcall\b|\bcontact\b/.test(text);
            const hasLinkCluster = el.querySelectorAll('a').length >= 3;
            const nearTop = rect.top <= 140;
            const wide = rect.width >= window.innerWidth * 0.7;
            const shortBand = rect.height <= 220;
            const pinned = computed.position === 'fixed' || computed.position === 'sticky';

            return nearTop && wide && shortBand && (keywordMatch || hasPhoneOrSocial || (pinned && hasLinkCluster));
          };

          const removeEmptySpacers = () => {
            for (const el of Array.from(document.querySelectorAll('section, div'))) {
              if (el.dataset.nativeSpacerChecked === '1') continue;
              el.dataset.nativeSpacerChecked = '1';

              const computed = window.getComputedStyle(el);
              const rect = el.getBoundingClientRect();
              const text = (el.innerText || '').replace(/\s+/g, ' ').trim();
              const hasMedia = el.querySelector('img, picture, video, svg, canvas, iframe, form, input, button, textarea') !== null;
              const hasBackgroundImage = computed.backgroundImage && computed.backgroundImage !== 'none';

              if (!hasMedia && !hasBackgroundImage && text.length === 0 && rect.height >= 90) {
                hideElement(el);
              }
            }
          };

          const hideFloatingWidgets = () => {
            const floatingKeywords = ['chat', 'whatsapp', 'call', 'support', 'help', 'messenger', 'tawk', 'crisp'];
            for (const el of Array.from(document.querySelectorAll('body *'))) {
              const computed = window.getComputedStyle(el);
              const name = `${el.id || ''} ${typeof el.className === 'string' ? el.className : ''}`.toLowerCase();
              const rect = el.getBoundingClientRect();
              const isFloating = computed.position === 'fixed' || computed.position === 'sticky';
              const looksLikeWidget = floatingKeywords.some((keyword) => name.includes(keyword));
              const isSmallBottomWidget = isFloating &&
                rect.width > 0 &&
                rect.width < 240 &&
                rect.height > 0 &&
                rect.height < 240 &&
                rect.bottom > (window.innerHeight - 40);

              if (looksLikeWidget || isSmallBottomWidget) {
                hideElement(el);
              }
            }
          };

          const hideChrome = () => {
            document.querySelectorAll('header, nav, [role="banner"], [role="navigation"], [class], [id]').forEach((el) => {
              if (looksLikeTopChrome(el)) {
                hideElement(el);
              }
            });

            hideFloatingWidgets();
            removeEmptySpacers();
            document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');
            document.body.style.setProperty('overflow-x', 'hidden', 'important');
          };

          hideChrome();

          if (!window.__nativeAppShellObserver) {
            const observer = new MutationObserver(() => hideChrome());
            observer.observe(document.documentElement, {
              childList: true,
              subtree: true,
              attributes: true,
            });
            window.__nativeAppShellObserver = observer;
          }

          const floatingKeywords = ['chat', 'whatsapp', 'call', 'support', 'help', 'messenger', 'tawk', 'crisp'];
          for (const el of Array.from(document.querySelectorAll('body *'))) {
            const computed = window.getComputedStyle(el);
            const name = `${el.id || ''} ${el.className || ''}`.toLowerCase();
            const rect = el.getBoundingClientRect();
            const isFloating = computed.position === 'fixed' || computed.position === 'sticky';
            const looksLikeWidget = floatingKeywords.some((keyword) => name.includes(keyword));
            const isSmallBottomWidget = isFloating &&
              rect.width > 0 &&
              rect.width < 220 &&
              rect.height > 0 &&
              rect.height < 220 &&
              rect.bottom > (window.innerHeight - 32);

            if (looksLikeWidget || isSmallBottomWidget) {
              hideElement(el);
            }
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
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await _applyNativeChromeHiding();
    await Future<void>.delayed(const Duration(milliseconds: 220));
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
    final host = uri?.host ?? '';
    if (!mounted) return;
    setState(() {
      pageSubtitle = host.isEmpty ? _defaultSubtitle : host.replaceFirst('www.', '');
    });
  }

  String _sanitizeTitle(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return _defaultTitle;
    final title = trimmed.split('|').first.split('-').first.trim();
    if (title.isEmpty) return _defaultTitle;
    return title.length > 24 ? '${title.substring(0, 21)}...' : title;
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

  Future<void> _goHome() async {
    final url = initialUrl;
    if (url == null) return;
    await _fetchPage(url, addToHistory: false);
  }

  Future<void> _goForward() async {
    final controller = _controller;
    if (controller == null) return;
    if (await controller.canGoForward()) {
      await controller.goForward();
      await _syncBrowserState();
    }
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
    final inputController = TextEditingController(text: currentUrl ?? initialUrl ?? '');
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
                      setModalState(() => validationMessage = 'Website URL is required.');
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
                      setModalState(() => validationMessage = 'Enter a valid website URL.');
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

  List<Map<String, String>> _extractNavigationItemsFromHtml(String html, String baseUrl) {
    final document = html_parser.parse(html);
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null) return const [];

    final anchors = document.querySelectorAll(
      'header a, nav a, [role="navigation"] a, .menu a, .navbar a, .nav a, .elementor-nav-menu a, .et-menu a',
    );

    final items = <Map<String, String>>[];
    final seen = <String>{};

    for (final anchor in anchors) {
      final label = anchor.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      final href = anchor.attributes['href'];
      if (label.isEmpty || label.length < 2 || label.length > 22 || href == null || href.isEmpty) {
        continue;
      }

      if (href.startsWith('#') || href.startsWith('mailto:') || href.startsWith('tel:')) {
        continue;
      }

      final resolvedUrl = baseUri.resolve(href).toString();
      final key = '${label.toLowerCase()}|${_normalizeUrlKey(resolvedUrl)}';
      if (seen.contains(key)) continue;
      if (_looksLikeExternalSocialLink(resolvedUrl)) continue;

      seen.add(key);
      items.add({'label': label, 'url': resolvedUrl});
      if (items.length >= 8) break;
    }

    return items;
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

  void _applyMenuItems(List<Map<String, String>> rawItems, {String? activeUrl}) {
    final siteUrl = activeUrl ?? currentUrl ?? initialUrl;
    final siteUri = Uri.tryParse(siteUrl ?? '');
    if (siteUri == null) {
      ref.read(webProvider.notifier).updateMenu(const []);
      return;
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
      if (label.isEmpty || url.isEmpty) continue;

      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) continue;
      if (!_belongsToSameSite(siteUri, uri)) continue;

      final normalizedUrl = _normalizeUrlKey(uri.toString());
      final normalizedLabel = label.toLowerCase();
      if (seenUrls.contains(normalizedUrl) || seenLabels.contains(normalizedLabel)) continue;

      seenUrls.add(normalizedUrl);
      seenLabels.add(normalizedLabel);
      items.add(WebItem(label: label, url: uri.toString(), icon: _iconForLabel(label)));
      if (items.length >= 6) break;
    }

    ref.read(webProvider.notifier).updateMenu(items.length > 1 ? items : const []);
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
    if (text.contains('service') || text.contains('product') || text.contains('shop')) {
      return Icons.grid_view_rounded;
    }
    if (text.contains('contact') || text.contains('support')) return Icons.support_agent_rounded;
    if (text.contains('blog') || text.contains('news')) return Icons.article_rounded;
    if (text.contains('portfolio') || text.contains('work')) return Icons.workspaces_rounded;
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

  Future<void> _showToolsSheet() async {
    final state = ref.read(webProvider);
    final menuItems = state.menuItems;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Menu',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (menuItems.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Sections',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...menuItems.map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(item.icon ?? Icons.language_rounded, color: AppColors.primary),
                        title: Text(item.label),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_fetchPage(item.url));
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Tools',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _SheetActionChip(
                        icon: Icons.arrow_back_rounded,
                        label: 'Back',
                        enabled: _usesWebView ? canGoBack : _history.isNotEmpty,
                        onTap: () {
                          Navigator.pop(context);
                          _handleBack();
                        },
                      ),
                      _SheetActionChip(
                        icon: Icons.arrow_forward_rounded,
                        label: 'Next',
                        enabled: _usesWebView ? canGoForward : false,
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_goForward());
                        },
                      ),
                      _SheetActionChip(
                        icon: Icons.refresh_rounded,
                        label: 'Reload',
                        enabled: currentUrl != null,
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_refreshCurrentPage());
                        },
                      ),
                      _SheetActionChip(
                        icon: Icons.home_rounded,
                        label: 'Home',
                        enabled: initialUrl != null,
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_goHome());
                        },
                      ),
                      _SheetActionChip(
                        icon: Icons.open_in_new_rounded,
                        label: 'Open Browser',
                        enabled: currentUrl != null,
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_openInBrowser());
                        },
                      ),
                      _SheetActionChip(
                        icon: Icons.link_rounded,
                        label: 'Change Site',
                        enabled: true,
                        onTap: () {
                          Navigator.pop(context);
                          unawaited(_showWebsiteSwitcher());
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBarTitle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          pageTitle.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          pageSubtitle,
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

  Widget _buildBrowserSurface(WebState state) {
    if (_usesWebView) {
      final controller = _controller;
      if (controller == null) {
        return const Center(child: Text('Browser engine is not ready.'));
      }

      final showLoadingCover = state.isLoading || !isPagePresentationReady;

      return Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: controller)),
          if (showLoadingCover)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xFFF8FAFC),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x120F172A),
                              blurRadius: 18,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Preparing app view...',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
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
                minHeight: 2.5,
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
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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

  Widget _buildWebsiteDock(WebState state) {
    final items = state.menuItems.take(4).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x240F172A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            ...items.map(
              (item) => Expanded(
                child: _DockNavItem(
                  icon: item.icon ?? Icons.language_rounded,
                  label: item.label,
                  selected: _isSelectedMenuItem(item),
                  onTap: () => unawaited(_fetchPage(item.url)),
                ),
              ),
            ),
            Expanded(
              child: _DockNavItem(
                icon: Icons.menu_rounded,
                label: 'Menu',
                selected: false,
                onTap: () => unawaited(_showToolsSheet()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final hasCurrentUrl = (currentUrl ?? initialUrl) != null;
    final canStepBack = _usesWebView ? canGoBack : _history.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2A0F172A),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _BrowserActionButton(
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                enabled: canStepBack,
                onTap: _handleBack,
              ),
            ),
            Expanded(
              child: _BrowserActionButton(
                icon: Icons.arrow_forward_rounded,
                label: 'Next',
                enabled: _usesWebView ? canGoForward : false,
                onTap: () => unawaited(_goForward()),
              ),
            ),
            Expanded(
              child: _BrowserActionButton(
                icon: Icons.home_rounded,
                label: 'Home',
                enabled: initialUrl != null,
                onTap: () => unawaited(_goHome()),
              ),
            ),
            Expanded(
              child: _BrowserActionButton(
                icon: Icons.refresh_rounded,
                label: 'Reload',
                enabled: hasCurrentUrl,
                onTap: () => unawaited(_refreshCurrentPage()),
              ),
            ),
            Expanded(
              child: _BrowserActionButton(
                icon: Icons.menu_rounded,
                label: 'Menu',
                enabled: true,
                onTap: () => unawaited(_showToolsSheet()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: _buildAppBarTitle(),
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary, size: 24),
            onPressed: _handleBack,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8), size: 22),
              onPressed: () => unawaited(_refreshCurrentPage()),
            ),
            IconButton(
              icon: const Icon(Icons.menu_rounded, color: Color(0xFF94A3B8), size: 22),
              onPressed: () => unawaited(_showToolsSheet()),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _buildBrowserSurface(state),
        bottomNavigationBar: state.menuItems.length > 1
            ? _buildWebsiteDock(state)
            : _buildBottomControls(),
        extendBody: false,
      ),
    );
  }
}

class _DockNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DockNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFF94A3B8);
    final background = selected ? const Color(0xFF1E293B) : Colors.transparent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground, size: 19),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _BrowserActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.white : const Color(0xFF64748B);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _SheetActionChip({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? const Color(0xFF0F172A) : const Color(0xFF94A3B8);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
