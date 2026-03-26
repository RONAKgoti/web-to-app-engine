import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// PART D - API Service
class ApiService {
  final Dio _dio = Dio();

  Future<dynamic> fetchData(String url) async {
    try {
      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        return response.data;
      }
    } catch (e) {
      rethrow;
    }
    return null;
  }
}

final apiServiceProvider = Provider((ref) => ApiService());
