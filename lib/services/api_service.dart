import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';

class ApiService {
  static String get endpointUrl => '$apiBaseUrl/api/patients';

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$endpointUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['error'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    required int age,
    required String gender,
    required String contact,
    required String email,
    required String password,
    String? middleName,
  }) async {
    try {
      final fullNameParts = [
        name,
        if ((middleName ?? '').trim().isNotEmpty) middleName!.trim(),
      ].where((part) => part.trim().isNotEmpty).toList();

      final response = await http.post(
        Uri.parse('$endpointUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': fullNameParts.join(' '),
          'age': age,
          'gender': gender,
          'contact': contact,
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': data['error'] ?? 'Registration failed',
        };
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
