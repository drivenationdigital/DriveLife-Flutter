class ApiConfig {
  static const String baseUrl = 'https://www.carevents.com/uk';

  // API version
  static const String apiVersion = 'v2';

  // Optional: common endpoints
  static const String wpJsonPath = '/wp-json/app';

  // Helper to build full endpoint URLs
  static String endpoint(String path) => '$baseUrl$wpJsonPath/$path';

  // Timeouts
  static const Duration requestTimeout = Duration(seconds: 30);
}
