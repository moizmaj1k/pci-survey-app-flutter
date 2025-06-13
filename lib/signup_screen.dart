// lib/signup_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pci_survey_application/widgets/custom_snackbar.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'database_helper.dart';
import 'theme/theme_provider.dart';
import 'theme/theme_factory.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;


class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _designation = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _isLoading = false;
  int? _districtId;
  List<Map<String, dynamic>> _districts = [];
  bool _isOnline = true;
  late StreamSubscription<List<ConnectivityResult>> _connSub;

  @override
  void initState() {
    super.initState();
    // Load districts
    DatabaseHelper().getAllDistricts().then((list) {
      setState(() => _districts = list);
    });
    // Monitor connectivity
    _connSub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> statuses) {
      // if any non-none, we're online
      final online = statuses.any((s) => s != ConnectivityResult.none);
      setState(() => _isOnline = online);
    });
  }

  @override
  void dispose() {
    _connSub.cancel();
    _username.dispose();
    _email.dispose();
    _designation.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
      if (!_formKey.currentState!.validate() || _districtId == null) return;

      setState(() => _isLoading = true);

      try {
        // 1) Register API
        final regBody = {
          'username': _username.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
        };
        final regResp = await http.post(
          Uri.parse('http://56.228.26.125:8000/register/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(regBody),
        );

        debugPrint('🛠️ Register status=${regResp.statusCode}, body=${regResp.body}');

        if (regResp.statusCode < 200 || regResp.statusCode >= 300) {
          // show raw body so you know what actually came back
          throw Exception('Registration failed: ${regResp.body}');
        }

        // 2) Enumerator API
        // final sel = _districts.firstWhere((d) => d['id'] == _districtId);
        // final districtUic = sel['district_uic'] as String;
        // final enumBody = {
        //   'name': _username.text.trim(),
        //   'phone': _phone.text.trim(),
        //   'district': districtUic,
        // };
        // final enumResp = await http.post(
        //   Uri.parse('http://56.228.26.125:8000/enumerator/'),
        //   headers: {'Content-Type': 'application/json'},
        //   body: jsonEncode(enumBody),
        // );
        // if (enumResp.statusCode != 200 && enumResp.statusCode != 201) {
        //   throw Exception(
        //     jsonDecode(enumResp.body)['message'] ?? 'Enumerator creation failed',
        //   );
        // }

        // 3) Save locally exactly as before
        final db = DatabaseHelper();
        final uid = await db.insertUser(
          username: _username.text.trim(),
          email: _email.text.trim(),
          designation: _designation.text.trim(),
          password: _password.text,
        );
        await db.saveCurrentUser(uid);
        await db.insertEnumerator(
          name: _username.text.trim(),
          phone: _phone.text.trim(),
          districtId: _districtId!,
          userId: uid,
        );

        // 4) Navigate to login
        Navigator.pushReplacementNamed(context, '/login');
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      );
    }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppNavBar(title: 'Sign Up'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _username,
                decoration: _inputDecoration('Full Name'),
                validator: (v) => v!.isEmpty ? 'Enter your name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: _inputDecoration('Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v!.contains('@') ? null : 'Invalid email',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _designation,
                decoration: _inputDecoration('Designation'),
                validator: (v) => v!.isEmpty ? 'Enter designation' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: _inputDecoration('Phone'),
                keyboardType: TextInputType.phone,
                validator: (v) => v!.isEmpty ? 'Enter phone' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: _inputDecoration('District'),
                items: _districts.map((d) {
                  return DropdownMenuItem(
                    value: d['id'] as int,
                    child: Text(d['district_name']),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _districtId = v),
                validator: (v) => v == null ? 'Select district' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: _inputDecoration('Password'),
                obscureText: true,
                validator: (v) => v!.length < 6 ? 'Min 6 chars' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create Account', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
