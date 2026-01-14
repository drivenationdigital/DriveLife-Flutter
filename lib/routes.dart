import 'package:drivelife/screens/vehicle_detail_screen.dart';
import 'package:drivelife/widgets/post_detail_screen.dart';
import 'package:flutter/material.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/home_tabs.dart';
import 'screens/posts_screen.dart';
import 'screens/search_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/view_profile_screen.dart';
import 'package:flutter/cupertino.dart';
import 'screens/edit_profile_settings_screen.dart';
import 'screens/account-settings/manage_social_links_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String posts = '/posts';
  static const String search = '/search';
  static const String notifications = '/notifications';
  static const String profile = '/profile';
  static const String viewProfile = '/view-profile';
  static const String postDetail = '/post-detail';
  static const String vehicleDetail = '/vehicle-detail';

  static const String editProfile = '/edit-profile';
  static const String manageSocialLinks = '/manage-social-links';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _slide(const SplashScreen());
      case login:
        return _slide(const LoginScreen());
      case register:
        return _slide(const RegisterScreen());
      case home:
        return _slide(const HomeTabs());
      case posts:
        return _slide(const PostsScreen());
      case search:
        return _slide(const SearchScreen());
      case notifications:
        return _slide(const NotificationsScreen());
      case profile:
        return _slide(const ProfileScreen());
      case editProfile:
        return _slide(const EditProfileSettingsScreen());
      case manageSocialLinks:
        return _slide(const ManageSocialLinksScreen());
      case viewProfile:
        final args = settings.arguments as Map<String, dynamic>?;

        // ✅ FIXED: Handle userId as either String or int
        final userIdArg = args?['userId'];
        int? userId;

        if (userIdArg != null) {
          if (userIdArg is int) {
            userId = userIdArg;
          } else if (userIdArg is String) {
            userId = int.tryParse(userIdArg);
          }
        }

        return _slide(
          ViewProfileScreen(
            userId: userId,
            username: args?['username']?.toString() ?? '',
          ),
        );
      case postDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return _slide(PostDetailScreen(postId: args['postId']));
      case vehicleDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return _slide(VehicleDetailScreen(garageId: args['garageId']));
      default:
        return _slide(
          Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }

  static PageRouteBuilder _slideInAndroid(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final tween = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  static Route<dynamic> _slideDefault(Widget page) {
    return MaterialPageRoute(builder: (context) => page);
  }

  static Route<dynamic> _slide(Widget page) {
    return CupertinoPageRoute(builder: (context) => page);
  }
}
