// lib/screens/distress_form.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database_helper.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/app_nav_bar.dart';
import '../theme/theme_factory.dart';
import '../theme/theme_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';


class DistressForm extends StatefulWidget {
  static const routeName = '/recordDistress';

  const DistressForm({Key? key}) : super(key: key);

  @override
  State<DistressForm> createState() => _DistressFormState();
}

class _DistressFormState extends State<DistressForm> {
  final _formKey = GlobalKey<FormState>();
  final List<File> _images = [];
  final ImagePicker _picker = ImagePicker();

  // Controllers for RD, Quantity, and Unit fields
  final TextEditingController _rdController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _quantityUnitController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();


  String? _selectedSeverity;
  bool _isSubmitting = false;

  late int _surveyId;
  late double _latitude;
  late double _longitude;
  double? _fetchedLat;
  double? _fetchedLon;

  // Toggle state: index 0 = Flexible, index 1 = Rigid
  List<bool> _isSelected = [true, false];
  String get selectedType => _isSelected[0] ? 'Flexible' : 'Rigid';
  String? _surveyName;

  bool _hasFormChanged = false;

  // Lists of distress types
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

  String? _selectedDistressType; // for dropdown

  // Map distress type → default unit
  final Map<String, String> _unitMap = {
    // Flexible units
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

    // Rigid units
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (args == null ||
        args['surveyId'] == null ||
        args['lat'] == null ||
        args['lon'] == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CustomSnackbar.show(
          context,
          'Missing survey data.',
          type: SnackbarType.error,
        );
        Navigator.of(context).pop();
      });
      return;
    }

    _surveyId = args['surveyId'] as int;
    _latitude = args['lat'] as double;
    _longitude = args['lon'] as double;

    // Fetch the survey row so we can grab its name:
    DatabaseHelper()
        .getPciSurveyById(_surveyId)
        .then((surveyMap) {
          if (surveyMap != null && surveyMap['road_name'] != null) {
            setState(() {
              _surveyName = surveyMap['road_name'] as String;
            });
          }
        })
        .catchError((_) {
          // If it fails, we’ll just leave _surveyName null and fall back to timestamp alone.
        });
  }

  @override
  void dispose() {
    _rdController.dispose();
    _quantityController.dispose();
    _quantityUnitController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  /// Pick a new image from the camera, save it locally using
  /// "{surveyName}_{lat}_{lon}_{timestamp}.jpg", and add to _images.
  Future<void> _pickFromCamera() async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Sanitize surveyName (replace spaces with underscores)
      final baseName = (_surveyName ?? 'survey')
          .replaceAll(RegExp(r'\s+'), '_');

      final latStr = _latitude.toStringAsFixed(5);
      final lonStr = _longitude.toStringAsFixed(5);

      final fileName =
          '${baseName}_${latStr}_${lonStr}_$timestamp.jpg';

      final savedFile = await File(picked.path)
          .copy('${appDir.path}/$fileName');

      setState(() {
        _images.add(savedFile);
        _hasFormChanged = true;
      });

      CustomSnackbar.show(
        context,
        'Photo saved.',
        type: SnackbarType.success,
      );
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Failed to capture photo.',
        type: SnackbarType.error,
      );
    }
  }

  /// Pick one or more images from the gallery, save locally using
  /// "{surveyName}_{lat}_{lon}_{timestamp}.jpg", and add to _images.
  Future<void> _pickFromGallery() async {
    try {
      final List<XFile>? pickedList =
          await _picker.pickMultiImage(imageQuality: 85);
      if (pickedList == null || pickedList.isEmpty) return;

      final appDir = await getApplicationDocumentsDirectory();
      final latStr = _latitude.toStringAsFixed(5);
      final lonStr = _longitude.toStringAsFixed(5);
      final baseName = (_surveyName ?? 'survey')
          .replaceAll(RegExp(r'\s+'), '_');

      for (final XFile picked in pickedList) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName =
            '${baseName}_${latStr}_${lonStr}_$timestamp.jpg';

        final savedFile = await File(picked.path)
            .copy('${appDir.path}/$fileName');
        _images.add(savedFile);
        // Delay slightly so that timestamps differ if multiple picks happen very fast:
        await Future.delayed(const Duration(milliseconds: 50));
      }

      setState(() {
        _hasFormChanged = true;
      });

      CustomSnackbar.show(
        context,
        '${pickedList.length} image(s) added.',
        type: SnackbarType.success,
      );
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Failed to select images.',
        type: SnackbarType.error,
      );
    }
  }


  Future<void> _fetchLocation() async {
    try {
      // 1. Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        CustomSnackbar.show(
          context,
          'Location services are disabled. Please enable them.',
          type: SnackbarType.error,
        );
        return;
      }

      // 2. Check/request permission
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

      // 3. Fetch high‐accuracy location
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _fetchedLat = pos.latitude;
        _fetchedLon = pos.longitude;
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

  Future<bool> _onWillPop() async {
    if (_hasFormChanged) {
      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Discard Changes?'),
            content: const Text(
              'If you go back now, the distress point will not be saved. Proceed?',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    // Less rounded, gently curved edges
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    // Less rounded, gently curved edges
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Yes'),
              ),
            ],
          );
        },
      );
      return shouldLeave ?? false;
    }
    return true;
  }

  Future<void> _submitDistress() async {
    if (!_formKey.currentState!.validate()) return;

    // 2a) Ensure we’ve fetched a location before submitting
    if (_fetchedLat == null || _fetchedLon == null) {
      CustomSnackbar.show(
        context,
        'Please fetch the location first.',
        type: SnackbarType.warning,
      );
      return;
    }

    // 2b) Ensure at least 2 images have been captured
    if (_images.length < 2) {
      CustomSnackbar.show(
        context,
        'Please capture at least 2 images.',
        type: SnackbarType.warning,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final String rd = _rdController.text.trim();
    final String typeField = selectedType;
    final String? distressType = _selectedDistressType;
    final String severity = _selectedSeverity ?? '';
    final double? quantity = double.tryParse(_quantityController.text.trim());
    final String quantityUnit = _quantityUnitController.text.trim();
    final String? remarks = _remarksController.text.trim().isEmpty
        ? null
        : _remarksController.text.trim();

    // Build a comma-separated list of file paths for pics
    String? pics;
    if (_images.isNotEmpty) {
      pics = _images.map((file) => file.path).join(',');
    }

    try {
      final int newId = await DatabaseHelper().insertDistressPoint(
        surveyId: _surveyId,
        rd: rd,
        type: typeField,
        distressType: distressType,
        severity: severity.isEmpty ? null : severity,
        quantity: quantity,
        quantityUnit: quantityUnit.isEmpty ? null : quantityUnit,
        latitude: _fetchedLat!,
        longitude: _fetchedLon!,
        pics: pics,
        remarks: remarks,
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
        'Failed to save distress point.',
        type: SnackbarType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
    
  void _onFieldChanged() {
    if (!_hasFormChanged) {
      setState(() {
        _hasFormChanged = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final distressOptions =
        selectedType == 'Flexible' ? _flexibleTypes : _rigidTypes;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: const AppNavBar(title: 'Record Distress Point'),
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
                    // Toggle between Flexible and Rigid with bold border & bold text
                    Center(
                      child: ToggleButtons(
                        isSelected: _isSelected,
                        borderRadius: BorderRadius.circular(8),
                        borderColor: Theme.of(context).colorScheme.primary,
                        selectedBorderColor:
                            Theme.of(context).colorScheme.primary,
                        borderWidth: 2.0,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.2),
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
                            _selectedDistressType = null; // reset dropdown
                            _quantityUnitController.text = ''; // reset unit
                            _onFieldChanged();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
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
                    // RD and Type in same row
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _rdController,
                            decoration: const InputDecoration(
                              labelText: 'RD',
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
                              controller:
                                  TextEditingController(text: selectedType),
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

                    // Distress Type dropdown (dynamic + set unit on change)
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: '$selectedType Distress Type',
                        border: const OutlineInputBorder(),
                      ),
                      items: distressOptions
                          .map((dt) => DropdownMenuItem<String>(
                                value: dt,
                                child: Text(dt),
                              ))
                          .toList(),
                      value: _selectedDistressType,
                      onChanged: (val) {
                        setState(() {
                          _selectedDistressType = val;
                          // Auto-fill unit based on selected distress type
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

                    // Severity dropdown
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

                    // Quantity and Unit in same row
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

                    // ─── Location Button + Display Box ───────────────────────
                    Row(
                      children: [
                        // Location icon button
                        SizedBox(
                          height: 40,
                          width: 40,
                          child: FloatingActionButton(
                            heroTag: 'fetchLocationBtn',
                            onPressed: _fetchLocation,
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

                        // Box showing fetched coordinates (or hint text)
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
                              _fetchedLat != null && _fetchedLon != null
                                  ? '${_fetchedLat!.toStringAsFixed(5)}, '
                                    '${_fetchedLon!.toStringAsFixed(5)}'
                                  : 'No location fetched',
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

                    // Camera & Gallery buttons (outlined, bold text)
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
                                width: 2, // thicker border
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _pickFromCamera,
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
                                width: 2, // thicker border
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _pickFromGallery,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Horizontal list of stored images (if any)
                    if (_images.isNotEmpty)
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          itemBuilder: (context, index) {
                            final file = _images[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: GestureDetector(
                                onTap: () {
                                  // Show full‐screen preview in a dialog
                                  showDialog(
                                    context: context,
                                    builder: (_) => Dialog(
                                      child: GestureDetector(
                                        onTap: () => Navigator.of(context).pop(),
                                        child: InteractiveViewer(
                                          child: Image.file(file),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.file(
                                    file,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 24),

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
                    const SizedBox(height: 8),

                    // ─── “Remarks” Text Area ────────────────────────────────
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

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitDistress,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
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
                            : const Text(
                              'Save Distress Point',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
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
