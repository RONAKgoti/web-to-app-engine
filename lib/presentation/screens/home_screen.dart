import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
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
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:in_app_review/in_app_review.dart';

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
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

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
    _setupOfflineManager();
    _loadAndFetch();
  }

  Future<void> _checkAndPromptReview(String url) async {
     final l = url.toLowerCase();
     if (l.contains('success') || l.contains('thank-you') || l.contains('confirmed') || l.contains('order')) {
        final prefs = await SharedPreferences.getInstance();
        final hasPrompted = prefs.getBool('hasPromptedReview') ?? false;
        
        if (!hasPrompted) {
           await prefs.setBool('hasPromptedReview', true);
           final InAppReview inAppReview = InAppReview.instance;
           if (await inAppReview.isAvailable()) {
              // Add slight delay so it doesn't block page rendering
              Future.delayed(const Duration(seconds: 3), () {
                 inAppReview.requestReview();
              });
           }
        }
     }
  }

  void _setupOfflineManager() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
       final isDisconnected = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
       
       if (isDisconnected != _isOffline) {
          if (!mounted) return;
          setState(() {
             _isOffline = isDisconnected;
          });
          
          if (!isDisconnected) {
             // Internet restored! Auto-refresh.
             unawaited(_refreshCurrentPage());
          }
       }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _dio.close();
    super.dispose();
  }

  WebViewController _buildWebViewController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..enableZoom(false);

    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      (controller.platform as AndroidWebViewController).setMediaPlaybackRequiresUserGesture(false);
      // Auto-grant permissions on Android if the native app itself holds them
      (controller.platform as AndroidWebViewController)
          .setOnPlatformPermissionRequest((request) {
        request.grant();
      });
    }
      
    controller.addJavaScriptChannel(
      'NativeAppChannel',
      onMessageReceived: (JavaScriptMessage message) {
        if (!mounted) return;
        final msg = message.message;
        if (msg.startsWith('url|')) {
           final newUrl = msg.substring(4);
           _updateCurrentUrl(newUrl);
           unawaited(_refreshNativePresentation());
        }
      },
    );

    controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => loadingProgress = progress);
            if (progress > 30) {
               unawaited(_applyNativeChromeHiding());
            }
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url == null || url.isEmpty) return;
            _requestedUrl = url;
            _updateCurrentUrl(url);
            unawaited(_refreshNativePresentation());
            unawaited(_checkAndPromptReview(url));
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
            unawaited(_injectSPAMonitor());
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
            
            // File Download Interceptor
            final lowercaseUrl = request.url.toLowerCase();
            final isFileDownload = lowercaseUrl.endsWith('.pdf') || 
                                   lowercaseUrl.endsWith('.zip') || 
                                   lowercaseUrl.endsWith('.csv') || 
                                   lowercaseUrl.endsWith('.docx') ||
                                   lowercaseUrl.contains('/download');

            if (isWebUrl && !isFileDownload) return NavigationDecision.navigate;
            
            // Launch Non-Web Intents OR File Downloads externally
            try {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted && !isFileDownload) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Cannot open link on this device: ${uri.scheme}'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            } catch (e) {
              debugPrint('Launch Error: $e');
            }
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

    return controller;
  }

  Future<void> _injectSPAMonitor() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    try {
      const js = r'''
        (() => {
          if (window._nativeAppMonitorInjected) return;
          window._nativeAppMonitorInjected = true;

          const notifyNative = () => {
             if (window.NativeAppChannel) {
                 window.NativeAppChannel.postMessage('url|' + window.location.href);
             }
          };

          // Override pushState for SPAs
          const originalPushState = history.pushState;
          history.pushState = function() {
             originalPushState.apply(this, arguments);
             notifyNative();
          };

          const originalReplaceState = history.replaceState;
          history.replaceState = function() {
             originalReplaceState.apply(this, arguments);
             notifyNative();
          };

          window.addEventListener('popstate', notifyNative);
        })();
      ''';
      await controller.runJavaScript(js);
    } catch (_) {}
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
            let label = normalizeLabel(
              element.innerText ||
              element.textContent ||
              element.getAttribute('aria-label') ||
              ''
            );
            
            // 1. DYNAMIC SCRAPING (Primary labels)
            let label = normalizeLabel(element.innerText || '');
            
            // 2. ICON-ONLY FALLBACK (Critical for Myntra/Amazon)
            if (!label || label.length < 2) {
               label = element.getAttribute('aria-label') || 
                       element.getAttribute('title') || 
                       element.getAttribute('data-label') || '';
               label = normalizeLabel(label);
            }
            
            // 3. HREF HEURISTIC (Last resort for e-commerce)
            const href = resolveHref(element);
            if (!label && href) {
                const hl = href.toLowerCase();
                const pathParts = hl.split('/').filter(p => p.length > 2);
                const lastSegment = pathParts[pathParts.length - 1] || '';

                if (hl.includes('cart') || hl.includes('bag')) label = 'Cart';
                else if (hl.includes('wishlist')) label = 'Wishlist';
                else if (hl.includes('profile') || hl.includes('account') || hl.includes('user') || hl.includes('my-account')) label = 'Profile';
                else if (hl.includes('search') || hl.includes('/q=')) label = 'Search';
                else if (hl.includes('login') || hl.includes('signin')) label = 'Login';
                else if (hl.includes('category') || hl.includes('shop') || hl.includes('department')) label = 'Categories';
                else if (lastSegment.length > 2 && lastSegment.length < 15) label = lastSegment;
            }


            if (!label || label.length < 2 || label.length > 24) return null;
            if (invalidLabelPattern.test(label)) return null;

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

            // Look inside the container for links AND explicit E-commerce icons
            for (const element of Array.from(container.querySelectorAll(
              'a[href], button, [role="button"], [role="tab"], [tabindex="0"], a[data-testid="bagIcon"], a[data-testid="wishlistIcon"], a[data-testid="profileIcon"]'
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
            const keywordMatch = /nav|menu|tab|toolbar|bottom|footer|header|desktop-logoContainer|actions-container/.test(identity);
            
            // App-First Navigation Priority Boost
            let appNavBoost = 0;
            const appWords = ['home', 'category', 'categories', 'deal', 'offer', 'account', 'profile', 'bag', 'cart', 'shop', 'order', 'sign', 'login', 'men', 'women', 'kid', 'search'];
            for(const item of items) {
              const lbl = item.label.toLowerCase();
              if(appWords.some(w => lbl.includes(w))) appNavBoost += 250; 
              if(lbl.length > 2 && lbl.length < 15) appNavBoost += 40;
            }

            const textPenalty = Math.max(0, text.length - 280);
            const sizePenalty = items.length > 8 ? (items.length - 8) * 50 : 0;

            return (items.length * 120) +
              (shortLabels * 35) +
              (nearTop ? 150 : 0) + 
              (nearBottom ? 100 : 0) +
              (pinned ? 120 : 0) +
              (keywordMatch ? 180 : 0) +
              appNavBoost - 
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
      const js = r'''
        (() => {
          const SCRAPER_ID = 'native-app-chrome-hider-u12';
          const h = window.innerHeight;
          const w = window.innerWidth;

          // 1. Target by common selectors (Smart Stripping)
          // Removed 'header' and 'nav' since we want to keep the website's top navigation bar
          const selectors = [
            'footer', '.wpadminbar', '#wpadminbar',
            '.elementor-location-footer',
            '.td-footer-wrap', '.tp-bullets', '.rev_slider_wrapper',
            '[class*="bottom-nav"]', '[class*="bottomNav"]', '[class*="mobile-bottom"]',
            '[id*="bottom-nav"]', '[id*="bottomNav"]', '.mobile-navigation-bar', 
            '.bnav', '.bottomBar', '.footer-nav'
          ];

          selectors.forEach(sel => {
            document.querySelectorAll(sel).forEach(el => {
              el.style.setProperty('display', 'none', 'important');
              el.style.setProperty('visibility', 'hidden', 'important');
            });
          });

          // 2. Position-based Chrome Hiding (Protects Subpages)
          document.querySelectorAll('body *').forEach(el => {
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            const textLength = el.innerText.trim().length;
            
            // Only hide bars at the BOTTOM that are NOT the main content
            const isBottomBar = rect.bottom >= (h - 150) && rect.height < 250;
            const isFixedBottom = (style.position === 'fixed' || style.position === 'sticky') && (rect.bottom >= (h - 150)) && rect.height < 250;

            // CRITICAL: Protection for Main Content
            const isMainArea = el.matches('main, article, section, #main, .main, #content, .content, #main-content, [role="main"]');
            const hasSubstantialText = textLength > 100;
            
            if ((isBottomBar || isFixedBottom) && !isMainArea && !hasSubstantialText) {
                // Heuristic filtering: Only hide if it looks like a menu/nav/footer
                const identity = (el.className + el.id).toLowerCase();
                if (/nav|menu|footer|tab|bar|social|widget|bottom/.test(identity) || rect.width >= (window.innerWidth * 0.8)) {
                   el.style.setProperty('display', 'none', 'important');
                   el.style.setProperty('height', '0', 'important');
                   el.style.setProperty('pointer-events', 'none', 'important');
                }
            }
          });

          // 3. Persistent Global Style (Universal Fixes)
          if (!document.getElementById(SCRAPER_ID)) {
             const css = document.createElement('style');
             css.id = SCRAPER_ID;
             css.innerHTML = `
               .wpadminbar, #wpadminbar, .elementor-location-footer,
               [class*="td-footer-wrap"], .tp-bullets,
               /* Cookie & GDPR Banner Annihilation */
               #onetrust-consent-sdk, #cookie-notice, .cookie-banner, .cc-window,
               .cc-banner, .gdpr-cookie-consent, [id*="cookie"], [class*="cookie"],
               /* Search/Filter Overlay Cleanup (Only if fixed/redundant) */
               .search-overlay-fixed, 
               /* SCRAPER TARGETED ELEMENTS (Amazon/Myntra Bar Fix) */
               [data-native-app-chrome="1"] {
                 display: none !important;
                 visibility: hidden !important;
                 opacity: 0 !important;
                 height: 0 !important;
                 pointer-events: none !important;
               }
               
               /* Universal Scroll-Lock & Zoom Rescuer */
               html.no-scroll, body.no-scroll, html.modal-open, body.modal-open {
                 overflow: auto !important;
               }
               
               body { 
                 padding-bottom: 92px !important; 
                 -webkit-tap-highlight-color: transparent !important;
                 -webkit-touch-callout: none !important;
                 /* Prevent accidental zoom-ins on double-tap or focus */
                 touch-action: pan-x pan-y !important;
                 -webkit-text-size-adjust: 100% !important;
                 
                 -webkit-user-select: none !important;
                 user-select: none !important;
                 /* Fix for scrolling issues on complex sites like TCS */
                 height: auto !important;
                 min-height: 100vh !important;
               }
               
               /* Preserve selection for inputs and FIX ZOOM on FOCUS */
               input, textarea, [contenteditable="true"], select {
                 -webkit-user-select: auto !important;
                 user-select: auto !important;
                 font-size: 16px !important; /* Prevents auto-zoom on iOS Safari-based webviews */
               }
               
               /* Ad-Slot Space Cleanup */
               ins.adsbygoogle, .ad-unit, [id*="google_ads"] {
                 display: none !important;
               }
             `;
             document.head.appendChild(css);
             
             // 4. Viewport Lock (Universal Professional)
             let viewport = document.querySelector('meta[name="viewport"]');
             if (viewport) {
               viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
             } else {
               viewport = document.createElement('meta');
               viewport.name = "viewport";
               viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
               document.head.appendChild(viewport);
             }
             
             // Block context menu
             window.addEventListener('contextmenu', e => { 
                if(!['INPUT', 'TEXTAREA'].includes(e.target.tagName)) e.preventDefault(); 
             });
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
    // 1. Label Sanitization (Remove Junk like Support/Help from Bottom Bar)
    final filteredRaw = rawItems.where((item) {
      final lbl = (item['label'] ?? '').toLowerCase();
      // Junk terms for a Primary Bottom Bar
      final junkTerms = ['support', 'help', 'contact', 'legal', 'privacy', 'policy', 'return', 'refund', 'terms', 'conditions', 'career', 'shipping'];
      // Only keep if NOT junk OR if there are literally NO other links
      return !junkTerms.any((word) => lbl.contains(word)) || rawItems.length < 3;
    }).toList();

    final items = _buildMenuItemsFromRaw(filteredRaw, activeUrl: activeUrl);
    final existing = ref.read(webProvider).menuItems;


    // RULE: Stability First (Anti-Flicker).
    final bool isHome = _isOnHomePage;
    final bool hasDecentExisting = existing.length >= 3;

    // Quality Score Heuristic (Premium E-commerce Keywords)
    int _getMenuQuality(List<WebItem> menu) {
      if (menu.isEmpty) return 0;
      final premiumWords = ['category', 'deal', 'offer', 'cart', 'bag', 'buy', 'shop', 'pay', 'order', 'wishlist'];
      final junkWords = ['your', 'customer', 'account', 'sign in', 'login', 'support', 'help', 'career', 'shipping', 'privacy', 'policy', 'return', 'refund', 'cookie', 'legal', 'term', 'condition', 'track'];
      
      int score = menu.length * 15;
      for (final item in menu) {
        final lbl = item.label.toLowerCase();
        if (premiumWords.any((w) => lbl.contains(w))) score += 60;
        if (junkWords.any((w) => lbl.contains(w))) score -= 99; // Heavy penalty for boilerplate links
      }
      return score;
    }

    final int newScore = _getMenuQuality(items);
    final int existingScore = _getMenuQuality(existing);

    // Ultimate Stability Rule: Domain Session Lock.
    // Use host to ensure stability across the site
    final String currentHost = Uri.tryParse(activeUrl ?? currentUrl ?? initialUrl ?? '')?.host ?? '';
    final bool isPremiumLock = existingScore >= 180;
    
    bool shouldOverwrite = !hasDecentExisting;
    
    // If we have a Premium Lock and ARE NOT on the home page, NEVER update unless massive upgrade (> 120 gap)
    if (isPremiumLock && !isHome) {
       shouldOverwrite = newScore > (existingScore + 120); // Massive upgrade logic
    } else if (isHome) {
       // On Home page, we allow 'Better or Equal' updates to capture latest lazy-loads
       shouldOverwrite = newScore >= existingScore || !hasDecentExisting;
    } else {
       // Standard logic for sub-pages
       shouldOverwrite = newScore > (existingScore + 80) || !hasDecentExisting;
    }

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
      r'home|shop|store|cart|product|offer|deal|sale|new|collection|brand|men|women|kid|infant|boy|girl|beauty|accessories|fashion|service|contact|support|about|company|career|team|solution|platform|feature|resource|portfolio|work|project|resume|hire|gallery|blog|news|article|story|insight|editorial|event|ticket|booking|schedule|show|movie|pricing|plan|account|profile|user|login',
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
    if (label.contains('shop') || label.contains('store') || label.contains('product')) score += 450;
    if (label.contains('service') || label.contains('solution') || label.contains('platform')) score += 440;
    if (label.contains('about') || label.contains('company')) score += 420;
    if (label.contains('category') || RegExp(r'men|women|kid|beauty').hasMatch(label)) score += 400;
    if (label.contains('portfolio') || label.contains('work') || label.contains('project')) score += 390;
    if (label.contains('offer') || label.contains('deal') || label.contains('sale')) score += 380;
    if (label.contains('movie') || label.contains('show') || label.contains('event') || label.contains('ticket') || label.contains('booking')) score += 370;
    if (label.contains('profile') || label.contains('account') || label.contains('user') || label.contains('login')) score += 350;
    if (label.contains('contact') || label.contains('support')) score += 320;
    if (label.contains('pricing') || label.contains('plan')) score += 300;
    if (label.contains('blog') || label.contains('news') || label.contains('article')) score += 250;
    if (label.contains('cart')) score += 200;

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
    
    // E-commerce & Retail (Stability Focus)
    if (text.contains('shop') || text.contains('store')) return Icons.shopping_bag_rounded;
    if (text.contains('cart') || text.contains('bag') || text.contains('basket')) return Icons.shopping_cart_rounded;
    if (text.contains('product') || text.contains('collection')) return Icons.inventory_2_rounded;
    if (text.contains('deal') || text.contains('offer') || text.contains('sale')) return Icons.local_offer_rounded;
    if (text.contains('new')) return Icons.new_releases_rounded;
    if (text.contains('men') || text.contains('boy')) return Icons.man_rounded;
    if (text.contains('women') || text.contains('girl')) return Icons.woman_rounded;
    if (text.contains('category') || text.contains('browse')) return Icons.subject_rounded;
    if (text.contains('pay') || text.contains('wallet') || text.contains('money')) return Icons.account_balance_wallet_rounded;
    if (text.contains('sign in') || text.contains('account') || text.contains('login') || text.contains('your')) return Icons.person_rounded;
    if (text.contains('wishlist') || text.contains('favorite')) return Icons.favorite_rounded;
    
    // Tech & Media
    if (text.contains('web') || text.contains('site')) return Icons.language_rounded;
    if (text.contains('app') || text.contains('mobile')) return Icons.smartphone_rounded;
    if (text.contains('cloud') || text.contains('salesforce')) return Icons.cloud_done_rounded;

    // Corporate & Business
    if (text.contains('service') || text.contains('solution')) return Icons.miscellaneous_services_rounded;
    if (text.contains('contact') || text.contains('support') || text.contains('customer') || text.contains('help')) return Icons.support_agent_rounded;
    if (text.contains('about') || text.contains('company')) return Icons.info_rounded;
    if (text.contains('career')) return Icons.work_rounded;
    if (text.contains('team')) return Icons.groups_rounded;
    if (text.contains('platform') || text.contains('feature')) return Icons.featured_play_list_rounded;
    
    // Portfolio & Freelance
    if (text.contains('portfolio') || text.contains('work')) return Icons.workspaces_rounded;
    if (text.contains('project')) return Icons.folder_open_rounded;
    if (text.contains('resume') || text.contains('cv')) return Icons.description_rounded;
    if (text.contains('gallery')) return Icons.photo_library_rounded;
    
    // Blog & Media
    if (text.contains('blog') || text.contains('news') || text.contains('article')) return Icons.article_rounded;
    if (text.contains('story') || text.contains('insight')) return Icons.auto_stories_rounded;
    
    // Events & Bookings
    if (text.contains('event') || text.contains('show')) return Icons.event_available_rounded;
    if (text.contains('ticket') || text.contains('booking')) return Icons.confirmation_number_rounded;
    if (text.contains('schedule')) return Icons.calendar_today_rounded;
    if (text.contains('movie') || text.contains('cinema')) return Icons.local_movies_rounded;

    // Pricing
    if (text.contains('pricing') || text.contains('plan')) return Icons.payments_rounded;

    // User utility
    if (text.contains('login') || text.contains('account') || text.contains('profile') || text.contains('user')) return Icons.person_rounded;
    
    return Icons.language_rounded;
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
      
      final showLoadingSkeleton =
          errorMessage == null && (state.isLoading || !isPagePresentationReady) && loadingProgress < 75;

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        child: showLoadingSkeleton
            ? const Positioned.fill(
                key: ValueKey('skeleton'),
                child: ColoredBox(
                  color: Color(0xFFF8FAFC),
                  child: IgnorePointer(
                    child: LoadingWidget(),
                  ),
                ),
              )
            : Stack(
                key: const ValueKey('webview'),
                children: [
                  Positioned.fill(
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height,
                      child: WebViewWidget(controller: controller),
                    ),
                  ),
                  if (_isOffline)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.95),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_off_rounded, size: 70, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              const Text(
                                'No Internet Connection',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Retrying automatically...',
                                style: TextStyle(fontSize: 14, color: Colors.black54),
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
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: loadingProgress <= 0 ? null : loadingProgress / 100,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
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
              ),
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
        // App bar removed so the website's native header is the only header
        // End Drawer removed because native websites (Myntra, TechCrunch)
        // already provide their own premium Hamburger Menus.
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              _buildBrowserSurface(state),
            ],
          ),
        ),
        // HIDE BAR WHEN KEYBOARD IS ACTIVE (Myntra Login Fix)
        // The original edit snippet provided a different Scaffold structure.
        // Assuming the intent was to add a conditional bottomNavigationBar
        // or similar element that should hide when the keyboard is active.
        // Since the original Scaffold does not have a bottomNavigationBar,
        // and the provided snippet introduces `widget.navigationShell` and
        // `_buildGlassFloatingBar(finalItems)` which are not defined here,
        // I'm applying the `isKeyboardVisible` logic to a placeholder
        // `bottomNavigationBar` to demonstrate the keyboard visibility check.
        // This part would need to be adapted to the actual "bottom bar" widget
        // that the user intends to hide.
        // For now, I'm adding a dummy bottom navigation bar that hides.
        bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
            ? null // Hide bottom bar when keyboard is active
            : BottomAppBar(
                color: Colors.transparent,
                elevation: 0,
                child: Container(
                  height: 0, // Placeholder for the actual bottom bar
                  // child: _buildGlassFloatingBar(finalItems), // If this widget exists elsewhere
                ),
              ),
      ),
    );
  }
}


