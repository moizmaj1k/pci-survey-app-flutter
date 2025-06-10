// lib/screens/distress_form.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../database_helper.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/app_nav_bar.dart';
import '../theme/theme_factory.dart';
import '../theme/theme_provider.dart';

class DistressForm extends StatefulWidget {
  static const routeName = '/recordDistress';

  const DistressForm({Key? key}) : super(key: key);

  @override
  State<DistressForm> createState() => _DistressFormState();
}

class _DistressFormState extends State<DistressForm> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  // ─── Form controllers ─────────────────────────────────────────────────────
  final TextEditingController _rdController           = TextEditingController();
  final TextEditingController _quantityController     = TextEditingController();
  final TextEditingController _quantityUnitController = TextEditingController();
  final TextEditingController _remarksController      = TextEditingController();

  String? _selectedSeverity;
  String? _selectedDistressType;

  bool _initialized = false;

  // Toggle “Flexible” vs. “Rigid”
  List<bool> _isSelected = [true, false];
  String get selectedType => _isSelected[0] ? 'Flexible' : 'Rigid';

  // Dropdown options
  final List<String> _flexibleTypes = [
    'Alligator Cracking',
    'Bleeding',
    'Block Cracking',
    'Bumps & Sags',
    'Corrugation',
    'Depressions',
    'Edge Cracking',
    'Joint Reflection Cracking',
    'Lane/Shoulder Drop off',
    'Long & Trans Cracking',
    'Patching & Utility Cut Patching',
    'Polished Aggregate',
    'Potholes',
    'Railroad Crossing',
    'Rutting',
    'Showing',
    'Slippage Cracking',
    'Swell',
    'Weathering/raveling',
  ];
  final List<String> _rigidTypes = [
    'Blowup/Buckling',
    'Corner Break',
    'Divided Slab',
    'Durability (D) Cracking',
    'Faulting',
    'Joint Seal Damage',
    'Lane/Shoulder Drop Off',
    'Linear Cracking',
    'Patching, Large &  Utility Cut Patching',
    'Patching, Small',
    'Polished Aggregate',
    'Popouts',
    'Punchout',
    'Railroad Crossing',
    'Scaling, Map Cracking and Crazing',
    'Shrinkage Cracks',
    'Spalling, Corner',
    'Joint Spalling',
  ];

  // Distress type → default unit
  final Map<String, String> _unitMap = {
    'Alligator Cracking': 'sqm',
    'Bleeding': 'sqm',
    'Block Cracking': 'sqm',
    'Bumps & Sags': 'm',
    'Corrugation': 'sqm',
    'Depressions': 'sqm',
    'Edge Cracking': 'm',
    'Joint Reflection Cracking': 'm',
    'Lane/Shoulder Drop off': 'm',
    'Long & Trans Cracking': 'm',
    'Patching & Utility Cut Patching': 'sqm',
    'Polished Aggregate': 'sqm',
    'Potholes': 'No',
    'Railroad Crossing': 'sqm',
    'Rutting': 'sqm',
    'Showing': 'sqm',
    'Slippage Cracking': 'sqm',
    'Swell': 'sqm',
    'Weathering/raveling': 'sqm',
    'Blowup/Buckling': 'Nos of Slab',
    'Corner Break': 'Nos of Slab',
    'Divided Slab': 'Nos of Slab',
    'Durability (D) Cracking': 'Nos of Slabs',
    'Faulting': 'Nos of Slab',
    'Joint Seal Damage': '%',
    'Lane/Shoulder Drop Off': 'Nos of Slab',
    'Linear Cracking': 'Nos of Pieces',
    'Patching, Large &  Utility Cut Patching': 'Nos of Patches',
    'Patching, Small': 'Nos of Slabs',
    'Polished Aggregate': 'Nos of slab',
    'Popouts': 'Nos of Slabs',
    'Punchout': 'Nos of Slabs',
    'Railroad Crossing': 'Nos of slab',
    'Scaling, Map Cracking and Crazing': 'Nos of Pieces',
    'Shrinkage Cracks': 'Nos of slab',
    'Spalling, Corner': 'Nos of slab',
    'Joint Spalling': 'Nos of slab',
  };

  // ─── Shared state ────────────────────────────────────────────────────────
  bool         _isSubmitting       = false;
  bool         _isLocationRecorded = false;
  bool         _hasFormChanged     = false;
  List<String> _imagePaths         = [];

  int?         _surveyId;
  double?      _latitude;
  double?      _longitude;
  String?      _surveyName;
  bool         _surveyCompleted    = false;

  @override
  void initState() {
    super.initState();
    // All “edit vs. create” logic lives in didChangeDependencies()
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ─── Only run this block once ─────────────────────────────────────────
    if (_initialized) return;
    _initialized = true;

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    // Determine if in edit mode:
    final isEditMode = args != null && args['existingDistressData'] != null;
    if (isEditMode) {
      final existing = args!['existingDistressData'] as Map<String, dynamic>;

      // 1) Basic fields:
      _surveyId          = existing['survey_id'] as int?;
      _rdController.text = (existing['rd'] as String?) ?? '';

      final existingType = (existing['type'] as String?) ?? 'Flexible';
      _isSelected = (existingType == 'Rigid') ? [false, true] : [true, false];

      _selectedDistressType     = existing['distress_type'] as String?;
      _selectedSeverity         = existing['severity'] as String?;
      final qtyVal              = existing['quantity'] as num?;
      if (qtyVal != null) {
        _quantityController.text = qtyVal.toString();
      }
      _quantityUnitController.text = (existing['quantity_unit'] as String?) ?? '';
      _remarksController.text      = (existing['remarks'] as String?) ?? '';

      // 2) Location was already recorded—read from existing row:
      _latitude  = (existing['latitude']  as num?)?.toDouble();
      _longitude = (existing['longitude'] as num?)?.toDouble();
      if (_latitude != null && _longitude != null) {
        _isLocationRecorded = true;
      }

      // 3) Existing pics come as JSON (string or List). Decode to List<String>.
      _imagePaths = _decodePics(existing['pics']);

      // 4) Fetch surveyName so that any newly picked images can be named properly
      if (_surveyId != null) {
        DatabaseHelper()
            .getPciSurveyById(_surveyId!)
            .then((surveyMap) {
              if (surveyMap != null) {
                setState(() {
                  _surveyName = surveyMap['road_name'] as String?;
                  _surveyCompleted = (surveyMap['status'] as String?) == 'completed';
                });
              }
            })
            .catchError((_) {});
      }
    } else {
      // ─── CREATE MODE ─────────────────────────────────────────────────────────
      if (args == null ||
          args['surveyId'] == null ||
          args['lat']      == null ||
          args['lon']      == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          CustomSnackbar.show(
            context,
            'Missing survey or location data.',
            type: SnackbarType.error,
          );
          Navigator.of(context).pop();
        });
        return;
      }

      _surveyId          = args['surveyId'] as int?;
      _latitude          = (args['lat'] as num).toDouble();
      _longitude         = (args['lon'] as num).toDouble();
      _isLocationRecorded = true;

      // Fetch surveyName and completion status
      if (_surveyId != null) {
        DatabaseHelper()
            .getPciSurveyById(_surveyId!)
            .then((surveyMap) {
              if (surveyMap != null) {
                setState(() {
                  _surveyName      = surveyMap['road_name'] as String?;
                  _surveyCompleted = (surveyMap['status'] as String?) == 'completed';
                });
              }
            })
            .catchError((_) {});
      }
    }
  }

  @override
  void dispose() {
    _rdController.dispose();
    _quantityController.dispose();
    _quantityUnitController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  // ─── JSON ↔ List<String> for “pics” ──────────────────────────────────────
  List<String> _decodePics(dynamic pics) {
    if (pics is List) {
      return List<String>.from(pics);
    }
    if (pics is String && pics.isNotEmpty) {
      try {
        final decoded = jsonDecode(pics);
        if (decoded is String) {
          final doubleDecoded = jsonDecode(decoded);
          if (doubleDecoded is List) {
            return List<String>.from(doubleDecoded);
          }
        }
        if (decoded is List) {
          return List<String>.from(decoded);
        }
      } catch (e) {
        print("Error decoding JSON pics: $e");
      }
    }
    return [];
  }

  // ─── Image picking ──────────────────────────────────────────────────────
  bool _isPickingImage = false;

  Future<void> _pickImage({required ImageSource source}) async {
    // Prevent picking if survey is completed (edit mode & completed)
    if (_surveyCompleted) {
      CustomSnackbar.show(
        context,
        'Cannot add new images to a completed survey.',
        type: SnackbarType.warning,
      );
      return;
    }

    if (_isPickingImage) return;
    _isPickingImage = true;

    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        final appDir    = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final baseName  = (_surveyName ?? 'survey').replaceAll(RegExp(r'\s+'), '_');
        final latStr    = (_latitude ?? 0.0).toStringAsFixed(5);
        final lonStr    = (_longitude ?? 0.0).toStringAsFixed(5);
        final ext       = pickedFile.path.split('.').last;
        final newFileName = '${baseName}_${latStr}_${lonStr}_$timestamp.$ext';
        final destPath  = '${appDir.path}/$newFileName';

        await File(pickedFile.path).copy(destPath);

        setState(() {
          _hasFormChanged = true;
          _imagePaths.add(destPath);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e'), backgroundColor: Colors.red),
      );
    } finally {
      _isPickingImage = false;
    }
  }

  // ─── Fetch current location ──────────────────────────────────────────────
  Future<void> _getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        CustomSnackbar.show(
          context,
          'Location services are disabled. Please enable them.',
          type: SnackbarType.error,
        );
        return;
      }
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
          'Location permission permanently denied. Please enable in Settings.',
          type: SnackbarType.error,
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _isLocationRecorded = true;
        _hasFormChanged = true;
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

  // ─── Confirm discard on back press ──────────────────────────────────────
  Future<bool> _onWillPop() async {
    if (!_hasFormChanged) return true;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text(
          'If you go back now, the distress point will not be saved. Proceed?',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  // ─── INSERT mode: save new distress to DB ────────────────────────────────
  Future<void> _submitDistress() async {
    final dbHelper = DatabaseHelper();

    final rd            = _rdController.text.trim();
    final rdPattern = RegExp(r'^\d+\+\d{3}$');
    if (!rdPattern.hasMatch(rd)) {
      CustomSnackbar.show(
        context,
        'RD must be like 0+100 (any number of digits on the left, exactly 3 on the right).',
        type: SnackbarType.error,
      );
      return;
    }
    setState(() => _isSubmitting = true);
    final typeField     = selectedType;
    final distressType  = _selectedDistressType;
    final severity      = _selectedSeverity ?? '';
    final quantity      = double.tryParse(_quantityController.text.trim());
    final unit          = _quantityUnitController.text.trim();
    final remarks       = _remarksController.text.trim().isEmpty
                           ? null
                           : _remarksController.text.trim();
    final picsJson      = jsonEncode(_imagePaths);

    try {
      if (_surveyId == null) {
        throw Exception('Survey ID is missing for insert.');
      }

      final newId = await dbHelper.insertDistressPoint(
        surveyId:       _surveyId!,
        rd:             rd,
        type:           typeField,
        distressType:   distressType,
        severity:       severity.isEmpty ? null : severity,
        quantity:       quantity,
        quantityUnit:   unit.isEmpty ? null : unit,
        latitude:       _latitude!,
        longitude:      _longitude!,
        pics:           picsJson,
        remarks:        remarks,
      );

      CustomSnackbar.show(
        context,
        'Distress point #$newId saved.',
        type: SnackbarType.success,
      );
      Navigator.of(context).pop();
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Error submitting distress point: $e',
        type: SnackbarType.error,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── UPDATE mode: update existing distress by ID ─────────────────────────
  Future<void> _updateDistress() async {
    final dbHelper = DatabaseHelper();

    final rd            = _rdController.text.trim();
    // 1) pattern‐validate rd
    final rdPattern = RegExp(r'^\d+\+\d{3}$');
    if (!rdPattern.hasMatch(rd)) {
      CustomSnackbar.show(
        context,
        'RD must be like 0+100 (any digits + “+” + exactly three digits).',
        type: SnackbarType.error,
      );
      return;
    }
    setState(() => _isSubmitting = true);
    final typeField     = selectedType;
    final distressType  = _selectedDistressType;
    final severity      = _selectedSeverity ?? '';
    final quantity      = double.tryParse(_quantityController.text.trim());
    final unit          = _quantityUnitController.text.trim();
    final remarks       = _remarksController.text.trim().isEmpty
                           ? null
                           : _remarksController.text.trim();
    final picsJson      = jsonEncode(_imagePaths);

    try {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args == null || args['existingDistressData'] == null) {
        throw Exception('Missing existingDistressData for update.');
      }

      final existingId = (args['existingDistressData'] as Map<String, dynamic>)['id'] as int;

      await dbHelper.updateDistressPoint(
        id:            existingId,
        rd:            rd,
        type:          typeField,
        distressType:  distressType,
        severity:      severity.isEmpty ? null : severity,
        quantity:      quantity,
        quantityUnit:  unit.isEmpty ? null : unit,
        latitude:      _latitude!,
        longitude:     _longitude!,
        pics:          picsJson,
        remarks:       remarks,
      );

      CustomSnackbar.show(
        context,
        'Distress #$existingId updated.',
        type: SnackbarType.success,
      );
      Navigator.of(context).pop();
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Error updating distress point: $e',
        type: SnackbarType.error,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── Decide which one to call ───────────────────────────────────────────
  void _onSaveOrUpdatePressed() {
    if (!_formKey.currentState!.validate()) return;

    if (!_isLocationRecorded || _latitude == null || _longitude == null) {
      CustomSnackbar.show(
        context,
        'Please fetch the location first.',
        type: SnackbarType.warning,
      );
      return;
    }

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (_surveyCompleted && args != null && args['existingDistressData'] != null) {
      // Editing a distress for a completed survey: allow updating fields but only if at least 2 images already exist
      if (_imagePaths.length < 2) {
        CustomSnackbar.show(
          context,
          'Images cannot be changed. Ensure at least 2 existing images remain.',
          type: SnackbarType.warning,
        );
        return;
      }
      _updateDistress();
    } else {
      // Create mode or editing an incomplete survey
      if (_imagePaths.length < 2) {
        CustomSnackbar.show(
          context,
          'Please capture at least 2 images.',
          type: SnackbarType.warning,
        );
        return;
      }
      if (args != null && args['existingDistressData'] != null) {
        _updateDistress();
      } else {
        _submitDistress();
      }
    }
  }

  // ─── Track any change in the form ───────────────────────────────────────
  void _onFieldChanged() {
    if (!_hasFormChanged) {
      setState(() => _hasFormChanged = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final distressOptions =
        selectedType == 'Flexible' ? _flexibleTypes : _rigidTypes;

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final isEditMode = (args != null && args['existingDistressData'] != null);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppNavBar(
          title: isEditMode ? 'Edit Distress Point' : 'Record Distress Point',
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ChangeNotifierProvider.value(
            value: Provider.of<ThemeProvider>(context),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                onChanged: _onFieldChanged,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ─── Toggle “Flexible” vs. “Rigid” ─────────────────
                    Center(
                      child: ToggleButtons(
                        isSelected: _isSelected,
                        borderRadius: BorderRadius.circular(8),
                        borderColor: Theme.of(context).colorScheme.primary,
                        selectedBorderColor: Theme.of(context).colorScheme.primary,
                        borderWidth: 2.0,
                        fillColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        selectedColor: Theme.of(context).colorScheme.primary,
                        color: Theme.of(context).colorScheme.onSurface,
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32.0),
                            child: Text('Flexible'),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 44.0),
                            child: Text('Rigid'),
                          ),
                        ],
                        onPressed: (index) {
                          setState(() {
                            for (int i = 0; i < _isSelected.length; i++) {
                              _isSelected[i] = (i == index);
                            }
                            _selectedDistressType = null;
                            _quantityUnitController.text = '';
                            _onFieldChanged();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ─── Details Section ───────────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),

                    // RD + Type (read-only) ────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _rdController,
                            decoration: const InputDecoration(
                              labelText: 'RD',
                              hintText: 'e.g. 0+100',
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter RD';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Opacity(
                            opacity: 0.6,
                            child: TextFormField(
                              controller: TextEditingController(text: selectedType),
                              decoration: const InputDecoration(
                                labelText: 'Type',
                                border: OutlineInputBorder(),
                              ),
                              readOnly: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Distress-Type dropdown ──────────────────────────
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: '$selectedType Distress Type',
                        border: const OutlineInputBorder(),
                      ),
                      items: distressOptions.map((dt) => DropdownMenuItem<String>(
                            value: dt,
                            child: Text(dt),
                          )).toList(),
                      value: _selectedDistressType,
                      onChanged: (val) {
                        setState(() {
                          _selectedDistressType = val;
                          if (val != null && _unitMap.containsKey(val)) {
                            _quantityUnitController.text = _unitMap[val]!;
                          } else {
                            _quantityUnitController.text = '';
                          }
                          _onFieldChanged();
                        });
                      },
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Select distress type';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Severity dropdown ──────────────────────────────
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Severity',
                        border: OutlineInputBorder(),
                      ),
                      items: <String>['Low', 'Medium', 'High']
                          .map((sev) => DropdownMenuItem<String>(
                                value: sev,
                                child: Text(sev),
                              ))
                          .toList(),
                      value: _selectedSeverity,
                      onChanged: (val) {
                        setState(() {
                          _selectedSeverity = val;
                          _onFieldChanged();
                        });
                      },
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Select severity';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Quantity + Unit ───────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _quantityController,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              border: OutlineInputBorder(),
                              hintText: 'e.g. 10.5',
                            ),
                            onChanged: (_) => _onFieldChanged(),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Please enter quantity';
                              }
                              final parsed = double.tryParse(val.trim());
                              if (parsed == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: Opacity(
                            opacity: 0.6,
                            child: TextFormField(
                              controller: _quantityUnitController,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                                border: OutlineInputBorder(),
                              ),
                              readOnly: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ─── Location Section ──────────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'Location',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          height: 40,
                          width: 40,
                          child: FloatingActionButton(
                            heroTag: 'fetchLocationBtn',
                            onPressed: isEditMode
                                ? () {
                                    CustomSnackbar.show(
                                      context,
                                      'You can only record location for a distress once.',
                                      type: SnackbarType.warning,
                                    );
                                  }
                                : _getCurrentLocation,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            shape: CircleBorder(
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.my_location,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isLocationRecorded && _latitude != null && _longitude != null
                                  ? '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                                  : 'No location recorded',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ─── Images Section ──────────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'Images',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(
                              Icons.camera_alt,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            label: Text(
                              'Camera',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.primary,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => _pickImage(source: ImageSource.camera),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(
                              Icons.photo_library,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            label: Text(
                              'Gallery',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.primary,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => _pickImage(source: ImageSource.gallery),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Inline image preview ──────────────────────────
                    if (_imagePaths.isNotEmpty)
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _imagePaths.length,
                          itemBuilder: (context, index) {
                            final path = _imagePaths[index];
                            final isExistingImage = (args != null &&
                                args['existingDistressData'] != null &&
                                _decodePics(
                                  (args['existingDistressData'] as Map<String, dynamic>)['pics'],
                                ).contains(path));

                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: GestureDetector(
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => Dialog(
                                            child: GestureDetector(
                                              onTap: () => Navigator.of(context).pop(),
                                              child: InteractiveViewer(
                                                child: Image.file(File(path)),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                      child: Image.file(
                                        File(path),
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  if (!isExistingImage && !_surveyCompleted)
                                    Positioned(
                                      top: -4,
                                      right: -4,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _imagePaths.remove(path);
                                            _onFieldChanged();
                                          });
                                        },
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 2,
                                                offset: Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 18,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Icon(
                                        Icons.lock_outline,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 24),

                    // ─── Remarks ───────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'Additional Notes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: _remarksController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Enter Remarks (optional)…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onChanged: (_) => _onFieldChanged(),
                    ),
                    const SizedBox(height: 24),

                    // ─── Save / Update Button ──────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _onSaveOrUpdatePressed,
                        style: ElevatedButton.styleFrom(
                          // Use warning color if editing; otherwise use success for “Save”
                          backgroundColor: isEditMode
                              ? AppColors.warning   // ← change for “Update”
                              : AppColors.success,  // ← original “Save” color
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isEditMode
                                    ? 'Update Distress Point'
                                    : 'Save Distress Point',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isEditMode ? Colors.black : Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
