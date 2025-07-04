// lib/dashboard_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pci_survey_application/survey_dashboard.dart';
import 'package:pci_survey_application/survey_list_screen.dart';
import 'package:pci_survey_application/theme/theme_provider.dart';
import 'package:pci_survey_application/widgets/custom_snackbar.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'data_viewer.dart';
import 'theme/theme_factory.dart'; // for AppColors
import 'services/uploader.dart';


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
  late StreamSubscription<List<ConnectivityResult>> _connSub;
  late StreamSubscription<ServiceStatus> _locSub;

  @override
  void initState() {
    super.initState();
    // monitor connectivity
    _connSub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> statuses) {
      // if any non-none, we're online
      final online = statuses.any((s) => s != ConnectivityResult.none);
      setState(() => _isOnline = online);
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
          SettingsTab(
            onViewData: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DataViewer()),
              );
            },
            onViewSurveys: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SurveyListScreen()),
              );
            },
          ),
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
              // Make the selected icon larger + primary color
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Colors.grey,
            selectedIconTheme: IconThemeData(
              size: 28,                                          // larger size
              color: Theme.of(context).colorScheme.primary,      // primary color
            ),
            unselectedIconTheme: const IconThemeData(
              size: 20,                                          // normal size
              color: Colors.grey,                                // grey out
            ),
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

    // Registered: show details + metrics + intro card
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

            // Enumerator details card
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

            // Change district button
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.9,    // 80% of available width
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
            ),
            const SizedBox(height: 12),

            // Metrics + Intro combined scroll area
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // ─── Metric Cards ─────────────────────────────
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,      // tighter gutter
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.6,    // slightly more compact
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      children: [
                        _AsyncMetricCard(
                          label: 'Completed',
                          icon: Icons.check_circle,
                          color: AppColors.success,
                          futureCount: DatabaseHelper().getSurveyCountByStatus('completed'),
                        ),
                        _AsyncMetricCard(
                          label: 'Uncompleted',
                          icon: Icons.pending,
                          color: AppColors.danger,
                          futureCount: DatabaseHelper().getSurveyCountByStatus('draft'),
                        ),
                        _AsyncMetricCard(
                          label: 'Pushed',
                          icon: Icons.cloud_done,
                          color: AppColors.primary,
                          futureCount: DatabaseHelper().getPushedSurveyCount(),
                        ),
                        _AsyncMetricCard(
                          label: 'Unpushed',
                          icon: Icons.cloud_upload,
                          color: AppColors.warning,
                          futureCount: DatabaseHelper().getUnpushedSurveyCount(),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // ─── App Intro Card ───────────────────────────
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 6,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withOpacity(0.2),
                              AppColors.info.withOpacity(0.2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,  // left-align text
                          children: [
                            // Icon & heading stay centered
                            Center(
                              child: Column(
                                children: [
                                  Icon(Icons.map, size: 48, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Welcome to PCI Survey!',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // left-aligned body text
                            Text(
                              'Use the tabs below to:\n'
                              '• New: start a fresh survey\n'
                              '• View: browse your collected data\n'
                              '• Upload: sync completed surveys\n'
                              '• Settings: adjust your preferences',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.start,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
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
    final screenContext = context;

    await showDialog(
      context: screenContext,
      builder: (dialogContext) => AlertDialog(
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
                fillColor: Theme.of(screenContext).colorScheme.surface,
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
          // Cancel button: warning bg, black text
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              minimumSize: const Size(80, 40),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),

          // Save button: success bg, white text
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              minimumSize: const Size(80, 40),
            ),
            onPressed: () async {
              if (newDistrictId == null) return;

              Navigator.of(dialogContext).pop();
              setState(() => _loading = true);

              final db = DatabaseHelper();
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
              widget.onRegistered();

              CustomSnackbar.show(
                screenContext,
                'District updated successfully!',
                type: SnackbarType.success,
              );
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




class NewSurveyTab extends StatefulWidget {
  const NewSurveyTab({Key? key}) : super(key: key);

  @override
  State<NewSurveyTab> createState() => _NewSurveyTabState();
}

class _NewSurveyTabState extends State<NewSurveyTab> {
  final _formKey       = GlobalKey<FormState>();
  final _roadNameCtrl  = TextEditingController();
  final _startRdCtrl   = TextEditingController();
  List<Map<String, dynamic>> _districts = [];
  int?    _selectedDistrictId;
  double? _startLat, _startLon;
  bool    _loading = false;

  @override
  void initState() {
    super.initState();
    _loadDistricts();
  }

  Future<void> _loadDistricts() async {
    _districts = await DatabaseHelper().getAllDistricts();
    setState(() {});
  }

  Future<void> _fetchLocation() async {
    // 1. Service enabled?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      CustomSnackbar.show(
        context,
        'Location services are disabled. Please enable them in your device settings.',
        type: SnackbarType.error,
      );
      return;
    }

    // 2. Permission check / request
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        CustomSnackbar.show(
          context,
          'Location permission denied.',
          type: SnackbarType.error,
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      CustomSnackbar.show(
        context,
        'Location permission permanently denied. Please enable it in Settings.',
        type: SnackbarType.error,
      );
      return;
    }

    // 3. Finally, actually fetch
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _startLat = pos.latitude;
        _startLon = pos.longitude;
      });
      CustomSnackbar.show(
        context,
        'Location fetched successfully.',
        type: SnackbarType.success,
      );
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Failed to get current location.',
        type: SnackbarType.error,
      );
    }
  }


  Future<void> _onStartPressed() async {
    // 1) field‐level “not empty” check
    if (!_formKey.currentState!.validate()) return;

    // 2) enforce the pattern: any digits, then ‘+’, then exactly 3 digits
    final rd = _startRdCtrl.text.trim();
    final rdPattern = RegExp(r'^\d+\+\d{3}$');
    if (!rdPattern.hasMatch(rd)) {
      CustomSnackbar.show(
        context,
        'Invalid Start RD. Must be like 0+100 or 27+300 (any number of digits before “+”, exactly 3 after).',
        type: SnackbarType.error,
      );
      return;
    }

    // 3) location check as before
    if (_startLat == null || _startLon == null) {
      CustomSnackbar.show(
        context,
        'Please tap "Get Location" first',
        type: SnackbarType.warning,
      );
      return;
    }

    // 4) rest of your insert logic…
    setState(() => _loading = true);
    final userId = await DatabaseHelper().getCurrentUserId() ?? 0;
    try {
      final newId = await DatabaseHelper().insertPciSurvey(
        districtId: _selectedDistrictId!,
        roadName: _roadNameCtrl.text.trim(),
        startRd: rd,
        startLat: _startLat!,
        startLon: _startLon!,
        createdBy: userId,
      );
      CustomSnackbar.show(
        context,
        'Survey #$newId started',
        type: SnackbarType.success,
      );
      Navigator.pushNamed(
        context,
        SurveyDashboard.routeName,
        arguments: newId,
      );
    } catch (_) {
      CustomSnackbar.show(
        context,
        'Failed to start survey',
        type: SnackbarType.error,
      );
    } finally {
      setState(() => _loading = false);
    }
  }
    
  @override
  Widget build(BuildContext context) {
    // Compute text color for success button based on its background luminance
    final startTextColor = AppColors.success.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ─── Instruction Card ───────────────────────────────
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 6,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.2),
                  AppColors.info.withOpacity(0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,  // left-align text
              children: [
                // Icon & heading stay centered
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.info, size: 48, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        'Before you begin:',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // left-aligned body text
                Text(
                  '• Stand at the START location of the road.\n'
                  '• Complete all the details in the form below.\n'
                  '• Start the survey, record distress points.\n'
                  '• Once survey is done, you’ll enter END details.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
        ),
        

        const SizedBox(height: 24),

        // ─── Section Heading ────────────────────────────────
        Text(
          'Enter Road Details to Start Survey',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),

        const SizedBox(height: 16),

        // ─── Form ────────────────────────────────────────────
        Form(
          key: _formKey,
          child: Column(children: [
            DropdownButtonFormField<int>(
              decoration: InputDecoration(
                labelText: 'District',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: _districts
                  .map((d) => DropdownMenuItem<int>(
                        value: d['id'] as int,
                        child: Text(d['district_name'] as String),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedDistrictId = v),
              validator: (v) => v == null ? 'Select district' : null,
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: _roadNameCtrl,
              decoration: InputDecoration(
                labelText: 'Road Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter road name' : null,
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: _startRdCtrl,
              decoration: InputDecoration(
                labelText: 'Start RD',
                hintText: 'e.g. 0+100',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Enter Start RD';
                }
                return null;
              },
            ),

            const SizedBox(height: 12),

            // ─── Get Location Button & Display ───────────────
            Row(children: [
              ElevatedButton.icon(
                onPressed: _fetchLocation,
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Get Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: AppColors.light,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 16),
              if (_startLat != null && _startLon != null)
                Expanded(
                  child: Text(
                    '${_startLat!.toStringAsFixed(5)}, ${_startLon!.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ]),

            const SizedBox(height: 24),

            // ─── Start Button ─────────────────────────────────
            FractionallySizedBox(
              widthFactor: 0.8, // 80% width
              child: ElevatedButton(
                onPressed: _loading ? null : _onStartPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: startTextColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('Start PCI Survey for this Road'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}




class ViewTab extends StatefulWidget {
  const ViewTab({Key? key}) : super(key: key);

  @override
  State<ViewTab> createState() => _ViewTabState();
}

class _ViewTabState extends State<ViewTab> {
  // Lists to hold “draft” and “completed” surveys
  List<Map<String, dynamic>> _incompleteSurveys = [];
  List<Map<String, dynamic>> _completedSurveys = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSurveys();
  }

  Future<void> _loadSurveys() async {
    setState(() {
      _loading = true;
    });

    try {
      // Fetch surveys with status = 'draft' (incomplete)
      final drafts = await DatabaseHelper().getPciSurveysByStatus('draft');
      // Fetch surveys with status = 'completed'
      final completed = await DatabaseHelper().getUnpushedPciSurveys();

      setState(() {
        _incompleteSurveys = drafts;
        _completedSurveys = completed;
      });
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Failed to load surveys',
        type: SnackbarType.error,
      );
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  /// Deletes the given survey and its distress points, then refreshes the list.
  Future<void> _deleteSurvey(int surveyId) async {
    try {
      await DatabaseHelper().deletePciSurvey(surveyId);
      CustomSnackbar.show(
        context,
        'Survey #$surveyId deleted.',
        type: SnackbarType.success,
      );
      // Immediately reload so the UI updates
      await _loadSurveys();
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Failed to delete survey #$surveyId',
        type: SnackbarType.error,
      );
    }
  }

  /// Shows a confirmation dialog before actually deleting.
  void _confirmDelete(int surveyId) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete Survey?'),
          content: const Text(
            'Deleting this survey will also delete all the distress points recorded on it.\n\n'
            'Are you sure you want to delete?',
          ),
          actions: [
            // "No" button: success background, closes dialog
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
              onPressed: () {
                Navigator.of(ctx).pop(); // just close the dialog
              },
              child: Text(
                'No',
                style: TextStyle(
                  color: AppColors.success.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),

            // "Yes" button: danger background, performs delete, then closes dialog
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
              onPressed: () {
                Navigator.of(ctx).pop(); // close confirmation dialog
                _deleteSurvey(surveyId);
              },
              child: Text(
                'Yes',
                style: TextStyle(
                  color: AppColors.danger.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompletedSurveyCard({
    required Map<String, dynamic> survey,
  }) {
    final int surveyId = survey['id'] as int;
    final String roadName = survey['road_name'] as String? ?? 'Unnamed road';
    final String createdAt = survey['created_at'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Row with “Survey #…” and “Road Name” ─────────────────────
            Row(
              children: [
                // 1) Survey # container (surface background, onSurface text)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Survey #$surveyId',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 2) Road Name container (warning background, black text)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    roadName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),

            // ─── Created At (if available) ──────────────────────────────
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Created: $createdAt',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            const SizedBox(height: 6),
            // ─── “View” button aligned right ─────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    SurveyDashboard.routeName,
                    arguments: surveyId,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.success.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: const Size(64, 32),
                ),
                child: const Text(
                  'View',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncompleteSurveyCard({
    required Map<String, dynamic> survey,
  }) {
    final int surveyId = survey['id'] as int;
    final String roadName = survey['road_name'] as String? ?? 'Unnamed road';
    final String createdAt = survey['created_at'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Row with “Survey #…” and “Road Name” ─────────────────────
            Row(
              children: [
                // 1) Survey # container (surface background, onSurface text)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Survey #$surveyId',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 2) Road Name container (warning background, black text)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    roadName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),

            // ─── Created At (if available) ──────────────────────────────
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Created At: $createdAt',
                style: const TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            const SizedBox(height: 6),
            // ─── Two buttons: “Delete” (opens confirmation) and “Continue” ─
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1) Delete button: opens confirmation dialog
                  ElevatedButton(
                    onPressed: () => _confirmDelete(surveyId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: AppColors.danger.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: const Size(64, 32),
                    ),
                    child: const Text(
                      'Delete',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 2) Continue button, unchanged
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        SurveyDashboard.routeName,
                        arguments: surveyId,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: AppColors.primary.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: const Size(64, 32),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // Simple loading indicator while fetching both lists
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadSurveys,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.only(top: 16.0, bottom: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Section 1: Incomplete Surveys ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Incomplete Surveys',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              if (_incompleteSurveys.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'You have no incomplete surveys.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                Column(
                  children: _incompleteSurveys.map((survey) {
                    return _buildIncompleteSurveyCard(survey: survey);
                  }).toList(),
                ),

              const SizedBox(height: 24),

              // ─── Section 2: Completed Surveys ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Completed Surveys',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              if (_completedSurveys.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'You have no completed surveys.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                Column(
                  children: _completedSurveys.map((survey) {
                    return _buildCompletedSurveyCard(survey: survey);
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}






class UploadDataTab extends StatefulWidget {
  const UploadDataTab({Key? key}) : super(key: key);
  @override
  _UploadDataTabState createState() => _UploadDataTabState();
}

class _UploadDataTabState extends State<UploadDataTab> {
  late Future<_UploadInfo> _infoFuture;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _infoFuture = _loadUploadInfo();

    // once the first frame is up, subscribe to Uploader
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uploader = context.read<Uploader>();
      uploader.addListener(() {
        // when busy goes false, refresh
        if (!uploader.busy && mounted) {
          setState(() {
            _infoFuture = _loadUploadInfo();
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final uploader   = context.watch<Uploader>();
    final busy       = uploader.busy;
    final done       = uploader.doneImages;
    final total      = uploader.totalImages;
    final progress   = uploader.progress;
    final current    = uploader.current;

    return FutureBuilder<_UploadInfo>(
      future: _infoFuture,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final info = snap.data!;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary
              Row(
                children: [
                  Expanded(
                    child: Card(
                      color: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        child: Column(
                          children: [
                            Text(
                              '${info.pendingSurveys}',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Surveys pending',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      color: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        child: Column(
                          children: [
                            Text(
                              '${info.pendingImages}',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Images to upload',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Progress Card
              if (busy && current != null) ...[
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Uploading images for Survey $current',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor:
                                AppColors.primary.withOpacity(0.2),
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // ← New line showing X of Y
                        Text(
                          '$done of $total images uploaded',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Upload All Images button
              ElevatedButton.icon(
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.image, size: 20),
                label: Text(
                  busy ? 'Uploading Images…' : 'Upload All Images',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: busy
                  ? null
                  : () async {
                      final conn = await Connectivity().checkConnectivity();
                      if (conn == ConnectivityResult.none) {
                        CustomSnackbar.show(
                          context,
                          'No internet connection.',
                          type: SnackbarType.warning,
                        );
                        return;
                      }

                      await uploader.uploadAllPending();
                      // now that uploads are done:
                      if (!mounted) return;
                      CustomSnackbar.show(
                        context,
                        'All pending images have been uploaded.',
                        type: SnackbarType.success,
                      );
                      setState(() {
                        _infoFuture = _loadUploadInfo();
                      });
                    },
              ),
              const SizedBox(height: 32),

              // ─── Surveys Ready to Push ────────────────────────
              if (info.readySurveys.isEmpty)
                Text(
                  'No surveys ready to push.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: info.readySurveys.length,
                    itemBuilder: (ctx, i) {
                      final s  = info.readySurveys[i];
                      final id = s['id'] as int;
                      final name = s['road_name'] as String? ?? 'Survey #$id';
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 3,
                        child: ListTile(
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Survey #$id — images uploaded'),
                          trailing: ElevatedButton(
                            onPressed: () => _pushSurvey(id),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Push Data'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pushSurvey(int surveyId) async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      CustomSnackbar.show(
        context,
        'No internet connection.',
        type: SnackbarType.warning,
      );
      return;
    }

    // 1) grab auth token
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) {
      CustomSnackbar.show(
        context,
        'Auth token missing – please log in again.',
        type: SnackbarType.error,
      );
      return;
    }

    final db = DatabaseHelper();

    try {
      // 2) Load survey row
      final survey = await db.getPciSurveyById(surveyId);
      if (survey == null) throw 'Survey not found';

      // 3) Resolve district UIC
      final allDistricts = await db.getAllDistricts();
      final d = allDistricts.firstWhere(
        (d) => d['id'] == survey['district_id'],
        orElse: () => {'district_uic': ''}
      );
      final districtUic = d['district_uic'] as String;

      // 4) Build payload
      final payload = <String, dynamic>{
        'district':   districtUic,
        'road_name':  survey['road_name'] ?? '',
        'road_length': survey['road_length'] ?? 0.0,
        'start_rd':   survey['start_rd'] ?? '',
        'end_rd':     survey['end_rd'] ?? '',
        'start_lat':  survey['start_lat'] ?? 0.0,
        'start_lon':  survey['start_lon'] ?? 0.0,
        'end_lat':    survey['end_lat'] ?? 0.0,
        'end_lon':    survey['end_lon'] ?? 0.0,
        'remark':     survey['remarks'] ?? '',
        'pcis':       <Map<String, dynamic>>[],
      };

      // 5) Load distress points
      final distressList = await db.getDistressBySurvey(surveyId);
      for (var r in distressList) {
        List<String> pics = [];
        final rawPics = r['pics'];
        if (rawPics is String && rawPics.isNotEmpty) {
          final decoded = jsonDecode(rawPics);
          if (decoded is List) pics = List<String>.from(decoded);
        } else if (rawPics is List) {
          pics = List<String>.from(rawPics);
        }

        payload['pcis'].add({
          'type':           r['type'] ?? '',
          'rd':             r['rd'] ?? '',
          'severity':       r['severity'] ?? '',
          'distress_type':  r['distress_type'] ?? '',
          'quantity':       r['quantity'] ?? 0,
          'quantity_unit':  r['quantity_unit'] ?? '',
          'latitude':       r['latitude'] ?? 0.0,
          'longitude':      r['longitude'] ?? 0.0,
          'remark':         r['remarks'] ?? '',
          'pics':           pics,
        });
      }

      // 6) POST to Django
      final url = Uri.parse('http://56.228.26.125:8000/survey/');
      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        // 7) Mark local as synced
        await db.updateSurveySynced(surveyId);
        CustomSnackbar.show(
          context,
          'Survey #$surveyId pushed successfully!',
          type: SnackbarType.success,
        );
        setState(() {
          _infoFuture = _loadUploadInfo();
        });
      } else {
        throw 'Server responded ${resp.statusCode}: ${resp.body}';
      }
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Push failed: $e',
        type: SnackbarType.error,
      );
    }
  }
}


// Helper model & loader (below your widget in same file or a separate one)
class _UploadInfo {
  final int pendingSurveys;
  final int pendingImages;
  final List<Map<String,dynamic>> readySurveys;
  _UploadInfo({
    required this.pendingSurveys,
    required this.pendingImages,
    required this.readySurveys,
  });
}

List<String> _decodePics(dynamic pics) {
  if (pics is List) return List<String>.from(pics);
  if (pics is String && pics.isNotEmpty) {
    final decoded = jsonDecode(pics);
    if (decoded is List) return List<String>.from(decoded);
  }
  return [];
}

Future<_UploadInfo> _loadUploadInfo() async {
  final db      = DatabaseHelper();
  final surveys = await db.getPciSurveysByStatus('completed');

  int pendingSurveys = 0;
  int pendingImages  = 0;
  final ready       = <Map<String, dynamic>>[];

  for (final s in surveys) {
    final state    = s['pics_state'] as String? ?? 'pending';
    final isSynced = (s['is_synced'] as int) == 1;

    if (state != 'done') pendingSurveys++;

    final distressRows = await db.getDistressBySurvey(s['id'] as int);
    for (final r in distressRows) {
      final rowState = r['pics_state'] as String? ?? 'pending';
      if (rowState != 'done') {
        final pics = _decodePics(r['pics']);
        pendingImages += pics.length;    // <-- sum each image!
      }
    }

    if (state == 'done' && !isSynced) {
      ready.add(s);
    }
  }

  return _UploadInfo(
    pendingSurveys: pendingSurveys,
    pendingImages : pendingImages,
    readySurveys  : ready,
  );
}




class SettingsTab extends StatelessWidget {
  final VoidCallback onViewData;
  final VoidCallback onViewSurveys;

  const SettingsTab({
    Key? key,
    required this.onViewData,
    required this.onViewSurveys,
  }) : super(key: key);

  Future<void> _deleteAppDatabase(BuildContext context) async {
    try {
      await DatabaseHelper().deleteDatabaseFile();
      CustomSnackbar.show(
        context,
        'Database deleted successfully.',
        type: SnackbarType.success,
      );
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Failed to delete database.',
        type: SnackbarType.error,
      );
    }
  }

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select Primary Color'),
        content: Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            _colorSwatch(context, AppColors.primary),
            _colorSwatch(context, const Color.fromARGB(255, 167, 39, 139)),
            _colorSwatch(context, const Color.fromARGB(255, 118, 24, 173)),
            _colorSwatch(context, const Color.fromARGB(255, 22, 138, 128)),
            _colorSwatch(context, const Color.fromARGB(255, 138, 117, 55)),
          ],
        ),
      ),
    );
  }

  Widget _colorSwatch(BuildContext context, Color color) {
    return GestureDetector(
      onTap: () {
        // assumes you’ve wired ThemeProvider.setPrimaryColor(...)
        context.read<ThemeProvider>().setPrimaryColor(color);
        Navigator.of(context).pop();
      },
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black12),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Data & Storage',
              style: Theme.of(context).textTheme.titleMedium),
        ),

        // View Local Data
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.folder_open, color: AppColors.info),
            title: const Text('View Local Data'),
            onTap: onViewData,
          ),
        ),

        // View Pushed Surveys
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.list_alt, color: AppColors.primary),
            title: const Text('View Pushed Surveys'),
            onTap: onViewSurveys,
          ),
        ),

        // Delete database
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.delete_forever, color: AppColors.danger),
            title: const Text('Delete Local Database'),
            // onTap: () => _deleteAppDatabase(context),
            onTap: () {
              CustomSnackbar.show(
                context,
                'You are not allowed to delete the database.',
                type: SnackbarType.warning,
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Other Settings Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('App Settings',
              style: Theme.of(context).textTheme.titleMedium),
        ),

        // Example: Toggle Dark Mode
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: Icon(Icons.palette, color: Theme.of(context).colorScheme.primary),
            title: const Text('App Primary Color'),
            subtitle: const Text('Tap to choose'),
            onTap: () => _showColorPicker(context),
          ),
        ),

        // Example: About
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.info_outline, color: AppColors.info),
            title: const Text('About'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'PCI Survey App',
                applicationVersion: '1.0.0',
                children: [const Text('© 2025 Hamood')],
              );
            },
          ),
        ),

        // Logout
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text('Logout'),
            onTap: () async {
              // 1) Remove auth token
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('auth_token');
              // 2) Clear local 'current_user' record
              await DatabaseHelper().logoutUser();
              // 3) Feedback
              CustomSnackbar.show(
                context,
                'Logged out successfully.',
                type: SnackbarType.success,
              );
              // 4) Navigate to login, wiping the back stack
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            },
          ),
        ),
      ],
    );
  }
}
