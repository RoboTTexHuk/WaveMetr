import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;
import 'dart:math' as math;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as appsflyer_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
    MethodChannel,
    SystemChrome,
    SystemUiOverlayStyle,
    MethodCall;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tzData;
import 'package:timezone/timezone.dart' as tzZone;
import 'package:wavemetr/pushMetr.dart';

import 'appWaveMetr.dart';

// ============================================================================
// Заглушки для других экранов
// ============================================================================





// ============================================================================
// Константы
// ============================================================================

const String metrLoadedOnceKey = 'loaded_once';
const String metrStatEndpoint = 'https://api.lwave.live/stat';
const String metrCachedFcmKey = 'cached_fcm';
const String metrCachedDeepKey = 'cached_deep_push_uri';

// ============================================================================
// НОВЫЙ LOADER — волна
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
          final double wavePhase = waveController.value * 2 * math.pi;
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
  void paint(Canvas canvas, Size size) {
    final double waveWidth = size.width;
    final double waveHeight = size.height;
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

    canvas.drawPath(wavePathLighter, wavePaintLighter);
    canvas.drawPath(wavePathLight, wavePaintLight);
    canvas.drawPath(wavePathMain, wavePaintMain);
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
      final double waveOmega = 2 * math.pi / waveWidth * 1.2;
      final double waveY = waveMidY +
          math.sin(waveOmega * waveX + wavePhaseShift) * waveAmplitude * 0.6 +
          math.sin(waveOmega * waveX * 0.5 + wavePhaseShift * 1.5) *
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
  bool shouldRepaint(covariant WavePainter oldDelegate) =>
      oldDelegate.wavePhase != wavePhase ||
          oldDelegate.waveMainColor != waveMainColor ||
          oldDelegate.waveLightColor != waveLightColor ||
          oldDelegate.waveLighterColor != waveLighterColor;
}

// ============================================================================
// Лёгкие сервисы
// ============================================================================

class WaveLoggerService {
  static final WaveLoggerService waveSharedInstance =
  WaveLoggerService._waveInternalConstructor();

  WaveLoggerService._waveInternalConstructor();

  factory WaveLoggerService() => waveSharedInstance;

  final Connectivity waveConnectivity = Connectivity();

  void waveLogInfo(Object waveMessage) => debugPrint('[I] $waveMessage');
  void waveLogWarn(Object waveMessage) => debugPrint('[W] $waveMessage');
  void waveLogError(Object waveMessage) => debugPrint('[E] $waveMessage');
}

class WaveNetworkService {
  final WaveLoggerService waveLogger = WaveLoggerService();

  Future<bool> waveIsOnline() async {
    final List<ConnectivityResult> waveResults =
    await waveLogger.waveConnectivity.checkConnectivity();
    return waveResults.isNotEmpty &&
        !waveResults.contains(ConnectivityResult.none);
  }

  Future<void> wavePostJson(
      String waveUrl,
      Map<String, dynamic> waveData,
      ) async {
    try {
      await http.post(
        Uri.parse(waveUrl),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(waveData),
      );
    } catch (waveError) {
      waveLogger.waveLogError('postJson error: $waveError');
    }
  }
}

// ============================================================================
// Профиль устройства
// ============================================================================

class WaveDeviceProfile {
  String? waveDeviceId;
  String? waveSessionId = 'retrocar-session';
  String? wavePlatformName;
  String? waveOsVersion;
  String? waveAppVersion;
  String? waveLanguageCode;
  String? waveTimezoneName;
  bool wavePushEnabled = false;

  Future<void> waveInitialize() async {
    final DeviceInfoPlugin waveDeviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo waveAndroidInfo =
      await waveDeviceInfoPlugin.androidInfo;
      waveDeviceId = waveAndroidInfo.id;
      wavePlatformName = 'android';
      waveOsVersion = waveAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo waveIosInfo = await waveDeviceInfoPlugin.iosInfo;
      waveDeviceId = waveIosInfo.identifierForVendor;
      wavePlatformName = 'ios';
      waveOsVersion = waveIosInfo.systemVersion;
    }

    final PackageInfo wavePackageInfo = await PackageInfo.fromPlatform();
    waveAppVersion = wavePackageInfo.version;
    waveLanguageCode = Platform.localeName.split('_').first;
    waveTimezoneName = tzZone.local.name;
    waveSessionId = 'tripriviera-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> waveToMap({String? waveFcmToken}) =>
      <String, dynamic>{
        'fcm_token': waveFcmToken ?? 'missing_token',
        'device_id': waveDeviceId ?? 'missing_id',
        'app_name': 'lwave',
        'instance_id': waveSessionId ?? 'missing_session',
        'platform': wavePlatformName ?? 'missing_system',
        'os_version': waveOsVersion ?? 'missing_build',
        'app_version': waveAppVersion ?? 'missing_app',
        'language': waveLanguageCode ?? 'en',
        'timezone': waveTimezoneName ?? 'UTC',
        'push_enabled': wavePushEnabled,
      };
}

// ============================================================================
// AppsFlyer Spy
// ============================================================================

class WaveAnalyticsSpyService {
  appsflyer_core.AppsFlyerOptions? waveAppsFlyerOptions;
  appsflyer_core.AppsflyerSdk? waveAppsFlyerSdk;

  String waveAppsFlyerUid = '';
  String waveAppsFlyerData = '';

  void waveStartTracking({VoidCallback? waveOnUpdate}) {
    final appsflyer_core.AppsFlyerOptions waveConfig =
    appsflyer_core.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6758451600',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    waveAppsFlyerOptions = waveConfig;
    waveAppsFlyerSdk = appsflyer_core.AppsflyerSdk(waveConfig);

    waveAppsFlyerSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    waveAppsFlyerSdk?.startSDK(
      onSuccess: () =>
          WaveLoggerService().waveLogInfo('RetroCarAnalyticsSpy started'),
      onError: (int waveCode, String waveMsg) => WaveLoggerService()
          .waveLogError('RetroCarAnalyticsSpy error $waveCode: $waveMsg'),
    );

    waveAppsFlyerSdk?.onInstallConversionData((dynamic waveValue) {
      waveAppsFlyerData = waveValue.toString();
      waveOnUpdate?.call();
    });

    waveAppsFlyerSdk?.getAppsFlyerUID().then((dynamic waveValue) {
      waveAppsFlyerUid = waveValue.toString();
      waveOnUpdate?.call();
    });
  }
}

// ============================================================================
// FCM фон
// ============================================================================

@pragma('vm:entry-point')
Future<void> waveFcmBackgroundHandler(RemoteMessage waveMessage) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  WaveLoggerService().waveLogInfo('bg-fcm: ${waveMessage.messageId}');
  WaveLoggerService().waveLogInfo('bg-data: ${waveMessage.data}');

  final dynamic waveLink = waveMessage.data['uri'];
  if (waveLink != null) {
    try {
      final SharedPreferences wavePrefs =
      await SharedPreferences.getInstance();
      await wavePrefs.setString(
        metrCachedDeepKey,
        waveLink.toString(),
      );
    } catch (waveError) {
      WaveLoggerService().waveLogError('bg-fcm save deep failed: $waveError');
    }
  }
}

// ============================================================================
// FCM Bridge
// ============================================================================

class WaveFcmBridge {
  final WaveLoggerService waveLogger = WaveLoggerService();
  String? waveToken;
  final List<void Function(String)> waveTokenWaiters =
  <void Function(String)>[];

  String? get waveFcmToken => waveToken;

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
      final String? waveCachedToken =
      wavePrefs.getString(metrCachedFcmKey);
      if (waveCachedToken != null && waveCachedToken.isNotEmpty) {
        waveSetToken(waveCachedToken, waveNotify: false);
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
      in List<void Function(String)>.from(waveTokenWaiters)) {
        try {
          waveCallback(waveNewToken);
        } catch (waveError) {
          waveLogger.waveLogWarn('fcm waiter error: $waveError');
        }
      }
      waveTokenWaiters.clear();
    }
  }

  Future<void> waveWaitForToken(
      Function(String waveToken) waveOnToken,
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

      waveTokenWaiters.add(waveOnToken);
    } catch (waveError) {
      waveLogger.waveLogError('waitToken error: $waveError');
    }
  }
}

// ============================================================================
// Splash / Hall
// ============================================================================

class WaveHall extends StatefulWidget {
  const WaveHall({Key? key}) : super(key: key);

  @override
  State<WaveHall> createState() => _WaveHallState();
}

class _WaveHallState extends State<WaveHall> {
  final WaveFcmBridge waveFcmBridge = WaveFcmBridge();
  bool waveNavigatedOnce = false;
  Timer? waveFallbackTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    waveFcmBridge.waveWaitForToken((String waveToken) {
      waveGoToHarbor(waveToken);
    });

    waveFallbackTimer = Timer(
      const Duration(seconds: 8),
          () => waveGoToHarbor(''),
    );
  }

  void waveGoToHarbor(String waveSignal) {
    if (waveNavigatedOnce) return;
    waveNavigatedOnce = true;
    waveFallbackTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext context) =>
            WaveHarbor(waveSignal: waveSignal),
      ),
    );
  }

  @override
  void dispose() {
    waveFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: WaveLoader(),
      ),
    );
  }
}

// ============================================================================
// ViewModel + Courier
// ============================================================================

class WaveBosunViewModel {
  final WaveDeviceProfile waveDeviceProfile;
  final WaveAnalyticsSpyService waveAnalyticsSpy;

  WaveBosunViewModel({
    required this.waveDeviceProfile,
    required this.waveAnalyticsSpy,
  });

  Map<String, dynamic> waveDeviceMap(String? waveFcmToken) =>
      waveDeviceProfile.waveToMap(waveFcmToken: waveFcmToken);

  Map<String, dynamic> waveAppsFlyerPayload(
      String? waveToken, {
        String? waveDeepLink,
      }) =>
      <String, dynamic>{
        'content': <String, dynamic>{
          'af_data': waveAnalyticsSpy.waveAppsFlyerData,
          'af_id': waveAnalyticsSpy.waveAppsFlyerUid,
          'fb_app_name': 'lwave',
          'app_name': 'lwave',
          'deep': waveDeepLink,
          'bundle_identifier': 'com.metrwave.metrvae.wavemetr',
          'app_version': '1.0.0',
          'apple_id': '6758451600',
          'fcm_token': waveToken ?? 'no_token',
          'device_id': waveDeviceProfile.waveDeviceId ?? 'no_device',
          'instance_id': waveDeviceProfile.waveSessionId ?? 'no_instance',
          'platform': waveDeviceProfile.wavePlatformName ?? 'no_type',
          'os_version': waveDeviceProfile.waveOsVersion ?? 'no_os',
          'app_version': waveDeviceProfile.waveAppVersion ?? 'no_app',
          'language': waveDeviceProfile.waveLanguageCode ?? 'en',
          'timezone': waveDeviceProfile.waveTimezoneName ?? 'UTC',
          'push_enabled': waveDeviceProfile.wavePushEnabled,
          'useruid': waveAnalyticsSpy.waveAppsFlyerUid,
        },
      };
}

class WaveCourierService {
  final WaveBosunViewModel waveBosun;
  final InAppWebViewController? Function() waveGetWebViewController;

  WaveCourierService({
    required this.waveBosun,
    required this.waveGetWebViewController,
  });

  Future<void> wavePutDeviceToLocalStorage(String? waveToken) async {
    final InAppWebViewController? waveController = waveGetWebViewController();
    if (waveController == null) return;

    final Map<String, dynamic> waveMap =
    waveBosun.waveDeviceMap(waveToken);
    await waveController.evaluateJavascript(
      source:
      "localStorage.setItem('app_data', JSON.stringify(${jsonEncode(waveMap)}));",
    );
  }

  Future<void> waveSendRawToPage(
      String? waveToken, {
        String? waveDeepLink,
      }) async {
    final InAppWebViewController? waveController =
    waveGetWebViewController();
    if (waveController == null) return;

    final Map<String, dynamic> wavePayload =
    waveBosun.waveAppsFlyerPayload(
      waveToken,
      waveDeepLink: waveDeepLink,
    );
    final String waveJsonString = jsonEncode(wavePayload);

    WaveLoggerService().waveLogInfo('SendRawData: $waveJsonString');

    await waveController.evaluateJavascript(
      source: 'sendRawData(${jsonEncode(waveJsonString)});',
    );
  }
}

// ============================================================================
// Переходы/статистика
// ============================================================================

Future<String> waveResolveFinalUrl(
    String waveStartUrl, {
      int waveMaxHops = 10,
    }) async {
  final HttpClient waveHttpClient = HttpClient();

  try {
    Uri waveCurrentUri = Uri.parse(waveStartUrl);

    for (int i = 0; i < waveMaxHops; i++) {
      final HttpClientRequest waveRequest =
      await waveHttpClient.getUrl(waveCurrentUri);
      waveRequest.followRedirects = false;
      final HttpClientResponse waveResponse = await waveRequest.close();

      if (waveResponse.isRedirect) {
        final String? waveLocationHeader =
        waveResponse.headers.value(HttpHeaders.locationHeader);
        if (waveLocationHeader == null || waveLocationHeader.isEmpty) {
          break;
        }

        final Uri waveNextUri = Uri.parse(waveLocationHeader);
        waveCurrentUri = waveNextUri.hasScheme
            ? waveNextUri
            : waveCurrentUri.resolveUri(waveNextUri);
        continue;
      }

      return waveCurrentUri.toString();
    }

    return waveCurrentUri.toString();
  } catch (waveError) {
    debugPrint('goldenLuxuryResolveFinalUrl error: $waveError');
    return waveStartUrl;
  } finally {
    waveHttpClient.close(force: true);
  }
}

Future<void> wavePostStat({
  required String waveEvent,
  required int waveTimeStart,
  required String waveUrl,
  required int waveTimeFinish,
  required String waveAppSid,
  int? waveFirstPageLoadTs,
}) async {
  try {
    final String waveResolvedUrl = await waveResolveFinalUrl(waveUrl);

    final Map<String, dynamic> wavePayload = <String, dynamic>{
      'event': waveEvent,
      'timestart': waveTimeStart,
      'timefinsh': waveTimeFinish,
      'url': waveResolvedUrl,
      'appleID': '6758451600',
      'open_count': '$waveAppSid/$waveTimeStart',
    };

    debugPrint('goldenLuxuryStat $wavePayload');

    final http.Response waveResponse = await http.post(
      Uri.parse('$metrStatEndpoint/$waveAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(wavePayload),
    );

    debugPrint(
        'goldenLuxuryStat resp=${waveResponse.statusCode} body=${waveResponse.body}');
  } catch (waveError) {
    debugPrint('goldenLuxuryPostStat error: $waveError');
  }
}

// ============================================================================
// BLoC: Harbor
// ============================================================================

abstract class WaveHarborEvent extends Equatable {
  const WaveHarborEvent();

  @override
  List<Object?> get props => [];
}

class WaveHarborInit extends WaveHarborEvent {
  final String? waveSignal;
  const WaveHarborInit(this.waveSignal);

  @override
  List<Object?> get props => [waveSignal];
}

class WaveHarborUrlChanged extends WaveHarborEvent {
  final String waveUrl;
  const WaveHarborUrlChanged(this.waveUrl);

  @override
  List<Object?> get props => [waveUrl];
}

class WaveHarborSetVeilVisible extends WaveHarborEvent {
  final bool waveVisible;
  const WaveHarborSetVeilVisible(this.waveVisible);

  @override
  List<Object?> get props => [waveVisible];
}

class WaveHarborSetCoverVisible extends WaveHarborEvent {
  final bool waveVisible;
  const WaveHarborSetCoverVisible(this.waveVisible);

  @override
  List<Object?> get props => [waveVisible];
}

class WaveHarborSetWarmProgress extends WaveHarborEvent {
  final double waveProgress;
  const WaveHarborSetWarmProgress(this.waveProgress);

  @override
  List<Object?> get props => [waveProgress];
}

class WaveHarborState extends Equatable {
  final bool waveVeilVisible;
  final bool waveCoverVisible;
  final double waveWarmProgress;
  final String waveCurrentUrl;

  const WaveHarborState({
    required this.waveVeilVisible,
    required this.waveCoverVisible,
    required this.waveWarmProgress,
    required this.waveCurrentUrl,
  });

  WaveHarborState waveCopyWith({
    bool? waveVeilVisible,
    bool? waveCoverVisible,
    double? waveWarmProgress,
    String? waveCurrentUrl,
  }) {
    return WaveHarborState(
      waveVeilVisible: waveVeilVisible ?? this.waveVeilVisible,
      waveCoverVisible: waveCoverVisible ?? this.waveCoverVisible,
      waveWarmProgress: waveWarmProgress ?? this.waveWarmProgress,
      waveCurrentUrl: waveCurrentUrl ?? this.waveCurrentUrl,
    );
  }

  @override
  List<Object?> get props =>
      [waveVeilVisible, waveCoverVisible, waveWarmProgress, waveCurrentUrl];
}

class WaveHarborBloc extends Bloc<WaveHarborEvent, WaveHarborState> {
  WaveHarborBloc()
      : super(const WaveHarborState(
    waveVeilVisible: false,
    waveCoverVisible: true,
    waveWarmProgress: 0.0,
    waveCurrentUrl: '',
  )) {
    on<WaveHarborInit>(waveOnInit);
    on<WaveHarborUrlChanged>(waveOnUrlChanged);
    on<WaveHarborSetVeilVisible>(waveOnVeilVisible);
    on<WaveHarborSetCoverVisible>(waveOnCoverVisible);
    on<WaveHarborSetWarmProgress>(waveOnWarmProgress);
  }

  void waveOnInit(WaveHarborInit waveEvent, Emitter<WaveHarborState> emit) {}

  void waveOnUrlChanged(
      WaveHarborUrlChanged waveEvent, Emitter<WaveHarborState> emit) {
    emit(state.waveCopyWith(waveCurrentUrl: waveEvent.waveUrl));
  }

  void waveOnVeilVisible(
      WaveHarborSetVeilVisible waveEvent, Emitter<WaveHarborState> emit) {
    emit(state.waveCopyWith(waveVeilVisible: waveEvent.waveVisible));
  }

  void waveOnCoverVisible(
      WaveHarborSetCoverVisible waveEvent, Emitter<WaveHarborState> emit) {
    emit(state.waveCopyWith(waveCoverVisible: waveEvent.waveVisible));
  }

  void waveOnWarmProgress(
      WaveHarborSetWarmProgress waveEvent, Emitter<WaveHarborState> emit) {
    emit(state.waveCopyWith(waveWarmProgress: waveEvent.waveProgress));
  }
}

// ============================================================================
// Главный WebView — Harbor
// ============================================================================

class WaveHarbor extends StatefulWidget {
  final String? waveSignal;

  const WaveHarbor({super.key, required this.waveSignal});

  @override
  State<WaveHarbor> createState() => _WaveHarborState();
}

class _WaveHarborState extends State<WaveHarbor> with WidgetsBindingObserver {
  InAppWebViewController? waveWebViewController;
  final String waveHomeUrl = 'https://api.lwave.live/';

  int waveWebViewKeyCounter = 0;
  DateTime? waveSleepAt;
  late Timer waveWarmTimer;
  final int waveWarmSeconds = 6;

  bool waveLoadedOnceSent = false;
  int? waveFirstPageTimestamp;

  WaveCourierService? waveCourier;
  WaveBosunViewModel? waveBosunViewModel;

  int waveStartLoadTimestamp = 0;

  final WaveDeviceProfile waveDeviceProfile = WaveDeviceProfile();
  final WaveAnalyticsSpyService waveAnalyticsSpyService =
  WaveAnalyticsSpyService();
  bool waveUseSafeArea = false;

  final Set<String> waveSpecialSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> waveExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
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

  String? waveDeepLinkFromPush;

  WaveHarborBloc get waveHarborBloc => context.read<WaveHarborBloc>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    waveFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        waveHarborBloc.add(const WaveHarborSetCoverVisible(false));
      }
    });

    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      waveHarborBloc.add(const WaveHarborSetVeilVisible(true));
    });

    waveBootHarbor();
  }

  Future<void> waveLoadLoadedFlag() async {
    final SharedPreferences wavePrefs =
    await SharedPreferences.getInstance();
    waveLoadedOnceSent = wavePrefs.getBool(metrLoadedOnceKey) ?? false;
  }

  Future<void> waveSaveLoadedFlag() async {
    final SharedPreferences wavePrefs =
    await SharedPreferences.getInstance();
    await wavePrefs.setBool(metrLoadedOnceKey, true);
    waveLoadedOnceSent = true;
  }

  Future<void> waveLoadCachedDeep() async {
    try {
      final SharedPreferences wavePrefs =
      await SharedPreferences.getInstance();
      final String? waveCached =
      wavePrefs.getString(metrCachedDeepKey);
      if ((waveCached ?? '').isNotEmpty) {
        waveDeepLinkFromPush = waveCached;
      }
    } catch (_) {}
  }

  Future<void> waveSaveCachedDeep(String waveUri) async {
    try {
      final SharedPreferences wavePrefs =
      await SharedPreferences.getInstance();
      await wavePrefs.setString(metrCachedDeepKey, waveUri);
    } catch (_) {}
  }

  Future<void> waveSendLoadedOnce({
    required String waveUrl,
    required int waveTimestart,
  }) async {
    if (waveLoadedOnceSent) {
      debugPrint('Loaded already sent, skip');
      return;
    }

    final int waveNow = DateTime.now().millisecondsSinceEpoch;

    await wavePostStat(
      waveEvent: 'Loaded',
      waveTimeStart: waveTimestart,
      waveTimeFinish: waveNow,
      waveUrl: waveUrl,
      waveAppSid: waveAnalyticsSpyService.waveAppsFlyerUid,
      waveFirstPageLoadTs: waveFirstPageTimestamp,
    );

    await waveSaveLoadedFlag();
  }

  void waveBootHarbor() {
    waveStartWarmProgress();
    waveWireFcmHandlers();
    waveAnalyticsSpyService.waveStartTracking(
      waveOnUpdate: () => setState(() {}),
    );
    waveBindNotificationTap();
    wavePrepareDeviceProfile();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await wavePushDeviceInfo();
      await wavePushAppsFlyerData();
    });
  }

  void waveWireFcmHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage waveMessage) async {
      final dynamic waveLink = waveMessage.data['uri'];
      if (waveLink != null) {
        final String waveUri = waveLink.toString();
        waveDeepLinkFromPush = waveUri;
        await waveSaveCachedDeep(waveUri);
        waveNavigateToUri(waveUri);
      } else {
        waveResetHomeAfterDelay();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage waveMessage) async {
      final dynamic waveLink = waveMessage.data['uri'];
      if (waveLink != null) {
        final String waveUri = waveLink.toString();
        waveDeepLinkFromPush = waveUri;
        await waveSaveCachedDeep(waveUri);
        waveNavigateToUri(waveUri);
      } else {
        waveResetHomeAfterDelay();
      }
    });
  }

  void waveBindNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall waveCall) async {
      if (waveCall.method == 'onNotificationTap') {
        final Map<String, dynamic> wavePayload =
        Map<String, dynamic>.from(waveCall.arguments);
        if (wavePayload['uri'] != null &&
            !wavePayload['uri'].toString().contains('Нет URI')) {
          final String waveUri = wavePayload['uri'].toString();
          waveDeepLinkFromPush = waveUri;
          await waveSaveCachedDeep(waveUri);

          if (!mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext context) =>
                  WaveTripTableView(waveUri),
            ),
                (Route<dynamic> route) => false,
          );
        }
      }
    });
  }

  Future<void> wavePrepareDeviceProfile() async {
    try {
      await waveDeviceProfile.waveInitialize();

      final FirebaseMessaging waveMessaging = FirebaseMessaging.instance;
      final NotificationSettings waveSettings =
      await waveMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      waveDeviceProfile.wavePushEnabled =
          waveSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
              waveSettings.authorizationStatus ==
                  AuthorizationStatus.provisional;

      await waveLoadLoadedFlag();
      await waveLoadCachedDeep();

      waveBosunViewModel = WaveBosunViewModel(
        waveDeviceProfile: waveDeviceProfile,
        waveAnalyticsSpy: waveAnalyticsSpyService,
      );

      waveCourier = WaveCourierService(
        waveBosun: waveBosunViewModel!,
        waveGetWebViewController: () => waveWebViewController,
      );
    } catch (waveError) {
      WaveLoggerService()
          .waveLogError('prepareDeviceProfile fail: $waveError');
    }
  }

  void waveNavigateToUri(String waveLink) async {
    try {
      await waveWebViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(waveLink)),
      );
    } catch (waveError) {
      WaveLoggerService().waveLogError('navigate error: $waveError');
    }
  }

  void waveResetHomeAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        waveWebViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(waveHomeUrl)),
        );
      } catch (_) {}
    });
  }

  Future<void> wavePushDeviceInfo() async {
    WaveLoggerService().waveLogInfo('TOKEN ship ${widget.waveSignal}');
    try {
      await waveCourier?.wavePutDeviceToLocalStorage(
        widget.waveSignal,
      );
    } catch (waveError) {
      WaveLoggerService().waveLogError('pushDeviceInfo error: $waveError');
    }
  }

  Future<void> wavePushAppsFlyerData() async {
    try {
      await waveCourier?.waveSendRawToPage(
        widget.waveSignal,
        waveDeepLink: waveDeepLinkFromPush,
      );
    } catch (waveError) {
      WaveLoggerService()
          .waveLogError('pushAppsFlyerData error: $waveError');
    }
  }

  void waveStartWarmProgress() {
    int waveTick = 0;
    waveHarborBloc.add(const WaveHarborSetWarmProgress(0.0));

    waveWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer waveTimer) {
          if (!mounted) return;

          waveTick++;
          final double waveProgress = waveTick / (waveWarmSeconds * 10);

          if (waveProgress >= 1.0) {
            waveHarborBloc.add(const WaveHarborSetWarmProgress(1.0));
            waveWarmTimer.cancel();
          } else {
            waveHarborBloc.add(WaveHarborSetWarmProgress(waveProgress));
          }
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState waveState) {
    if (waveState == AppLifecycleState.paused) {
      waveSleepAt = DateTime.now();
    }

    if (waveState == AppLifecycleState.resumed) {
      if (Platform.isIOS && waveSleepAt != null) {
        final DateTime waveNow = DateTime.now();
        final Duration waveDrift = waveNow.difference(waveSleepAt!);

        if (waveDrift > const Duration(minutes: 25)) {
          waveReboardHarbor();
        }
      }
      waveSleepAt = null;
    }
  }

  void waveReboardHarbor() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
              WaveHarbor(waveSignal: widget.waveSignal),
        ),
            (Route<dynamic> route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    waveWarmTimer.cancel();
    super.dispose();
  }

  bool waveIsBareEmail(Uri waveUri) {
    final String waveScheme = waveUri.scheme;
    if (waveScheme.isNotEmpty) return false;
    final String waveRaw = waveUri.toString();
    return waveRaw.contains('@') && !waveRaw.contains(' ');
  }

  Uri waveToMailto(Uri waveUri) {
    final String waveFull = waveUri.toString();
    final List<String> waveParts = waveFull.split('?');
    final String waveEmail = waveParts.first;
    final Map<String, String> waveQueryParams = waveParts.length > 1
        ? Uri.splitQueryString(waveParts[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: waveEmail,
      queryParameters:
      waveQueryParams.isEmpty ? null : waveQueryParams,
    );
  }

  bool waveIsPlatformLink(Uri waveUri) {
    final String waveScheme = waveUri.scheme.toLowerCase();
    if (waveSpecialSchemes.contains(waveScheme)) {
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

  String waveDigitsOnly(String waveSource) =>
      waveSource.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri waveHttpizePlatformUri(Uri waveUri) {
    final String waveScheme = waveUri.scheme.toLowerCase();

    if (waveScheme == 'tg' || waveScheme == 'telegram') {
      final Map<String, String> waveQp = waveUri.queryParameters;
      final String? waveDomain = waveQp['domain'];

      if (waveDomain != null && waveDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$waveDomain',
          <String, String>{
            if (waveQp['start'] != null) 'start': waveQp['start']!,
          },
        );
      }

      final String wavePath =
      waveUri.path.isNotEmpty ? waveUri.path : '';

      return Uri.https(
        't.me',
        '/$wavePath',
        waveUri.queryParameters.isEmpty ? null : waveUri.queryParameters,
      );
    }

    if ((waveScheme == 'http' || waveScheme == 'https') &&
        waveUri.host.toLowerCase().endsWith('t.me')) {
      return waveUri;
    }

    if (waveScheme == 'viber') {
      return waveUri;
    }

    if (waveScheme == 'whatsapp') {
      final Map<String, String> waveQp = waveUri.queryParameters;
      final String? wavePhone = waveQp['phone'];
      final String? waveText = waveQp['text'];

      if (wavePhone != null && wavePhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${waveDigitsOnly(wavePhone)}',
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

    if ((waveScheme == 'http' || waveScheme == 'https') &&
        (waveUri.host.toLowerCase().endsWith('wa.me') ||
            waveUri.host.toLowerCase().endsWith('whatsapp.com'))) {
      return waveUri;
    }

    if (waveScheme == 'skype') {
      return waveUri;
    }

    if (waveScheme == 'fb-messenger') {
      final String wavePath = waveUri.pathSegments.isNotEmpty
          ? waveUri.pathSegments.join('/')
          : '';
      final Map<String, String> waveQp = waveUri.queryParameters;

      final String waveId =
          waveQp['id'] ?? waveQp['user'] ?? wavePath;

      if (waveId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$waveId',
          waveUri.queryParameters.isEmpty ? null : waveUri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        waveUri.queryParameters.isEmpty ? null : waveUri.queryParameters,
      );
    }

    if (waveScheme == 'sgnl') {
      final Map<String, String> waveQp = waveUri.queryParameters;
      final String? wavePhone = waveQp['phone'];
      final String? waveUsername = waveQp['username'];

      if (wavePhone != null && wavePhone.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${waveDigitsOnly(wavePhone)}',
        );
      }

      if (waveUsername != null && waveUsername.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$waveUsername',
        );
      }

      final String wavePath =
      waveUri.pathSegments.join('/');
      if (wavePath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$wavePath',
          waveUri.queryParameters.isEmpty ? null : waveUri.queryParameters,
        );
      }

      return waveUri;
    }

    if (waveScheme == 'tel') {
      return Uri.parse('tel:${waveDigitsOnly(waveUri.path)}');
    }

    if (waveScheme == 'mailto') {
      return waveUri;
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

  Future<bool> waveOpenMailWeb(Uri waveMailto) async {
    final Uri waveGmailUri = waveGmailizeMailto(waveMailto);
    return waveOpenWeb(waveGmailUri);
  }

  Uri waveGmailizeMailto(Uri waveMailUri) {
    final Map<String, String> waveQueryParams =
        waveMailUri.queryParameters;

    final Map<String, String> waveParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (waveMailUri.path.isNotEmpty) 'to': waveMailUri.path,
      if ((waveQueryParams['subject'] ?? '').isNotEmpty)
        'su': waveQueryParams['subject']!,
      if ((waveQueryParams['body'] ?? '').isNotEmpty)
        'body': waveQueryParams['body']!,
      if ((waveQueryParams['cc'] ?? '').isNotEmpty)
        'cc': waveQueryParams['cc']!,
      if ((waveQueryParams['bcc'] ?? '').isNotEmpty)
        'bcc': waveQueryParams['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', waveParams);
  }

  Future<bool> waveOpenWeb(Uri waveUri) async {
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
      debugPrint('openInAppBrowser error: $waveError; url=$waveUri');
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

  Future<bool> waveOpenExternal(Uri waveUri) async {
    try {
      return await launchUrl(
        waveUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (waveError) {
      debugPrint('openExternal error: $waveError; url=$waveUri');
      return false;
    }
  }

  void waveHandleServerSavedata(String waveSavedata) {
    debugPrint('onServerResponse savedata: $waveSavedata');

    if (waveSavedata == 'false') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
          const WaveFishCalendarHelpLite(),
        ),
            (Route<dynamic> route) => false,
      );
    } else if (waveSavedata == 'true') {
      // остаёмся на вебе
    }
  }

  @override
  Widget build(BuildContext context) {
    waveBindNotificationTap();

    return BlocBuilder<WaveHarborBloc, WaveHarborState>(
      builder: (BuildContext context, WaveHarborState waveState) {
        Widget waveContent = Stack(
          children: <Widget>[
            if (waveState.waveCoverVisible)
              const WaveLoader()
            else
              Container(
                color: Colors.black,
                child: Stack(
                  children: <Widget>[
                    InAppWebView(
                      key: ValueKey<int>(waveWebViewKeyCounter),
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
                        transparentBackground: true,
                      ),
                      initialUrlRequest: URLRequest(
                        url: WebUri(waveHomeUrl),
                      ),
                      onWebViewCreated:
                          (InAppWebViewController waveController) {
                        waveWebViewController = waveController;

                        waveBosunViewModel ??= WaveBosunViewModel(
                          waveDeviceProfile: waveDeviceProfile,
                          waveAnalyticsSpy: waveAnalyticsSpyService,
                        );

                        waveCourier ??= WaveCourierService(
                          waveBosun: waveBosunViewModel!,
                          waveGetWebViewController: () =>
                          waveWebViewController,
                        );

                        waveController.addJavaScriptHandler(
                          handlerName: 'onServerResponse',
                          callback: (List<dynamic> waveArgs) {
                            debugPrint('onServerResponse raw args: $waveArgs');

                            if (waveArgs.isEmpty) return null;

                            try {
                              if (waveArgs[0] is Map) {
                                final dynamic waveRaw =
                                (waveArgs[0] as Map)['savedata'];

                                debugPrint("saveDATA $waveRaw");
                                waveHandleServerSavedata(
                                    waveRaw?.toString() ?? '');
                              } else if (waveArgs[0] is String) {
                                waveHandleServerSavedata(
                                    waveArgs[0] as String);
                              } else if (waveArgs[0] is bool) {
                                waveHandleServerSavedata(
                                    (waveArgs[0] as bool).toString());
                              }
                            } catch (waveError, waveSt) {
                              debugPrint(
                                  'onServerResponse error: $waveError\n$waveSt');
                            }

                            return null;
                          },
                        );
                      },
                      onLoadStart: (
                          InAppWebViewController waveController,
                          Uri? waveUri,
                          ) async {
                        setState(() {
                          waveStartLoadTimestamp =
                              DateTime.now().millisecondsSinceEpoch;
                        });

                        final Uri? waveViewUri = waveUri;
                        if (waveViewUri != null) {
                          if (waveIsBareEmail(waveViewUri)) {
                            try {
                              await waveController.stopLoading();
                            } catch (_) {}
                            final Uri waveMailto =
                            waveToMailto(waveViewUri);
                            await waveOpenMailWeb(waveMailto);
                            return;
                          }

                          final String waveScheme =
                          waveViewUri.scheme.toLowerCase();
                          if (waveScheme != 'http' &&
                              waveScheme != 'https') {
                            try {
                              await waveController.stopLoading();
                            } catch (_) {}
                          }
                        }
                      },
                      onLoadError: (
                          InAppWebViewController waveController,
                          Uri? waveUri,
                          int waveCode,
                          String waveMessage,
                          ) async {
                        final int waveNow =
                            DateTime.now().millisecondsSinceEpoch;
                        final String waveEvent =
                            'InAppWebViewError(code=$waveCode, message=$waveMessage)';

                        await wavePostStat(
                          waveEvent: waveEvent,
                          waveTimeStart: waveNow,
                          waveTimeFinish: waveNow,
                          waveUrl: waveUri?.toString() ?? '',
                          waveAppSid:
                          waveAnalyticsSpyService.waveAppsFlyerUid,
                          waveFirstPageLoadTs: waveFirstPageTimestamp,
                        );
                      },
                      onReceivedError: (
                          InAppWebViewController waveController,
                          WebResourceRequest waveRequest,
                          WebResourceError waveError,
                          ) async {
                        final int waveNow =
                            DateTime.now().millisecondsSinceEpoch;
                        final String waveDescription =
                        (waveError.description ?? '').toString();
                        final String waveEvent =
                            'WebResourceError(code=$waveError, message=$waveDescription)';

                        await wavePostStat(
                          waveEvent: waveEvent,
                          waveTimeStart: waveNow,
                          waveTimeFinish: waveNow,
                          waveUrl: waveRequest.url?.toString() ?? '',
                          waveAppSid:
                          waveAnalyticsSpyService.waveAppsFlyerUid,
                          waveFirstPageLoadTs: waveFirstPageTimestamp,
                        );
                      },
                      onLoadStop: (
                          InAppWebViewController waveController,
                          Uri? waveUri,
                          ) async {
                        await wavePushDeviceInfo();
                        await wavePushAppsFlyerData();

                        waveHarborBloc.add(
                            WaveHarborUrlChanged(waveUri.toString()));

                        Future<void>.delayed(
                          const Duration(seconds: 20),
                              () {
                            waveSendLoadedOnce(
                              waveUrl: waveUri.toString(),
                              waveTimestart: waveStartLoadTimestamp,
                            );
                          },
                        );
                      },
                      shouldOverrideUrlLoading: (
                          InAppWebViewController waveController,
                          NavigationAction waveAction,
                          ) async {
                        final Uri? waveUri = waveAction.request.url;
                        if (waveUri == null) {
                          return NavigationActionPolicy.ALLOW;
                        }

                        if (waveIsBareEmail(waveUri)) {
                          final Uri waveMailto =
                          waveToMailto(waveUri);
                          await waveOpenMailWeb(waveMailto);
                          return NavigationActionPolicy.CANCEL;
                        }

                        final String waveScheme =
                        waveUri.scheme.toLowerCase();

                        if (waveScheme == 'mailto') {
                          await waveOpenMailWeb(waveUri);
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
                          await waveOpenExternal(waveUri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (waveIsPlatformLink(waveUri)) {
                          final Uri waveWebUri =
                          waveHttpizePlatformUri(waveUri);
                          await waveOpenExternal(waveWebUri);
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (waveScheme != 'http' &&
                            waveScheme != 'https') {
                          return NavigationActionPolicy.CANCEL;
                        }

                        return NavigationActionPolicy.ALLOW;
                      },
                      onCreateWindow: (
                          InAppWebViewController waveController,
                          CreateWindowAction waveRequest,
                          ) async {
                        final Uri? waveUri = waveRequest.request.url;
                        if (waveUri == null) {
                          return false;
                        }

                        if (waveIsBareEmail(waveUri)) {
                          final Uri waveMailto =
                          waveToMailto(waveUri);
                          await waveOpenMailWeb(waveMailto);
                          return false;
                        }

                        final String waveScheme =
                        waveUri.scheme.toLowerCase();

                        if (waveScheme == 'mailto') {
                          await waveOpenMailWeb(waveUri);
                          return false;
                        }

                        if (waveScheme == 'tel') {
                          await launchUrl(
                            waveUri,
                            mode: LaunchMode.externalApplication,
                          );
                          return false;
                        }

                        final String waveHost =
                        waveUri.host.toLowerCase();
                        final bool waveIsSocial =
                            waveHost.endsWith('facebook.com') ||
                                waveHost.endsWith('instagram.com') ||
                                waveHost.endsWith('twitter.com') ||
                                waveHost.endsWith('x.com');

                        if (waveIsSocial) {
                          await waveOpenExternal(waveUri);
                          return false;
                        }

                        if (waveIsPlatformLink(waveUri)) {
                          final Uri waveWebUri =
                          waveHttpizePlatformUri(waveUri);
                          await waveOpenExternal(waveWebUri);
                          return false;
                        }

                        if (waveScheme == 'http' ||
                            waveScheme == 'https') {
                          waveController.loadUrl(
                            urlRequest: URLRequest(
                              url: WebUri(waveUri.toString()),
                            ),
                          );
                        }

                        return false;
                      },
                      onDownloadStartRequest: (
                          InAppWebViewController waveController,
                          DownloadStartRequest waveReq,
                          ) async {
                        await waveOpenExternal(waveReq.url);
                      },
                    ),
                    Visibility(
                      visible: !waveState.waveVeilVisible,
                      child: const WaveLoader(),
                    ),
                  ],
                ),
              ),
          ],
        );

        if (waveUseSafeArea) {
          waveContent = SafeArea(child: waveContent);
        }

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox.expand(
              child: ColoredBox(
                color: Colors.black,
                child: waveContent,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// main()
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(waveFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tzData.initializeTimeZones();

  runApp(
    MultiBlocProvider(
      providers: <BlocProvider>[
        BlocProvider<WaveHarborBloc>(
          create: (_) => WaveHarborBloc()..add(const WaveHarborInit(null)),
        ),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: WaveHall(),
      ),
    ),
  );
}