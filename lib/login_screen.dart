// lib/login_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'package:pci_survey_application/widgets/custom_snackbar.dart';
import 'database_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // 1) Remote login
      final resp = await http.post(
        Uri.parse('http://56.228.26.125:8000/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        }),
      );

      if (resp.statusCode != 200 && resp.statusCode != 201) {
        final msg = jsonDecode(resp.body)['message'] ?? 'Login failed';
        throw Exception(msg);
      }

      final data = jsonDecode(resp.body);
      final token = data['access'] as String?;
      if (token == null) {
        throw Exception('Login response did not include an access token');
      }
      
      // 2) Persist token
      final prefs = await SharedPreferences.getInstance();

      // (optionally) store the refresh too:
      final refresh = data['refresh'] as String?;
      if (refresh != null) {
        await prefs.setString('refresh_token', refresh);
      }
      await prefs.setString('auth_token', token);

      final db = DatabaseHelper();

      // 3) Save user locally (so offline login still works)
      final localUser = await db.getUser(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (localUser == null) {
        throw Exception('Local user not found; please sign up first.');
      }
      final userId = localUser['id'] as int;
      await db.saveCurrentUser(userId);

      // 4) Push enumerator remotely
      final enumRec = await db.getEnumeratorByUserId(userId);
      if (enumRec != null) {
        // resolve district_uic
        final districts = await db.getAllDistricts();
        final sel = districts.firstWhere((d) => d['id'] == enumRec['district_id']);
        final districtUic = sel['district_uic'] as String;

        final enumResp = await http.post(
          Uri.parse('http://56.228.26.125:8000/enumerator/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'name': enumRec['name'],
            'phone': enumRec['phone'],
            'district': districtUic,
          }),
        );
        if (enumResp.statusCode != 200 && enumResp.statusCode != 201) {
          debugPrint('Enumerator push failed: ${enumResp.statusCode}');
        }
      }

      // 5) Navigate on success
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (e) {
      CustomSnackbar.show(
        context,
        e.toString(),
        type: SnackbarType.error,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppNavBar(title: 'Login'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _emailController,
                decoration: _inputDecoration('Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: _inputDecoration('Password'),
                obscureText: true,
                validator: (v) => v != null && v.length >= 6 ? null : 'Min 6 characters',
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24, width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Login', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/signup'),
                child: const Text('Don\'t have an account? Sign up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
