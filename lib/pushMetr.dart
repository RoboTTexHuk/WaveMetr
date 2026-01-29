import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as waveMath;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as waveTimezoneData;
import 'package:timezone/timezone.dart' as waveTimezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
import 'main.dart' show MafiaHarbor, CaptainHarbor, BillHarbor;

// ============================================================================
// Wave инфраструктура и паттерны (бывшая Trip инфраструктура)
// ============================================================================

class WaveTripLogger {
  const WaveTripLogger();

  void waveLogInfo(Object waveMessage) =>
      debugPrint('[WheelLogger] $waveMessage');
  void waveLogWarn(Object waveMessage) =>
      debugPrint('[WheelLogger/WARN] $waveMessage');
  void waveLogError(Object waveMessage) =>
      debugPrint('[WheelLogger/ERR] $waveMessage');
}

class WaveTripVault {
  static final WaveTripVault waveInstance = WaveTripVault._waveInternal();
  WaveTripVault._waveInternal();
  factory WaveTripVault() => waveInstance;

  final WaveTripLogger waveLogger = const WaveTripLogger();
}

// ============================================================================
// Константы (статистика/кеш)
// ============================================================================

const String metrLoadedOnceKey = 'wheel_loaded_once';
const String metrStatEndpoint =
    'https://getgame.portalroullete.bar/stat';
const String metrCachedFcmKey = 'wheel_cached_fcm';

// ============================================================================
// Утилиты: WaveTripKit
// ============================================================================

class WaveTripKit {
  static bool waveLooksLikeBareMail(Uri waveUri) {
    final String waveScheme = waveUri.scheme;
    if (waveScheme.isNotEmpty) return false;
    final String waveRaw = waveUri.toString();
    return waveRaw.contains('@') && !waveRaw.contains(' ');
  }

  static Uri waveToMailto(Uri waveUri) {
    final String waveFull = waveUri.toString();
    final List<String> waveBits = waveFull.split('?');
    final String waveWho = waveBits.first;
    final Map<String, String> waveQuery =
    waveBits.length > 1 ? Uri.splitQueryString(waveBits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: waveWho,
      queryParameters: waveQuery.isEmpty ? null : waveQuery,
    );
  }

  static Uri waveGmailize(Uri waveMailUri) {
    final Map<String, String> waveQp = waveMailUri.queryParameters;
    final Map<String, String> waveParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (waveMailUri.path.isNotEmpty) 'to': waveMailUri.path,
      if ((waveQp['subject'] ?? '').isNotEmpty) 'su': waveQp['subject']!,
      if ((waveQp['body'] ?? '').isNotEmpty) 'body': waveQp['body']!,
      if ((waveQp['cc'] ?? '').isNotEmpty) 'cc': waveQp['cc']!,
      if ((waveQp['bcc'] ?? '').isNotEmpty) 'bcc': waveQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', waveParams);
  }

  static String waveDigitsOnly(String waveSource) =>
      waveSource.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия ссылок: WaveTripLinker
// ============================================================================

class WaveTripLinker {
  static Future<bool> waveOpen(Uri waveUri) async {
    try {
      if (await launchUrl(
        waveUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }
      return await launchUrl(
        waveUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (waveError) {
      debugPrint('WheelLinker error: $waveError; url=$waveUri');
      try {
        return await launchUrl(
          waveUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler
// ============================================================================

@pragma('vm:entry-point')
Future<void> waveFcmBackgroundHandler(RemoteMessage waveMessage) async {
  debugPrint("Spin ID: ${waveMessage.messageId}");
  debugPrint("Spin Data: ${waveMessage.data}");
}

// ============================================================================
// WaveDeviceProfile
// ============================================================================

class WaveDeviceProfile {
  String? waveDeviceId;
  String? waveSessionId = 'wheel-one-off';
  String? wavePlatformKind;
  String? waveOsBuild;
  String? waveAppVersion;
  String? waveLocaleCode;
  String? waveTimezoneName;
  bool wavePushEnabled = true;

  Future<void> waveInitialize() async {
    final DeviceInfoPlugin waveInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo waveAndroidInfo =
      await waveInfoPlugin.androidInfo;
      waveDeviceId = waveAndroidInfo.id;
      wavePlatformKind = 'android';
      waveOsBuild = waveAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo waveIosInfo = await waveInfoPlugin.iosInfo;
      waveDeviceId = waveIosInfo.identifierForVendor;
      wavePlatformKind = 'ios';
      waveOsBuild = waveIosInfo.systemVersion;
    }

    final PackageInfo wavePackageInfo = await PackageInfo.fromPlatform();
    waveAppVersion = wavePackageInfo.version;
    waveLocaleCode = Platform.localeName.split('_').first;
    waveTimezoneName = waveTimezone.local.name;
    waveSessionId = 'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> waveAsMap({String? waveFcmToken}) => <String, dynamic>{
    'fcm_token': waveFcmToken ?? 'missing_token',
    'device_id': waveDeviceId ?? 'missing_id',
    'app_name': 'joiler',
    'instance_id': waveSessionId ?? 'missing_session',
    'platform': wavePlatformKind ?? 'missing_system',
    'os_version': waveOsBuild ?? 'missing_build',
    'app_version': waveAppVersion ?? 'missing_app',
    'language': waveLocaleCode ?? 'en',
    'timezone': waveTimezoneName ?? 'UTC',
    'push_enabled': wavePushEnabled,
  };
}

// ============================================================================
// AppsFlyer шпион: WaveTripSpy
// ============================================================================

class WaveTripSpy {
  AppsFlyerOptions? waveOptions;
  AppsflyerSdk? waveSdk;

  String waveAppsFlyerUid = '';
  String waveAppsFlyerData = '';

  void waveStart({VoidCallback? waveOnUpdate}) {
    final AppsFlyerOptions waveOpts = AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6756072063',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    waveOptions = waveOpts;
    waveSdk = AppsflyerSdk(waveOpts);

    waveSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    waveSdk?.startSDK(
      onSuccess: () =>
          WaveTripVault().waveLogger.waveLogInfo('WheelSpy started'),
      onError: (waveCode, waveMsg) => WaveTripVault()
          .waveLogger
          .waveLogError('WheelSpy error $waveCode: $waveMsg'),
    );

    waveSdk?.onInstallConversionData((waveValue) {
      waveAppsFlyerData = waveValue.toString();
      waveOnUpdate?.call();
    });

    waveSdk?.getAppsFlyerUID().then((waveValue) {
      waveAppsFlyerUid = waveValue.toString();
      waveOnUpdate?.call();
    });
  }
}

// ============================================================================
// Мост для FCM токена: WaveFcmBridge
// ============================================================================

class WaveFcmBridge {
  final WaveTripLogger waveLog = const WaveTripLogger();
  String? waveToken;
  final List<void Function(String)> waveWaiters =
  <void Function(String)>[];

  String? get waveCurrentToken => waveToken;

  WaveFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall waveCall) async {
      if (waveCall.method == 'setToken') {
        final String waveTokenString = waveCall.arguments as String;
        if (waveTokenString.isNotEmpty) {
          waveSetToken(waveTokenString);
        }
      }
    });

    waveRestoreToken();
  }

  Future<void> waveRestoreToken() async {
    try {
      final SharedPreferences wavePrefs =
      await SharedPreferences.getInstance();
      final String? waveCached =
      wavePrefs.getString(metrCachedFcmKey);
      if (waveCached != null && waveCached.isNotEmpty) {
        waveSetToken(waveCached, waveNotify: false);
      }
    } catch (_) {}
  }

  Future<void> wavePersistToken(String waveNewToken) async {
    try {
      final SharedPreferences wavePrefs =
      await SharedPreferences.getInstance();
      await wavePrefs.setString(metrCachedFcmKey, waveNewToken);
    } catch (_) {}
  }

  void waveSetToken(
      String waveNewToken, {
        bool waveNotify = true,
      }) {
    waveToken = waveNewToken;
    wavePersistToken(waveNewToken);
    if (waveNotify) {
      for (final void Function(String) waveCallback
      in List<void Function(String)>.from(waveWaiters)) {
        try {
          waveCallback(waveNewToken);
        } catch (waveErr) {
          waveLog.waveLogWarn('fcm waiter error: $waveErr');
        }
      }
      waveWaiters.clear();
    }
  }

  Future<void> waveWaitForToken(
      Function(String waveTokenValue) waveOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((waveToken ?? '').isNotEmpty) {
        waveOnToken(waveToken!);
        return;
      }

      waveWaiters.add(waveOnToken);
    } catch (waveErr) {
      waveLog.waveLogError('wheelWaitToken error: $waveErr');
    }
  }
}

// ============================================================================
// WaveLoader (новый лоадер в Wave/Metr стиле)
// ============================================================================

class WaveLoader extends StatefulWidget {
  const WaveLoader({Key? key}) : super(key: key);

  @override
  State<WaveLoader> createState() => _WaveLoaderState();
}

class _WaveLoaderState extends State<WaveLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController waveController;

  static const Color waveBackgroundColor = Color(0xFF05071B);
  static const Color waveMainColor = Color(0xFF4CAF50);
  static const Color waveLightColor = Color(0x804CAF50);
  static const Color waveLighterColor = Color(0x404CAF50);

  @override
  void initState() {
    super.initState();

    waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: waveBackgroundColor,
      child: AnimatedBuilder(
        animation: waveController,
        builder: (BuildContext context, Widget? child) {
          final double wavePhase = waveController.value * 2 * waveMath.pi;
          return CustomPaint(
            painter: WavePainter(
              wavePhase: wavePhase,
              waveMainColor: waveMainColor,
              waveLightColor: waveLightColor,
              waveLighterColor: waveLighterColor,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final double wavePhase;
  final Color waveMainColor;
  final Color waveLightColor;
  final Color waveLighterColor;

  WavePainter({
    required this.wavePhase,
    required this.waveMainColor,
    required this.waveLightColor,
    required this.waveLighterColor,
  });

  @override
  void paint(Canvas waveCanvas, Size waveSize) {
    final double waveWidth = waveSize.width;
    final double waveHeight = waveSize.height;
    final double waveMidY = waveHeight * 0.5;

    final Paint wavePaintMain = Paint()
      ..color = waveMainColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..isAntiAlias = true;

    final Paint wavePaintLight = Paint()
      ..color = waveLightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..isAntiAlias = true;

    final Paint wavePaintLighter = Paint()
      ..color = waveLighterColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..isAntiAlias = true;

    final Path wavePathMain = buildWavePath(
      waveWidth: waveWidth,
      waveMidY: waveMidY,
      waveAmplitude: waveHeight * 0.18,
      wavePhaseShift: wavePhase,
    );

    final Path wavePathLight = buildWavePath(
      waveWidth: waveWidth,
      waveMidY: waveMidY + waveHeight * 0.02,
      waveAmplitude: waveHeight * 0.16,
      wavePhaseShift: wavePhase + 0.25,
    );

    final Path wavePathLighter = buildWavePath(
      waveWidth: waveWidth,
      waveMidY: waveMidY - waveHeight * 0.02,
      waveAmplitude: waveHeight * 0.14,
      wavePhaseShift: wavePhase + 0.5,
    );

    waveCanvas.drawPath(wavePathLighter, wavePaintLighter);
    waveCanvas.drawPath(wavePathLight, wavePaintLight);
    waveCanvas.drawPath(wavePathMain, wavePaintMain);
  }

  Path buildWavePath({
    required double waveWidth,
    required double waveMidY,
    required double waveAmplitude,
    required double wavePhaseShift,
  }) {
    final Path wavePath = Path();
    const int waveSegments = 80;
    final double waveDx = waveWidth / waveSegments;

    for (int i = 0; i <= waveSegments; i++) {
      final double waveX = i * waveDx;
      final double waveOmega = 2 * waveMath.pi / waveWidth * 1.2;
      final double waveY = waveMidY +
          waveMath.sin(waveOmega * waveX + wavePhaseShift) *
              waveAmplitude *
              0.6 +
          waveMath.sin(waveOmega * waveX * 0.5 + wavePhaseShift * 1.5) *
              waveAmplitude *
              0.4;

      if (i == 0) {
        wavePath.moveTo(waveX, waveY);
      } else {
        wavePath.lineTo(waveX, waveY);
      }
    }

    return wavePath;
  }

  @override
  bool shouldRepaint(covariant WavePainter waveOldDelegate) =>
      waveOldDelegate.wavePhase != wavePhase ||
          waveOldDelegate.waveMainColor != waveMainColor ||
          waveOldDelegate.waveLightColor != waveLightColor ||
          waveOldDelegate.waveLighterColor != waveLighterColor;
}

// ============================================================================
// Статистика (waveFinalUrl / wavePostStat)
// ============================================================================

Future<String> waveFinalUrl(
    String waveStartUrl, {
      int waveMaxHops = 10,
    }) async {
  final HttpClient waveClient = HttpClient();

  try {
    Uri waveCurrentUri = Uri.parse(waveStartUrl);

    for (int waveI = 0; waveI < waveMaxHops; waveI++) {
      final HttpClientRequest waveRequest =
      await waveClient.getUrl(waveCurrentUri);
      waveRequest.followRedirects = false;
      final HttpClientResponse waveResponse = await waveRequest.close();

      if (waveResponse.isRedirect) {
        final String? waveLoc =
        waveResponse.headers.value(HttpHeaders.locationHeader);
        if (waveLoc == null || waveLoc.isEmpty) break;

        final Uri waveNextUri = Uri.parse(waveLoc);
        waveCurrentUri = waveNextUri.hasScheme
            ? waveNextUri
            : waveCurrentUri.resolveUri(waveNextUri);
        continue;
      }

      return waveCurrentUri.toString();
    }

    return waveCurrentUri.toString();
  } catch (waveError) {
    debugPrint('wheelFinalUrl error: $waveError');
    return waveStartUrl;
  } finally {
    waveClient.close(force: true);
  }
}

Future<void> wavePostStat({
  required String waveEvent,
  required int waveTimeStart,
  required String waveUrl,
  required int waveTimeFinish,
  required String waveAppSid,
  int? waveFirstPageTs,
}) async {
  try {
    final String waveResolvedUrl = await waveFinalUrl(waveUrl);
    final Map<String, dynamic> wavePayload = <String, dynamic>{
      'event': waveEvent,
      'timestart': waveTimeStart,
      'timefinsh': waveTimeFinish,
      'url': waveResolvedUrl,
      'appleID': '6755681349',
      'open_count': '$waveAppSid/$waveTimeStart',
    };

    debugPrint('wheelStat $wavePayload');

    final http.Response waveResp = await http.post(
      Uri.parse('$metrStatEndpoint/$waveAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(wavePayload),
    );

    debugPrint('wheelStat resp=${waveResp.statusCode} body=${waveResp.body}');
  } catch (waveError) {
    debugPrint('wheelPostStat error: $waveError');
  }
}

// ============================================================================
// WebView-экран: WaveTripTableView
// ============================================================================

class WaveTripTableView extends StatefulWidget with WidgetsBindingObserver {
  String waveStartingUrl;
  WaveTripTableView(this.waveStartingUrl, {super.key});

  @override
  State<WaveTripTableView> createState() =>
      _WaveTripTableViewState(waveStartingUrl);
}

class _WaveTripTableViewState extends State<WaveTripTableView>
    with WidgetsBindingObserver {
  _WaveTripTableViewState(this.waveCurrentUrl);

  final WaveTripVault waveVault = WaveTripVault();

  late InAppWebViewController waveWebViewController;
  String? wavePushToken;
  final WaveDeviceProfile waveDeviceProfile = WaveDeviceProfile();
  final WaveTripSpy waveSpy = WaveTripSpy();

  bool waveOverlayBusy = false;
  String waveCurrentUrl;
  DateTime? waveLastPausedAt;

  bool waveLoadedOnceSent = false;
  int? waveFirstPageTimestamp;
  int waveStartLoadTimestamp = 0;

  final Set<String> waveExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  final Set<String> waveExternalSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(waveFcmBackgroundHandler);

    waveFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    waveInitPushAndGetToken();
    waveDeviceProfile.waveInitialize();
    waveWireForegroundPushHandlers();
    waveBindPlatformNotificationTap();
    waveSpy.waveStart(waveOnUpdate: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState waveState) {
    if (waveState == AppLifecycleState.paused) {
      waveLastPausedAt = DateTime.now();
    }
    if (waveState == AppLifecycleState.resumed) {
      if (Platform.isIOS && waveLastPausedAt != null) {
        final DateTime waveNow = DateTime.now();
        final Duration waveDrift = waveNow.difference(waveLastPausedAt!);
        if (waveDrift > const Duration(minutes: 25)) {
          waveForceReloadToLobby();
        }
      }
      waveLastPausedAt = null;
    }
  }

  void waveForceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance
        .addPostFrameCallback((Duration waveDuration) {
      if (!mounted) return;
      // Здесь можно вернуть в лобби (MafiaHarbor / CaptainHarbor / BillHarbor),
      // если нужно.
    });
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------

  void waveWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage waveMsg) {
      if (waveMsg.data['uri'] != null) {
        waveNavigateTo(waveMsg.data['uri'].toString());
      } else {
        waveReturnToCurrentUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage waveMsg) {
      if (waveMsg.data['uri'] != null) {
        waveNavigateTo(waveMsg.data['uri'].toString());
      } else {
        waveReturnToCurrentUrl();
      }
    });
  }

  void waveNavigateTo(String waveNewUrl) async {
    await waveWebViewController.loadUrl(
      urlRequest: URLRequest(url: WebUri(waveNewUrl)),
    );
  }

  void waveReturnToCurrentUrl() async {
    Future<void>.delayed(const Duration(seconds: 3), () {
      waveWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(waveCurrentUrl)),
      );
    });
  }

  Future<void> waveInitPushAndGetToken() async {
    final FirebaseMessaging waveFm = FirebaseMessaging.instance;
    await waveFm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    wavePushToken = await waveFm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала: тап по уведомлению из native
  // --------------------------------------------------------------------------

  void waveBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall waveCall) async {
      if (waveCall.method == "onNotificationTap") {
        final Map<String, dynamic> wavePayload =
        Map<String, dynamic>.from(waveCall.arguments);
        debugPrint("URI from platform tap: ${wavePayload['uri']}");
        final String? waveUriString = wavePayload["uri"]?.toString();
        if (waveUriString != null && !waveUriString.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext waveContext) =>
                  WaveTripTableView(waveUriString),
            ),
                (Route<dynamic> waveRoute) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    waveBindPlatformNotificationTap();

    final bool waveIsDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: waveIsDark ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                disableDefaultErrorPage: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri(waveCurrentUrl),
              ),
              onWebViewCreated:
                  (InAppWebViewController waveController) {
                waveWebViewController = waveController;

                waveWebViewController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (List<dynamic> waveArgs) {
                    waveVault.waveLogger.waveLogInfo("JS Args: $waveArgs");
                    try {
                      return waveArgs.reduce(
                              (dynamic waveV, dynamic waveE) => waveV + waveE);
                    } catch (_) {
                      return waveArgs.toString();
                    }
                  },
                );
              },
              onLoadStart: (
                  InAppWebViewController waveController,
                  Uri? waveUri,
                  ) async {
                waveStartLoadTimestamp =
                    DateTime.now().millisecondsSinceEpoch;

                if (waveUri != null) {
                  if (WaveTripKit.waveLooksLikeBareMail(waveUri)) {
                    try {
                      await waveController.stopLoading();
                    } catch (_) {}
                    final Uri waveMailto =
                    WaveTripKit.waveToMailto(waveUri);
                    await WaveTripLinker.waveOpen(
                      WaveTripKit.waveGmailize(waveMailto),
                    );
                    return;
                  }

                  final String waveScheme =
                  waveUri.scheme.toLowerCase();
                  if (waveScheme != 'http' && waveScheme != 'https') {
                    try {
                      await waveController.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (
                  InAppWebViewController waveController,
                  Uri? waveUri,
                  ) async {
                await waveController.evaluateJavascript(
                  source: "console.log('Hello from Roulette JS!');",
                );

                setState(() {
                  waveCurrentUrl = waveUri?.toString() ?? waveCurrentUrl;
                });

                Future<void>.delayed(const Duration(seconds: 20), () {
                  waveSendLoadedOnce();
                });
              },
              shouldOverrideUrlLoading: (
                  InAppWebViewController waveController,
                  NavigationAction waveNav,
                  ) async {
                final Uri? waveUri = waveNav.request.url;
                if (waveUri == null) {
                  return NavigationActionPolicy.ALLOW;
                }

                if (WaveTripKit.waveLooksLikeBareMail(waveUri)) {
                  final Uri waveMailto =
                  WaveTripKit.waveToMailto(waveUri);
                  await WaveTripLinker.waveOpen(
                    WaveTripKit.waveGmailize(waveMailto),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final String waveScheme =
                waveUri.scheme.toLowerCase();

                if (waveScheme == 'mailto') {
                  await WaveTripLinker.waveOpen(
                    WaveTripKit.waveGmailize(waveUri),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                if (waveScheme == 'tel') {
                  await launchUrl(
                    waveUri,
                    mode: LaunchMode.externalApplication,
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final String waveHost =
                waveUri.host.toLowerCase();
                final bool waveIsSocial =
                    waveHost.endsWith('facebook.com') ||
                        waveHost.endsWith('instagram.com') ||
                        waveHost.endsWith('twitter.com') ||
                        waveHost.endsWith('x.com');

                if (waveIsSocial) {
                  await WaveTripLinker.waveOpen(waveUri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (waveIsExternalDestination(waveUri)) {
                  final Uri waveMapped =
                  waveMapExternalToHttp(waveUri);
                  await WaveTripLinker.waveOpen(waveMapped);
                  return NavigationActionPolicy.CANCEL;
                }

                if (waveScheme != 'http' && waveScheme != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (
                  InAppWebViewController waveController,
                  CreateWindowAction waveReq,
                  ) async {
                final Uri? waveUrl = waveReq.request.url;
                if (waveUrl == null) return false;

                if (WaveTripKit.waveLooksLikeBareMail(waveUrl)) {
                  final Uri waveMail =
                  WaveTripKit.waveToMailto(waveUrl);
                  await WaveTripLinker.waveOpen(
                    WaveTripKit.waveGmailize(waveMail),
                  );
                  return false;
                }

                final String waveScheme =
                waveUrl.scheme.toLowerCase();

                if (waveScheme == 'mailto') {
                  await WaveTripLinker.waveOpen(
                    WaveTripKit.waveGmailize(waveUrl),
                  );
                  return false;
                }

                if (waveScheme == 'tel') {
                  await launchUrl(
                    waveUrl,
                    mode: LaunchMode.externalApplication,
                  );
                  return false;
                }

                final String waveHost =
                waveUrl.host.toLowerCase();
                final bool waveIsSocial =
                    waveHost.endsWith('facebook.com') ||
                        waveHost.endsWith('instagram.com') ||
                        waveHost.endsWith('twitter.com') ||
                        waveHost.endsWith('x.com');

                if (waveIsSocial) {
                  await WaveTripLinker.waveOpen(waveUrl);
                  return false;
                }

                if (waveIsExternalDestination(waveUrl)) {
                  final Uri waveMapped =
                  waveMapExternalToHttp(waveUrl);
                  await WaveTripLinker.waveOpen(waveMapped);
                  return false;
                }

                if (waveScheme == 'http' || waveScheme == 'https') {
                  waveController.loadUrl(
                    urlRequest:
                    URLRequest(url: WebUri(waveUrl.toString())),
                  );
                }

                return false;
              },
            ),
            if (waveOverlayBusy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: WaveLoader(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Внешние “столы” (протоколы/мессенджеры/соцсети)
  // ========================================================================

  bool waveIsExternalDestination(Uri waveUri) {
    final String waveScheme = waveUri.scheme.toLowerCase();
    if (waveExternalSchemes.contains(waveScheme)) {
      return true;
    }

    if (waveScheme == 'http' || waveScheme == 'https') {
      final String waveHost = waveUri.host.toLowerCase();
      if (waveExternalHosts.contains(waveHost)) {
        return true;
      }
      if (waveHost.endsWith('t.me')) return true;
      if (waveHost.endsWith('wa.me')) return true;
      if (waveHost.endsWith('m.me')) return true;
      if (waveHost.endsWith('signal.me')) return true;
      if (waveHost.endsWith('facebook.com')) return true;
      if (waveHost.endsWith('instagram.com')) return true;
      if (waveHost.endsWith('twitter.com')) return true;
      if (waveHost.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri waveMapExternalToHttp(Uri waveUri) {
    final String waveScheme = waveUri.scheme.toLowerCase();

    if (waveScheme == 'tg' || waveScheme == 'telegram') {
      final Map<String, String> waveQp = waveUri.queryParameters;
      final String? waveDomain = waveQp['domain'];
      if (waveDomain != null && waveDomain.isNotEmpty) {
        return Uri.https('t.me', '/$waveDomain', <String, String>{
          if (waveQp['start'] != null) 'start': waveQp['start']!,
        });
      }
      final String wavePath =
      waveUri.path.isNotEmpty ? waveUri.path : '';
      return Uri.https(
        't.me',
        '/$wavePath',
        waveUri.queryParameters.isEmpty ? null : waveUri.queryParameters,
      );
    }

    if (waveScheme == 'whatsapp') {
      final Map<String, String> waveQp = waveUri.queryParameters;
      final String? wavePhone = waveQp['phone'];
      final String? waveText = waveQp['text'];
      if (wavePhone != null && wavePhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${WaveTripKit.waveDigitsOnly(wavePhone)}',
          <String, String>{
            if (waveText != null && waveText.isNotEmpty) 'text': waveText,
          },
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (waveText != null && waveText.isNotEmpty) 'text': waveText,
        },
      );
    }

    if (waveScheme == 'bnl') {
      final String waveNewPath =
      waveUri.path.isNotEmpty ? waveUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$waveNewPath',
        waveUri.queryParameters.isEmpty ? null : waveUri.queryParameters,
      );
    }

    return waveUri;
  }

  Future<void> waveSendLoadedOnce() async {
    if (waveLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final int waveNow = DateTime.now().millisecondsSinceEpoch;

    await wavePostStat(
      waveEvent: 'Loaded',
      waveTimeStart: waveStartLoadTimestamp,
      waveTimeFinish: waveNow,
      waveUrl: waveCurrentUrl,
      waveAppSid: waveSpy.waveAppsFlyerUid,
      waveFirstPageTs: waveFirstPageTimestamp,
    );

    waveLoadedOnceSent = true;
  }
}