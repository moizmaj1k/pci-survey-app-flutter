// lib/signup_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'database_helper.dart';
import 'theme/theme_provider.dart';
import 'theme/theme_factory.dart';


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
  int? _districtId;
  List<Map<String, dynamic>> _districts = [];
  bool _isOnline = true;
  late StreamSubscription<ConnectivityResult> _connSub;

  @override
  void initState() {
    super.initState();
    // Load districts
    DatabaseHelper().getAllDistricts().then((list) {
      setState(() => _districts = list);
    });
    // Monitor connectivity
    _connSub = Connectivity().onConnectivityChanged.listen((status) {
      setState(() => _isOnline = status != ConnectivityResult.none);
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
    Navigator.pushReplacementNamed(context, '/dashboard');
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
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
