import 'package:shared_preferences/shared_preferences.dart';

// PART D - Cache Service for Offline Support
class CacheService {
  static const String _urlKey = "cached_url_data";

  Future<void> cacheData(String data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, data);
  }

  Future<String?> getCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_urlKey);
  }
}
