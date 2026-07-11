import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String movieTitle;

  const PlayerScreen({
    Key? key,
    required this.streamUrl,
    required this.movieTitle,
  }) : super(key: key);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    // Force fullscreen landscape orientation for watching the movie
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Setup the WebView controller to run the iframe player webpage
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress > 80) {
              setState(() => _isLoading = false);
            }
          },
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            print("WebView resource error: ${error.description}");
          },
        ),
      )
      // Browser User-Agent and Referer header to bypass anti-hotlink checks
      ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
      ..loadRequest(
        Uri.parse(widget.streamUrl),
        headers: {
          'Referer': 'https://${Uri.parse(widget.streamUrl).host}/',
        },
      );
  }

  @override
  void dispose() {
    // Restore default portrait screen orientation on player exit
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Embedded Browser Player
          Positioned.fill(
            child: WebViewWidget(controller: _controller),
          ),

          // 2. Loading Indicator Overlay
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.red),
                ),
              ),
            ),

          // 3. Floating D-pad/Touch friendly close button (focused at top-left)
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Focus(
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                      style: IconButton.styleFrom(
                        backgroundColor: focused ? Colors.red : Colors.black.withOpacity(0.5),
                        side: BorderSide(
                          color: focused ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
