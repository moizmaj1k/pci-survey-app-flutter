import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'package:pci_survey_application/widgets/custom_snackbar.dart'; // <— Added import
import 'package:pci_survey_application/theme/theme_factory.dart';
import 'database_helper.dart';

class SurveyDashboard extends StatefulWidget {
  static const routeName = '/surveyDashboard';
  final int surveyId;

  const SurveyDashboard({Key? key, required this.surveyId}) : super(key: key);

  @override
  State<SurveyDashboard> createState() => _SurveyDashboardState();
}

class _SurveyDashboardState extends State<SurveyDashboard> {
  // Map controller to move/zoom/rotate the map
  final MapController _mapController = MapController();

  // Offline tile provider
  late final FMTCTileProvider _tileProvider;

  // Survey data loader
  late Future<Map<String, dynamic>?> _surveyFuture;

  // Track latest coordinates for recentering and distress recording
  LatLng? _currentLocation;

  // Dropdown toggle
  bool _showDropdown = false;

  // Fixed zoom level for recenter
  final double _defaultZoom = 15.0;

  // Holds any polylines/polygons parsed from the KMZ
  List<Polyline> _kmzPolylines = [];

  @override
  void initState() {
    super.initState();
    _surveyFuture = DatabaseHelper().getPciSurveyById(widget.surveyId);

    _tileProvider = FMTCTileProvider(
      stores: const {'osmCache': BrowseStoreStrategy.readUpdateCreate},
    );
  }

  Future<void> _updateCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          timeLimit: Duration(seconds: 5),
        ),
      );
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      // If permission denied or timeout, do nothing
    }
  }

  Future<void> _recenterToCurrentLocation() async {
    await _updateCurrentLocation();
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, _defaultZoom);
      _mapController.rotate(0);
    } else {
      CustomSnackbar.show(
        context,
        'Waiting for location data…',
        type: SnackbarType.info,
      );
    }
  }

  /// Shows a popup dialog allowing the user to edit “road_name” and “district”.
  /// Uses CustomSnackbar to show success / error / info messages.
  Future<void> _showEditRoadDialog(Map<String, dynamic> surveyData) async {
    // 1) Fetch all districts from the database
    List<Map<String, dynamic>> districts = [];
    try {
      districts = await DatabaseHelper().getAllDistricts();
    } catch (e) {
      // If loading districts fails, warn the user and abort
      CustomSnackbar.show(
        context,
        'Failed to load districts',
        type: SnackbarType.error,
      );
      return;
    }

    // 2) Extract current values from surveyData
    final currentName = surveyData['road_name'] as String? ?? '';
    // surveyData should have “district_id” field
    final currentDistrictId = surveyData['district_id'] as int?;

    // Controllers to hold user input
    final nameController = TextEditingController(text: currentName);
    int? selectedDistrictId = currentDistrictId;

    // A GlobalKey for form validation
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Road Details'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Road Name field
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Road Name',
                    hintText: 'Enter road name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a road name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // District dropdown
                DropdownButtonFormField<int>(
                  decoration: InputDecoration(
                    labelText: 'District',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: districts.map((d) {
                    return DropdownMenuItem<int>(
                      value: d['id'] as int,
                      child: Text(d['district_name'] as String),
                    );
                  }).toList(),
                  value: selectedDistrictId,
                  onChanged: (v) {
                    selectedDistrictId = v;
                  },
                  validator: (v) {
                    if (v == null) return 'Select a district';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            // Cancel button: warning color, slightly rounded
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.warning.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),

            // Save button: danger color, slightly rounded
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
              onPressed: () async {
                // 3) Validate
                if (!formKey.currentState!.validate()) return;

                final newName = nameController.text.trim();
                final newDistrictId = selectedDistrictId!;

                try {
                  // 4) Call the DB helper to update
                  final rowsAffected = await DatabaseHelper()
                      .updateSurveyRoadDetails(
                        widget.surveyId,
                        newName,
                        newDistrictId,
                      );

                  if (rowsAffected > 0) {
                    CustomSnackbar.show(
                      context,
                      'Road details updated successfully',
                      type: SnackbarType.success,
                    );
                    // 5) Refresh local surveyFuture so UI updates if you display these fields
                    setState(() {
                      _surveyFuture =
                          DatabaseHelper().getPciSurveyById(widget.surveyId);
                    });
                  } else {
                    CustomSnackbar.show(
                      context,
                      'No changes were made',
                      type: SnackbarType.info,
                    );
                  }
                } catch (e) {
                  CustomSnackbar.show(
                    context,
                    'Failed to update road details',
                    type: SnackbarType.error,
                  );
                }

                // 6) Close the dialog
                Navigator.of(ctx).pop();
              },
              child: Text(
                'Save',
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

  /// 1) Let the user pick a KMZ, extract KML, parse coordinates, and build polylines.
  Future<void> _pickAndPlotKmz() async {
    // 1) Launch the file picker for .kmz only
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kmz'],
    );
    if (result == null || result.files.isEmpty) {
      debugPrint('🛑 FilePicker returned null or empty.');
      return;
    }

    // 2) Read the bytes (FilePicker may give bytes or save on disk)
    Uint8List? fileBytes = result.files.single.bytes;
    if (fileBytes == null) {
      final path = result.files.single.path;
      if (path == null) {
        debugPrint('❌ Both bytes and path are null. Cannot load KMZ.');
        return;
      }
      debugPrint('ℹ️  fileBytes == null, reading from disk: $path');
      try {
        fileBytes = await File(path).readAsBytes();
      } catch (e) {
        debugPrint('❌ Error reading bytes from path: $e');
        CustomSnackbar.show(
          context,
          'Failed to load KMZ from path',
          type: SnackbarType.error,
        );
        return;
      }
    }

    if (fileBytes.isEmpty) {
      debugPrint('❌ Loaded fileBytes is empty.');
      CustomSnackbar.show(
        context,
        'The selected file is empty',
        type: SnackbarType.warning,
      );
      return;
    }

    try {
      // 3) Decode the KMZ (ZIP) in memory
      final archive = ZipDecoder().decodeBytes(fileBytes);

      // 4) Locate the first .kml entry inside
      ArchiveFile? kmlFile;
      for (final file in archive) {
        if (file.name.toLowerCase().endsWith('.kml')) {
          kmlFile = file;
          break;
        }
      }
      if (kmlFile == null) {
        debugPrint('🛑 No KML found inside the KMZ.');
        CustomSnackbar.show(
          context,
          'No KML found inside the KMZ',
          type: SnackbarType.warning,
        );
        return;
      }
      debugPrint('✅ Found KML entry: ${kmlFile.name}');

      // 5) Parse the KML XML
      final xmlString = utf8.decode(kmlFile.content as List<int>);
      final xmlDoc = XmlDocument.parse(xmlString);

      // 6) Build a list of Polylines from <LineString> and <Polygon>
      final List<Polyline> newPolylines = [];

      // 6a) Handle <LineString> (ignore any namespace prefix)
      final lineStrings =
          xmlDoc.findAllElements('LineString', namespace: '*').toList();
      debugPrint('⌛ Found ${lineStrings.length} <LineString> elements');
      for (final lineElem in lineStrings) {
        // Look for a child <coordinates> in any namespace
        final coordsElem = lineElem
            .findElements('coordinates', namespace: '*')
            .firstWhere(
              (c) => c.text.trim().isNotEmpty,
              orElse: () => XmlElement(XmlName(''), [], [], true),
            );
        if (coordsElem.name.local == '') {
          debugPrint('⚠️  <LineString> had no non-empty <coordinates>.');
          continue;
        }

        final rawCoords = coordsElem.text.trim();
        if (rawCoords.isEmpty) {
          debugPrint('⚠️  <coordinates> was empty for one <LineString>.');
          continue;
        }

        // Split by whitespace into "lon,lat[,alt]" pairs
        final coordPairs = rawCoords.split(RegExp(r'\s+'));
        final List<LatLng> points = [];
        for (final pair in coordPairs) {
          final comps = pair.split(',');
          if (comps.length < 2) continue;
          final lon = double.tryParse(comps[0]);
          final lat = double.tryParse(comps[1]);
          if (lat != null && lon != null) {
            points.add(LatLng(lat, lon));
          }
        }
        if (points.isNotEmpty) {
          newPolylines.add(
            Polyline(points: points, color: Colors.blue, strokeWidth: 3),
          );
        }
      }

      // 6b) Handle <Polygon> (outerBoundaryIs → <coordinates>), ignoring namespace
      final polygons = xmlDoc.findAllElements('Polygon', namespace: '*').toList();
      debugPrint('⌛ Found ${polygons.length} <Polygon> elements');
      for (final polyElem in polygons) {
        final coordsElem = polyElem
            .findAllElements('outerBoundaryIs', namespace: '*')
            .expand((outer) =>
                outer.findAllElements('coordinates', namespace: '*'))
            .firstWhere(
              (c) => c.text.trim().isNotEmpty,
              orElse: () => XmlElement(XmlName(''), [], [], true),
            );
        if (coordsElem.name.local == '') {
          debugPrint('⚠️  Found <Polygon> but no non-empty <coordinates>.');
          continue;
        }

        final rawCoords = coordsElem.text.trim();
        if (rawCoords.isEmpty) continue;

        final coordPairs = rawCoords.split(RegExp(r'\s+'));
        final List<LatLng> points = [];
        for (final pair in coordPairs) {
          final comps = pair.split(',');
          if (comps.length < 2) continue;
          final lon = double.tryParse(comps[0]);
          final lat = double.tryParse(comps[1]);
          if (lat != null && lon != null) {
            points.add(LatLng(lat, lon));
          }
        }
        if (points.isNotEmpty) {
          newPolylines.add(
            Polyline(
              points: [...points, points.first], // close the ring
              color: Colors.green.withAlpha((0.5 * 255).round()),
              strokeWidth: 2,
            ),
          );
        }
      }

      // 7) Debug‐print how many shapes & total points
      if (newPolylines.isEmpty) {
        debugPrint('⛔ KMZ parsing found NO polylines/polygons.');
        CustomSnackbar.show(
          context,
          'No visible geometries found in the KMZ',
          type: SnackbarType.info,
        );
      } else {
        final totalPts =
            newPolylines.fold<int>(0, (sum, pl) => sum + pl.points.length);
        debugPrint(
            '✅ KMZ parsed ${newPolylines.length} shapes, $totalPts total points.');

        // 8) Update state so the PolylineLayer re‐draws
        setState(() {
          _kmzPolylines = newPolylines;
        });

        // 9) If at least one shape was found, center the map on its first point
        final firstPoint = newPolylines.first.points.first;
        debugPrint('🔍 Centering map on first parsed point: $firstPoint');
        _mapController.move(firstPoint, 12.0);

        // 10) Show a “success” snackbar to the user
        CustomSnackbar.show(
          context,
          'KMZ successfully loaded onto the map',
          type: SnackbarType.success,
        );
      }
    } catch (e, stack) {
      debugPrint('❌ Exception while parsing KMZ: $e\n$stack');
      CustomSnackbar.show(
        context,
        'Failed to load KMZ',
        type: SnackbarType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppNavBar(title: 'PCI Survey (#${widget.surveyId})'),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _surveyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Text(
                snapshot.hasError ? 'Error: ${snapshot.error}' : 'Survey not found',
                style: const TextStyle(color: AppColors.danger),
              ),
            );
          }

          final data = snapshot.data!;
          final start = LatLng(data['start_lat'], data['start_lon']);
          final hasEnd = data['end_lat'] != null && data['end_lon'] != null;
          final end = hasEnd ? LatLng(data['end_lat'], data['end_lon']) : null;

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: start,
                  initialZoom: _defaultZoom,
                ),
                children: [
                  // 1) Offline-capable OSM tiles
                  TileLayer(
                    urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    tileProvider: _tileProvider,
                    userAgentPackageName: 'com.example.pci_survey_application',
                  ),
                  // TileLayer(
                  //   urlTemplate: 'https://stamen-tiles-{s}.a.ssl.fastly.net/toner-lite/{z}/{x}/{y}.png',
                  //   subdomains: const ['a','b','c','d'],
                  //   userAgentPackageName: 'com.example.pci_survey_application',
                  //   tileProvider: _tileProvider,
                  // ),

                  // 2) Blue location marker with heading (default behavior)
                  const CurrentLocationLayer(),

                  // 3) KML polylines (if any)
                  if (_kmzPolylines.isNotEmpty)
                    PolylineLayer(
                      polylines: _kmzPolylines,
                    ),

                  // 4) Start and end markers
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: start,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.green,
                          size: 36,
                        ),
                      ),
                      if (end != null)
                        Marker(
                          point: end,
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.flag_outlined,
                            color: Colors.red,
                            size: 36,
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // 5) Recenter button (top-right)
              Positioned(
                top: 16,
                right: 16,
                child: Column(
                  children: [
                    FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.white,
                      heroTag: 'recenterBtn',
                      onPressed: _recenterToCurrentLocation,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // 6) “Upload KMZ” button (just below recenter)
                    FloatingActionButton(
                      mini: true,
                      backgroundColor: AppColors.primary,
                      heroTag: 'uploadKmzBtn',
                      onPressed: _pickAndPlotKmz,
                      child: const Icon(
                        Icons.upload_file,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // 7) Dropdown for Edit Road Details & Complete Survey (top-left)
              Positioned(
                top: 16,
                left: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_showDropdown)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.arrow_drop_down, size: 32),
                          color: Colors.white,
                          onPressed: () {
                            setState(() {
                              _showDropdown = true;
                            });
                          },
                        ),
                      ),
                    if (_showDropdown) ...[
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 195, 146, 0),
                          minimumSize: const Size(160, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () {
                          setState(() => _showDropdown = false);
                          _showEditRoadDialog(data);
                        },
                        child: const Text(
                          'Edit Road Details',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          minimumSize: const Size(160, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: () {
                          setState(() => _showDropdown = false);
                          Navigator.pushNamed(
                            context,
                            '/completeSurvey',
                            arguments: widget.surveyId,
                          );
                        },
                        child: const Text(
                          'Complete Survey',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.arrow_drop_up, size: 32),
                          color: Colors.white,
                          onPressed: () {
                            setState(() {
                              _showDropdown = false;
                            });
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 8) Record Distress Point button (bottom-right)
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton(
                  backgroundColor: AppColors.success,
                  heroTag: 'recordDistressBtn',
                  onPressed: () async {
                    await _updateCurrentLocation();
                    if (_currentLocation != null) {
                      Navigator.pushNamed(
                        context,
                        '/recordDistress',
                        arguments: {
                          'surveyId': widget.surveyId,
                          'lat': _currentLocation!.latitude,
                          'lon': _currentLocation!.longitude,
                        },
                      );
                    } else {
                      CustomSnackbar.show(
                        context,
                        'Current location not available yet',
                        type: SnackbarType.info,
                      );
                    }
                  },
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
