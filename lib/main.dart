import 'package:drivelife/providers/cart_provider.dart';
import 'package:drivelife/utils/crash_trace.dart';
import 'package:drivelife/providers/location_access_provider.dart';
import 'package:drivelife/providers/registration_provider.dart';
import 'package:drivelife/providers/pending_tags_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/gallery_upload_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/services/analytics_service.dart';
import 'package:drivelife/services/app_error_logger.dart';
import 'package:drivelife/services/auth_service.dart';
import 'package:drivelife/services/firebase_messaging_service.dart';
import 'package:drivelife/utils/analytics_route_observer.dart';
import 'package:drivelife/utils/deeplinks_helper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'routes.dart';
import 'providers/user_provider.dart';
import 'providers/account_provider.dart';
import 'providers/video_mute_provider.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:drivelife/config/mapbox_config.dart';
import 'package:drivelife/config/app_environment.dart';
import 'package:drivelife/providers/connectivity_provider.dart';
import 'package:drivelife/providers/feature_tips_provider.dart';
import 'package:drivelife/widgets/offline_banner.dart';

// const String stripePublishableKey =
//     'pk_test_51H0Z3HGcmkippALfD7tDQ7tvZ80SHeBBOHX6ABm1fHca3FQWPDR4DnXIZtYh1AzaWnvRXAXgBpdur4XR5ceWdHOk00PEsDjNOZ';
// const String stripePublishableKey =
//     'pk_live_51KPRpjHPxUaL4Jbz8h65yzP0a0RRORzQbmOv9qdXZbRs8Scsb9lV9UlaDSIqI1QIIFi93JYwRBU76zl3RFsTjQK3001yEe0JHT';

const String stripePublishableKey =
    'pk_live_51H0Z3HGcmkippALfhsfFEMLG0T7zbwRrAHFKk36djEg4n00qMSHTlIZXs9pth8LncJjFI7ER8inHFyZkaBcUAFhY00X4Gd5Bn9';

// Create a global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();
final AnalyticsRouteObserver analyticsObserver = AnalyticsRouteObserver();
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Where the app currently is: which bottom-bar destination, and which
/// section of Home within it.
///
/// Both live here, and both have names. The Home section used to be private
/// state inside the shell, which meant anything else that wanted to send the
/// user to Events had no way to say so and used a bare bottom-bar index
/// instead — and when the bar was reordered, "Find Events" quietly started
/// opening the map. Naming the destinations is what stops that happening
/// again: `BottomNavProvider.events` cannot drift, where `1` can.
class BottomNavProvider extends ChangeNotifier {
  // ── bottom bar destinations, in the order they appear ──────────────
  static const int home = 0;
  static const int discover = 1;
  static const int groups = 2;
  static const int photos = 3;
  static const int account = 4;

  /// How many destinations there are. The shell asserts its own list
  /// against this, because the two are matched by position.
  static const int destinationCount = account + 1;

  // ── sections of Home, in the order of its top tab row ──────────────
  static const int forYou = 0;
  static const int events = 1;
  static const int places = 2;
  static const int tracks = 3;
  static const int businesses = 4;
  static const int shop = 5;

  static const int sectionCount = shop + 1;

  int _currentIndex = home;
  int _homeSection = forYou;

  int get currentIndex => _currentIndex;

  /// Which section of Home is showing. Only meaningful while [currentIndex]
  /// is [home], but kept across visits elsewhere so returning to Home lands
  /// where it was left.
  int get homeSection => _homeSection;

  void setIndex(int index) {
    if (_currentIndex == index) return;
    _currentIndex = index;
    notifyListeners();
  }

  /// Shows a section of Home, switching to Home if it is not already there.
  ///
  /// One call rather than two, because the two have to happen together:
  /// setting the section while on another destination changes nothing
  /// visible, and switching to Home first shows the old section for a frame.
  void openHomeSection(int section) {
    if (_currentIndex == home && _homeSection == section) return;
    _currentIndex = home;
    _homeSection = section;
    notifyListeners();
  }
}

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Reprints build-time crashes with our own frames and the widget the
  // framework blames, because the default dump is forty frames of
  // Element.inflateWidget with nothing of ours in it. Debug only.
  installCrashTrace();

  // Reads assets/config/mapbox.json and hands the token to the Maps SDK.
  // Before runApp so the Discover map is ready the moment it is opened, and
  // never throws — a missing token leaves that one screen explaining itself
  // rather than stopping launch.
  await MapboxConfig.load();

  final accountManager = AccountManager();
  await accountManager.loadAccounts();

  await accountManager.cleanupDuplicates();

  final authService = AuthService();
  authService.setAccountManager(accountManager);

  try {
    AppEnvironment.assertSafeForRelease();
    Stripe.publishableKey = stripePublishableKey;
    Stripe.merchantIdentifier = 'merchant.com.app.carcalendar';
    // await Stripe.instance.applySettings();
  } catch (e) {
    print('[Stripe Err] $e');
  }

  try {
    await Firebase.initializeApp();
    FirebaseMessagingService.navigatorKey = navigatorKey;
    print('✅ Assigned navigatorKey: ${FirebaseMessagingService.navigatorKey}');
    await FirebaseMessagingService.initialize();
  } catch (e) {
    print('Error initializing Firebase: $e');
  }

  // Piwik PRO analytics — never throws, logs and no-ops on failure.
  await Analytics.initialize();

  // await SupabaseConfig.initialize();
  // await UserProfileCache.instance.loadFromDisk();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: accountManager),
        Provider.value(value: authService),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => VideoMuteProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => UploadPostProvider()),
        // Above the navigator so a gallery upload outlives the screen that
        // started it.
        ChangeNotifierProvider(create: (_) => GalleryUploadProvider()),
        ChangeNotifierProvider(create: (_) => RegistrationProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => UnreadCountProvider()),
        ChangeNotifierProvider(create: (_) => BottomNavProvider()),
        ChangeNotifierProvider(create: (_) => PendingTagsProvider()),
        ChangeNotifierProvider(create: (_) => LocationAccessProvider()),
        // Starts watching as soon as it is built, which is before the first
        // screen asks for anything.
        ChangeNotifierProvider(
          create: (_) => ConnectivityProvider()..start(),
          lazy: false,
        ),
        // One preferences read, off the first frame. Nothing is shown until
        // it lands, so a cold start never flashes a tip and takes it away.
        ChangeNotifierProvider(
          create: (_) => FeatureTipsProvider()..load(),
          lazy: false,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _deepLinkHandler = DeepLinkHandler();
  double _previousVolume = 0;
  late VideoMuteProvider _muteProvider;

  @override
  void initState() {
    super.initState();

    // Initialize deep link handler AFTER first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Don't pass context here, let it handle internally
      _deepLinkHandler.initialize();

      _muteProvider = context.read<VideoMuteProvider>();

      // Android: listen to media stream specifically
      await FlutterVolumeController.updateShowSystemUI(true);
      FlutterVolumeController.setAndroidAudioStream(stream: AudioStream.music);

      _previousVolume = await FlutterVolumeController.getVolume() ?? 0;
      debugPrint('🔊 Initial volume: $_previousVolume');

      FlutterVolumeController.addListener((newVolume) {
        if (newVolume > _previousVolume) {
          _muteProvider.unmuteFromVolumeButton();
        }
        _previousVolume = newVolume;
      });
    });

    // Flush any queued logs from previous offline sessions
    AppLogger.flushQueue();
  }

  @override
  void dispose() {
    _deepLinkHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          navigatorObservers: [routeObserver, analyticsObserver],
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: themeProvider.themeData.copyWith(
            scaffoldBackgroundColor: Colors.white,
            // textTheme: GoogleFonts.leagueSpartanTextTheme(
            //   Theme.of(context).textTheme,
            // ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              },
            ),
          ),
          // Add this builder to set a white background immediately
          builder: (context, child) {
            return Container(
              color: Colors.white,
              // Above the navigator, so the strip survives every push and
              // pop rather than each screen having to know about it.
              child: OfflineBanner(child: child ?? const SizedBox.shrink()),
            );
          },
          initialRoute: AppRoutes.splash,
          onGenerateRoute: AppRoutes.generateRoute,
          onGenerateInitialRoutes: (String initialRoute) {
            debugPrint('🚀 [App] Initial route requested: $initialRoute');

            // If it's a deep link URL, ignore it and start at splash
            if (initialRoute.startsWith('https://') ||
                initialRoute.startsWith('http://') ||
                initialRoute.contains('app.mydrivelife.com') ||
                initialRoute.contains('?')) {
              debugPrint('🔗 [App] Deep link detected, forcing splash screen');
              return [
                AppRoutes.generateRoute(
                  const RouteSettings(name: AppRoutes.splash),
                ),
              ];
            }

            // Otherwise use the requested route
            return [AppRoutes.generateRoute(RouteSettings(name: initialRoute))];
          },
          localizationsDelegates: const [
            FlutterQuillLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'US')],
        );
      },
    );
  }
}
