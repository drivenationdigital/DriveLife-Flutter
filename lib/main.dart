import 'package:drivelife/providers/registration_provider.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';
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

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

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
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
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
          onGenerateRoute: AppRoutes.generateRoute,
          initialRoute: AppRoutes.splash,
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
