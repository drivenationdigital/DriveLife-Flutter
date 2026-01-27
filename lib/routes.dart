import 'package:drivelife/screens/auth/onboarding_screen.dart';
import 'package:drivelife/screens/auth/register/step_five.dart';
import 'package:drivelife/screens/auth/register/step_four.dart';
import 'package:drivelife/screens/auth/register/step_one.dart';
import 'package:drivelife/screens/auth/register/step_three.dart';
import 'package:drivelife/screens/auth/register/step_two.dart';
import 'package:drivelife/screens/create-post/create_post_screen.dart';
import 'package:drivelife/screens/events/event_detail_screen.dart';
import 'package:drivelife/screens/garage/garage_list_screen.dart';
import 'package:drivelife/screens/garage/vehicle_detail_screen.dart';
import 'package:drivelife/screens/search_screen.dart';
import 'package:drivelife/widgets/profile/post_detail_screen.dart';
import 'package:flutter/material.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/home_tabs.dart';
import 'screens/posts_screen.dart';
import 'screens/events/events_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/view_profile_screen.dart';
import 'package:flutter/cupertino.dart';
import 'screens/profile/edit_profile_settings_screen.dart';
import 'screens/account-settings/manage_social_links_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String auth = '/auth';
  static const String login = '/login';
  static const String register = '/register';
  static const String registerStepOne = '/register-step-1';
  static const String registerStepTwo = '/register-step-2';
  static const String registerStepThree = '/register-step-3';
  static const String registerStepFour = '/register-step-4';
  static const String registerStepFive = '/register-step-5';

  static const String home = '/home';
  static const String posts = '/posts';
  static const String events = '/events';
  static const String notifications = '/notifications';
  static const String profile = '/profile';
  static const String viewProfile = '/view-profile';
  static const String postDetail = '/post-detail';
  static const String vehicleDetail = '/vehicle-detail';

  static const String editProfile = '/edit-profile';
  static const String manageSocialLinks = '/manage-social-links';
  static const String createPost = '/create-post';
  static const String garageList = '/garage-list';
  static const String search = '/search';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _slide(const SplashScreen());
      case welcome:
        return _slide(const WelcomeScreen());
      case login:
        return _slide(const LoginScreen());
      case register:
      case registerStepOne:
        return _slide(const RegisterStepOneScreen());
      case registerStepTwo:
        return _slide(const RegisterStepTwoScreen());
      case registerStepThree:
        return _slide(const RegisterStepThreeScreen());
      case registerStepFour:
        return _slide(const RegisterStepFourScreen());
      case registerStepFive:
        return _slide(const RegisterStepFiveScreen());
      case home:
        return _slide(const HomeTabs());
      case posts:
        return _slide(const PostsScreen());
      case createPost:
        final args = settings.arguments as Map<String, dynamic>;
        return _slide(
          CreatePostScreen(
            associationId: args['association_id'],
            associationType: args['association_type'],
            associationLabel: args['association_label'],
          ),
        );
      case events:
        return _slide(const EventsScreen());
      case notifications:
        return _slide(const NotificationsScreen());
      case garageList:
        return _slide(const GarageListScreen());
      case profile:
        return _slide(const ProfileScreen());
      case editProfile:
        return _slide(EditProfileSettingsScreen());
      case manageSocialLinks:
        return _slide(const ManageSocialLinksScreen());
      // In routes.dart or wherever you handle navigation
      case '/event-detail':
        final args = settings.arguments as Map<String, dynamic>;
        return _slide(EventDetailScreen(event: args['event']));
      case search:
        return _slide(const SearchScreen());
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

  static Route<dynamic> _slide(Widget page) {
    return CupertinoPageRoute(builder: (context) => page);
  }
}
