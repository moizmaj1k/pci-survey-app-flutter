// lib/dashboard_screen.dart
import 'dart:async';
import 'package:pci_survey_application/survey_dashboard.dart';
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
                                  const Icon(Icons.map, size: 48, color: AppColors.primary),
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

    // Capture the screen context for the snackbar:
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
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newDistrictId == null) return;

              // Close the dialog first
              Navigator.of(dialogContext).pop();

              // Show loading state
              setState(() => _loading = true);

              // Perform the update
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

              // Update local state
              setState(() {
                _districtId = newDistrictId;
                _loading = false;
              });

              // Tell parent to refetch
              widget.onRegistered();

              // Finally, show success
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
    if (!_formKey.currentState!.validate()) return;
    if (_startLat == null || _startLon == null) {
      CustomSnackbar.show(
        context,
        'Please tap "Get Location" first',
        type: SnackbarType.warning,
      );
      return;
    }

    setState(() => _loading = true);
    final userId = await DatabaseHelper().getCurrentUserId() ?? 0;
    try {
      final newId = await DatabaseHelper().insertPciSurvey(
        districtId: _selectedDistrictId!,
        roadName: _roadNameCtrl.text.trim(),
        startRd: _startRdCtrl.text.trim(),
        startLat: _startLat!,
        startLon: _startLon!,
        createdBy: userId,
      );
      CustomSnackbar.show(
        context,
        'Survey #$newId started',
        type: SnackbarType.success,
      );

      // ← only pass the surveyId
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
                      const Icon(Icons.info, size: 48, color: AppColors.primary),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter start RD' : null,
            ),

            const SizedBox(height: 12),

            // ─── Get Location Button & Display ───────────────
            Row(children: [
              ElevatedButton.icon(
                onPressed: _fetchLocation,
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Get Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
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
