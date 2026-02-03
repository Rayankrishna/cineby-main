import 'package:app_web_ui/services/config.dart';
import 'package:adblocker_webview/adblocker_webview.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MyWidget extends StatefulWidget {
  final String? url;
  const MyWidget({super.key, this.url});

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final _adBlockerWebviewController = AdBlockerWebviewController.instance;
  late String _currentUrl;
  Key _webViewKey = UniqueKey();

  final InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: true,
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false, // BLOCKS POP-UNDERS
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllowFullscreen: true,
  );

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url ?? serverurl;
    _initAdBlocker();
    WakelockPlus.enable();
  }

  Future<void> _initAdBlocker() async {
    await _adBlockerWebviewController.initialize(
      FilterConfig(filterTypes: [FilterType.easyList, FilterType.adGuard]),
      [],
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  InAppWebViewController? _webViewController;

  bool _isAdUrl(String url) {
    final adDomains = [
      "popads",
      "monetag",
      "doubleclick",
      "adsystem",
      "popcash",
      "propellerads",
      "adsterra",
      "googlesyndication",
      "google-analytics",
      "facebook.com/tr",
      "adservice",
      "bet365",
      "1xbet",
    ];
    return adDomains.any((domain) => url.contains(domain));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: InAppWebView(
          key: _webViewKey,
          initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
          initialSettings: settings,
          onWebViewCreated: (controller) {
            _webViewController = controller;
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            if (uri != null && _isAdUrl(uri.toString())) {
              // Block navigation to known ad domains
              debugPrint("Blocked ad URL: $uri");
              if (await controller.canGoBack()) {
                controller.goBack();
              } else {
                setState(() {
                  _webViewKey = UniqueKey();
                });
              }
              return NavigationActionPolicy.CANCEL;
            }
            // Update current valid URL
            if (uri != null) {
              _currentUrl = uri.toString();
            }
            return NavigationActionPolicy.ALLOW;
          },
          // Optional: Intercept requests to block ad assets
          shouldInterceptRequest: (controller, request) async {
            if (_isAdUrl(request.url.toString())) {
              return WebResourceResponse();
            }
            return null;
          },
        ),
      ),
    );
  }
}
