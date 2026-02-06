import 'package:drivelife/providers/cart_provider.dart';
import 'package:drivelife/providers/registration_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
import 'package:drivelife/utils/deeplinks_helper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'routes.dart';
import 'providers/user_provider.dart';
import 'providers/video_mute_provider.dart';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// import League Spartan font from google fonts
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

const String stripePublishableKey =
    'pk_test_51KPRpjHPxUaL4Jbz1Kn3SK5I4T5mL539JGCSyuM81qvXeExgBhxxngXg5FZyb0iqxLjK4FwpyFbG21lXLcinbynl008v1d9eo1';

// Create a global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    Stripe.publishableKey = stripePublishableKey;
    // await Stripe.instance.applySettings();
  } catch (e) {
    print('[Stripe Err] $e');
  }

  try {
    // Initialize Firebase
    await Firebase.initializeApp();
  } catch (e) {
    print('Error initializing Firebase: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => VideoMuteProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => UploadPostProvider()),
        ChangeNotifierProvider(create: (_) => RegistrationProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
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

  @override
  void initState() {
    super.initState();

    // Initialize deep link handler AFTER first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Don't pass context here, let it handle internally
      _deepLinkHandler.initialize();
    });
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
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: themeProvider.themeData.copyWith(
            scaffoldBackgroundColor: Colors.white,
            textTheme: GoogleFonts.leagueSpartanTextTheme(
              Theme.of(context).textTheme,
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              },
            ),
          ),
          // Add this builder to set a white background immediately
          builder: (context, child) {
            return Container(color: Colors.white, child: child);
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
