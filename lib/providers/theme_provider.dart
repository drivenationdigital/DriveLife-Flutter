import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeProvider extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _themeKey = 'theme_mode';
  static const PRIMARY_COLOR_CODE = 0xFFAE9159;

  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final savedTheme = await _storage.read(key: _themeKey);
    _isDarkMode = savedTheme == 'dark';
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _storage.write(key: _themeKey, value: _isDarkMode ? 'dark' : 'light');
    notifyListeners();
  }

  ThemeData get themeData {
    if (_isDarkMode) {
      return ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          selectedItemColor: Color(PRIMARY_COLOR_CODE),
          unselectedItemColor: Colors.grey,
        ),
      );
    } else {
      return ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.grey,
        ),
      );
    }
  }

  // Helper colors for custom widgets
  Color get backgroundColor =>
      _isDarkMode ? const Color(0xFF121212) : Colors.white;
  Color get cardColor =>
      _isDarkMode ? const Color(0xFF1E1E1E) : Colors.grey.shade50;
  Color get textColor => _isDarkMode ? Colors.white : Colors.black;
  Color get textColorSecondary => _isDarkMode ? Colors.black : Colors.white;

  Color get subtextColor => _isDarkMode ? Colors.grey : Colors.grey.shade600;
  Color get dividerColor =>
      _isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200;
  Color get primaryColor => _isDarkMode
      ? const Color(PRIMARY_COLOR_CODE)
      : const Color(PRIMARY_COLOR_CODE);
  Color get secondaryColor =>
      _isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFF1A1A1A);
  Color get secondaryCardColor =>
      _isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFF1A1A1A);
}
