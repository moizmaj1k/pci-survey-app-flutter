// lib/dashboard_screen.dart
import 'dart:async';
import 'package:pci_survey_application/widgets/custom_snackbar.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'database_helper.dart';
import 'data_viewer.dart';
import 'theme/theme_factory.dart'; // for AppColors

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  final _db = DatabaseHelper();
  bool _isOnline = true;
  bool _locationEnabled = true;
  late StreamSubscription<ConnectivityResult> _connSub;
  late StreamSubscription<ServiceStatus> _locSub;

  @override
  void initState() {
    super.initState();
    // monitor connectivity
    _connSub = Connectivity().onConnectivityChanged.listen((status) {
      setState(() => _isOnline = status != ConnectivityResult.none);
    });

    // check initial location service state
    Geolocator.isLocationServiceEnabled().then((enabled) {
      setState(() => _locationEnabled = enabled);
    });

    // **listen** for location service changes  ②
    _locSub = Geolocator
        .getServiceStatusStream()
        .listen((ServiceStatus status) {
      final enabled = status == ServiceStatus.enabled;
      if (enabled != _locationEnabled) {
        setState(() => _locationEnabled = enabled);
      }
    });
  }


  @override
  void dispose() {
    _connSub.cancel();
    _locSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _db.getEnumeratorDetails(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final enumr = snapshot.data;
        final isRegistered = enumr != null;

        final pages = <Widget>[
          HomeTab(
            enumerator: enumr,
            onRegistered: () => setState(() {}),
          ),
          NewSurveyTab(),
          const ViewTab(),
          UploadDataTab(),
          SettingsTab(onViewData: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DataViewer()));
          }),
        ];

        return Scaffold(
          appBar: AppNavBar(
            title: _titleFor(_currentIndex),
            automaticallyImplyLeading: false,
          ),
          body: pages[_currentIndex],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            type: BottomNavigationBarType.fixed,
            onTap: (i) async {
              // first, location must be enabled for New, View, Upload
              if (!_locationEnabled && (i == 1 || i == 2 || i == 3)) {
                CustomSnackbar.show(
                  context,
                  'Enable location services first.',
                  type: SnackbarType.error,
                );
                return;
              }
              // next, upload needs internet
              if (i == 3 && !_isOnline) {
                CustomSnackbar.show(
                  context,
                  'No internet: cannot upload.',
                  type: SnackbarType.warning,
                );
                return;
              }
              // also require enumerator registration
              if (!isRegistered && (i == 1 || i == 2 || i == 3)) {
                CustomSnackbar.show(
                  context,
                  'Please register as Enumerator first.',
                  type: SnackbarType.warning,
                );
                return;
              }
              setState(() => _currentIndex = i);
            },
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(
                  icon:
                      Icon(Icons.add, color: isRegistered ? null : Colors.grey),
                  label: 'New'),
              BottomNavigationBarItem(
                  icon:
                      Icon(Icons.list, color: isRegistered ? null : Colors.grey),
                  label: 'View'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.cloud_upload,
                      color: isRegistered ? null : Colors.grey),
                  label: 'Upload'),
              const BottomNavigationBarItem(
                  icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }

  String _titleFor(int idx) {
    switch (idx) {
      case 1:
        return 'New Survey';
      case 2:
        return 'View Data';
      case 3:
        return 'Upload Data';
      case 4:
        return 'Settings';
      default:
        return 'Dashboard';
    }
  }
}

/// HOME TAB: shows registration form or details+metrics
class HomeTab extends StatefulWidget {
  final Map<String, dynamic>? enumerator;
  final VoidCallback onRegistered;
  const HomeTab({
    Key? key,
    required this.enumerator,
    required this.onRegistered,
  }) : super(key: key);

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  int? _districtId;
  List<Map<String, dynamic>> _districts = [];
  bool _loading = false;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _loadDistricts();
    if (widget.enumerator != null) {
      _nameCtrl.text = widget.enumerator!['name'];
      _phoneCtrl.text = widget.enumerator!['phone'];
      _districtId = widget.enumerator!['district_id'] as int;
    }
  }

  Future<void> _loadDistricts() async {
    final list = await DatabaseHelper().getAllDistricts();
    setState(() => _districts = list);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _districtId == null) return;
    setState(() => _loading = true);
    final db = DatabaseHelper();

    if (widget.enumerator == null) {
      // first‐time registration
      final userId = await db.getCurrentUserId() ?? 0;
      await db.insertEnumerator(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        districtId: _districtId!,
        userId: userId,
      );
    } else {
      // updating district only
      await db.updateEnumeratorDetails(
        _nameCtrl.text.trim(),
        _phoneCtrl.text.trim(),
        _districts.firstWhere((d) => d['id'] == _districtId!)['district_name']
            as String,
      );
    }

    setState(() {
      _loading = false;
      _editMode = false;
    });
    widget.onRegistered();
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      );

  @override
  Widget build(BuildContext context) {
    // Not registered: show form
    if (widget.enumerator == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text('Register Enumerator',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: _dec('Name'),
                validator: (v) => v!.isEmpty ? 'Enter name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: _dec('Phone'),
                validator: (v) => v!.isEmpty ? 'Enter phone' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: _dec('District'),
                items: _districts
                    .map((d) => DropdownMenuItem(
                        value: d['id'] as int,
                        child: Text(d['district_name'])))
                    .toList(),
                onChanged: (v) => setState(() => _districtId = v),
                validator: (v) => v == null ? 'Select district' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                style:
                    ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('Submit'),
              ),
            ],
          ),
        ),
      );
    }

    // Registered: show details + metrics
    final enumr = widget.enumerator!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Hello, ${enumr['name']}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 2,

              color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade900
                : Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _infoRow('Your Registered Phone', enumr['phone']),
                    _infoRow('District Being Covered', enumr['district']),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ─── New “Change District” button ───────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_location),
                label: const Text('Change District'),
                onPressed: _showChangeDistrictDialog,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.2,
                children: [
                  _AsyncMetricCard(
                    label: 'Completed',
                    icon: Icons.check_circle,
                    color: AppColors.success,
                    futureCount: Future.value(0),
                  ),
                  _AsyncMetricCard(
                    label: 'Uncompleted',
                    icon: Icons.pending,
                    color: AppColors.danger,
                    futureCount: Future.value(0),
                  ),
                  _AsyncMetricCard(
                    label: 'Pushed',
                    icon: Icons.cloud_done,
                    color: Theme.of(context).colorScheme.primary,
                    futureCount: Future.value(0),
                  ),
                  _AsyncMetricCard(
                    label: 'Unpushed',
                    icon: Icons.cloud_upload,
                    color: AppColors.warning,
                    futureCount: Future.value(0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pops a dialog to let user pick a new district.
  Future<void> _showChangeDistrictDialog() async {
    int? newDistrictId = _districtId;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change District'),
        content: StatefulBuilder(
          builder: (ctx2, setDialogState) {
            return DropdownButtonFormField<int>(
              value: newDistrictId,
              decoration: InputDecoration(
                labelText: 'District',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              items: _districts.map((d) {
                return DropdownMenuItem(
                  value: d['id'] as int,
                  child: Text(d['district_name']),
                );
              }).toList(),
              onChanged: (v) => setDialogState(() => newDistrictId = v),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newDistrictId == null) return;
              Navigator.pop(ctx);

              setState(() => _loading = true);

              final db = DatabaseHelper();
              // call your existing updateEnumeratorDetails
              final newName = _nameCtrl.text.trim();
              final newPhone = _phoneCtrl.text.trim();
              final newDistrictName = _districts
                  .firstWhere((d) => d['id'] == newDistrictId)['district_name']
                  as String;

              await db.updateEnumeratorDetails(
                newName,
                newPhone,
                newDistrictName,
              );

              setState(() {
                _districtId = newDistrictId;
                _loading = false;
              });
              widget.onRegistered(); // tell parent to re-fetch details
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ]),
    );
  }
}

/// A metric card backed by a Future<int>
class _AsyncMetricCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Future<int> futureCount;
  const _AsyncMetricCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.futureCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.grey.shade900 : Colors.grey.shade100;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
      color: bg,
      child: FutureBuilder<int>(
        future: futureCount,
        builder: (ctx, snap) {
          final count = snap.data ?? 0;
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 28, color: color),
                    const SizedBox(width: 8),
                    Text('$count',
                        style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          );
        },
      ),
    );
  }
}

// -- Placeholder tabs for the other screens --

class NewSurveyTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child:
          Text('Start a new survey', style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

class ViewTab extends StatelessWidget {
  const ViewTab({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Center(
      child:
          Text('View collected data', style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

class UploadDataTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child:
          Text('Upload collected data', style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

class SettingsTab extends StatelessWidget {
  final VoidCallback onViewData;
  const SettingsTab({Key? key, required this.onViewData}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: onViewData,
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.black,
            minimumSize: const Size(200, 50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        child: const Text('View Data'),
      ),
    );
  }
}
