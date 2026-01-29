import 'dart:math' as waveMath;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WaveFishCalendarHelpLite extends StatefulWidget {
  const WaveFishCalendarHelpLite({super.key});

  @override
  State<WaveFishCalendarHelpLite> createState() =>
      _WaveFishCalendarHelpLiteState();
}

class _WaveFishCalendarHelpLiteState extends State<WaveFishCalendarHelpLite> {
  InAppWebViewController? waveFishCalendarWebViewController;
  bool waveFishCalendarLoading = true;

  Future<bool> waveFishCalendarGoBackInWebViewIfPossible() async {
    if (waveFishCalendarWebViewController == null) return false;
    try {
      final bool waveFishCalendarCanBack =
      await waveFishCalendarWebViewController!.canGoBack();
      if (waveFishCalendarCanBack) {
        await waveFishCalendarWebViewController!.goBack();
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext waveFishCalendarContext) {
    return WillPopScope(
      onWillPop: () async {
        final bool waveFishCalendarHandled =
        await waveFishCalendarGoBackInWebViewIfPossible();
        return waveFishCalendarHandled ? false : false;
      },
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.black,
        
          body: Stack(
            children: <Widget>[
              InAppWebView(
                initialFile: 'assets/Meter.html',
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  supportZoom: false,
                  disableHorizontalScroll: false,
                  disableVerticalScroll: false,
                  transparentBackground: true,
                  mediaPlaybackRequiresUserGesture: false,
                  disableDefaultErrorPage: true,
                  allowsInlineMediaPlayback: true,
                  allowsPictureInPictureMediaPlayback: true,
                  useOnDownloadStart: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                ),
                onWebViewCreated:
                    (InAppWebViewController waveFishCalendarController) {
                  waveFishCalendarWebViewController =
                      waveFishCalendarController;
                },
                onLoadStart: (
                    InAppWebViewController waveFishCalendarController,
                    Uri? waveFishCalendarUrl,
                    ) =>
                    setState(() => waveFishCalendarLoading = true),
                onLoadStop: (
                    InAppWebViewController waveFishCalendarController,
                    Uri? waveFishCalendarUrl,
                    ) async =>
                    setState(() => waveFishCalendarLoading = false),
                onLoadError: (
                    InAppWebViewController waveFishCalendarController,
                    Uri? waveFishCalendarUrl,
                    int waveFishCalendarCode,
                    String waveFishCalendarMessage,
                    ) =>
                    setState(() => waveFishCalendarLoading = false),
              ),
        
              // Лоадер по середине экрана
              if (waveFishCalendarLoading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black87,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

