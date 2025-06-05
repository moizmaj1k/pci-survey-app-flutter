import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:pci_survey_application/distress_form.dart';
import 'package:xml/xml.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'package:pci_survey_application/widgets/custom_snackbar.dart'; // <— Added import
import 'package:pci_survey_application/theme/theme_factory.dart';
import 'database_helper.dart';
import 'package:http/io_client.dart';


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

  // We'll keep one HTTP client around and hand‐construct an FMTCTileProvider per‐layer:
  late final IOClient _httpClient;
  late final FMTCTileProvider _osmProvider;
  late final FMTCTileProvider _topoProvider;
  late final FMTCTileProvider _esriProvider;
  // during testing only:
  // late final TileProvider _tileProvider;


  final List<Map<String, String>> _baseLayers = [
    {
      'name'      : 'OSM Standard',
      'url'       : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      'subdomains': 'a,b,c',
      'provider'  : 'osm',
    },
    {
      'name'      : 'OpenTopoMap',
      'url'       : 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
      'subdomains': '',
      'provider'  : 'topo',
    },
    {
      'name'      : 'Satellite (Esri)',
      'url'       : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'subdomains': '',
      'provider'  : 'esri',
    },
  ];



  int _currentBaseLayerIndex = 0;

  // Survey data loader
  late Future<Map<String, dynamic>?> _surveyFuture;
  late Future<List<Map<String, dynamic>>> _distressFuture;

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

    // 1) Create a single IOClient for HTTP (reuse it for all providers):
    final httpClient = IOClient();

    // 2) Make one provider *per* store. Each provider only points at its single cache store:
    _osmProvider = FMTCTileProvider(
      stores: const { 'osmCache':   BrowseStoreStrategy.readUpdateCreate },
      loadingStrategy: BrowseLoadingStrategy.cacheFirst,
      httpClient: httpClient,
    );

    _topoProvider = FMTCTileProvider(
      stores: const { 'topoCache':  BrowseStoreStrategy.readUpdateCreate },
      loadingStrategy: BrowseLoadingStrategy.cacheFirst,
      httpClient: httpClient,
    );

    _esriProvider = FMTCTileProvider(
      stores: const { 'esriCache':  BrowseStoreStrategy.readUpdateCreate },
      loadingStrategy: BrowseLoadingStrategy.cacheFirst,
      httpClient: httpClient,
    );

    _surveyFuture = DatabaseHelper().getPciSurveyById(widget.surveyId);
    _distressFuture = DatabaseHelper().getDistressBySurvey(widget.surveyId);
  }

  Future<void> _showDistressListSheet(bool isCompleted) async {
    final rawRows = await DatabaseHelper().getDistressBySurvey(widget.surveyId);

    // Make a mutable copy:
    final distressRows = List<Map<String, dynamic>>.from(rawRows);

    distressRows.sort((a, b) {
      final tsa = DateTime.tryParse(a['recorded_at'] as String? ?? '') 
                  ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tsb = DateTime.tryParse(b['recorded_at'] as String? ?? '') 
                  ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tsb.compareTo(tsa);
    });

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (ctx, scrollCtr) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).canvasColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Container(
                      width: 50,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'All Distress Points',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtr,
                      itemCount: distressRows.length,
                      itemBuilder: (ctx, idx) {
                        final row = distressRows[idx];
                        final id = row['id'] as int;
                        final type = row['type'] as String? ?? '—';
                        final distressType = row['distress_type'] as String? ?? '—';
                        final recordedAt = row['recorded_at'] as String? ?? '—';

                        return ListTile(
                          title: Row(
                            children: [
                              // 1) Colored box for the "type" label
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: type == 'Rigid'
                                      ? AppColors.danger           // theme danger background
                                      : AppColors.warning,         // theme warning background
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  type,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    // If Rigid → white text; if Flexible → black text
                                    color: type == 'Rigid'
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 8),

                              // 2) Then show the distressType text
                              Expanded(
                                child: Text(
                                  distressType,
                                  style: const TextStyle(fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),

                          subtitle: Text(
                            DateTime.tryParse(recordedAt) != null
                                ? '${DateTime.parse(recordedAt).toLocal()}'
                                : recordedAt,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Edit icon
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.orange),
                                onPressed: () async {
                                  Navigator.of(ctx).pop(); // close sheet
                                  // Load full row, then push DistressForm in edit mode
                                  final fullRow = await DatabaseHelper()
                                      .getDistressPointById(id);
                                  if (fullRow != null) {
                                    await Navigator.pushNamed(
                                      context,
                                      DistressForm.routeName,
                                      arguments: {
                                        'existingDistressData': fullRow,
                                      },
                                    );
                                    setState(() {
                                      _distressFuture = DatabaseHelper()
                                          .getDistressBySurvey(widget.surveyId);
                                    });
                                  } else {
                                    CustomSnackbar.show(
                                      context,
                                      'Distress no longer exists.',
                                      type: SnackbarType.error,
                                    );
                                  }
                                },
                              ),

                              // Delete icon
                              if (!isCompleted)
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    // Remove from database, then refresh and rebuild
                                    await DatabaseHelper().deleteDistressPoint(id);
                                    setState(() {
                                      _distressFuture = DatabaseHelper()
                                          .getDistressBySurvey(widget.surveyId);
                                    });
                                    CustomSnackbar.show(
                                      context,
                                      'Distress #$id deleted.',
                                      type: SnackbarType.success,
                                    );
                                  },
                                ),
                            ],
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
      },
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
  Future<void> _showEditRoadDialog(
    Map<String, dynamic> surveyData,
    bool isCompleted,
  ) async {
    // 1) Fetch all districts from the database
    List<Map<String, dynamic>> districts = [];
    try {
      districts = await DatabaseHelper().getAllDistricts();
    } catch (e) {
      CustomSnackbar.show(
        context,
        'Failed to load districts',
        type: SnackbarType.error,
      );
      return;
    }

    // 2) Extract current values from surveyData
    final currentName       = surveyData['road_name']   as String? ?? '';
    final currentDistrictId = surveyData['district_id'] as int?;

    // Always‐present fields:
    final currentStartRd  = surveyData['start_rd'] as String? ?? '';
    final currentRemarks  = surveyData['remarks']  as String? ?? '';

    // If the survey is already completed, also extract end_rd and road_length
    String  currentEndRd   = '';
    double currentRoadLen  = 0.0;
    if (isCompleted) {
      currentEndRd  = surveyData['end_rd']      as String? ?? '';
      final num? lenNum = surveyData['road_length'] as num?;
      if (lenNum != null) currentRoadLen = lenNum.toDouble();
    }

    // 3) Controllers for user input
    final nameController      = TextEditingController(text: currentName);
    int? selectedDistrictId   = currentDistrictId;

    final startRdController   = TextEditingController(text: currentStartRd);
    final remarksController   = TextEditingController(text: currentRemarks);

    // Controllers for completed‐survey fields:
    final endRdController     = TextEditingController(
      text: isCompleted ? currentEndRd : '',
    );
    final roadLenController   = TextEditingController(
      text: isCompleted && currentRoadLen > 0.0
          ? currentRoadLen.toString()
          : '',
    );

    // 4) Form validation key
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Road Details'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ─── Road Name ──────────────────────────────────────
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

                  // ─── District ───────────────────────────────────────
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
                  const SizedBox(height: 12),

                  // ─── Start Rd ───────────────────────────────────────
                  TextFormField(
                    controller: startRdController,
                    decoration: const InputDecoration(
                      labelText: 'Start Rd',
                      hintText: 'Enter start road',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter the start road';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // ─── If completed: End Rd & Road Length ─────────────
                  if (isCompleted) ...[
                    TextFormField(
                      controller: endRdController,
                      decoration: const InputDecoration(
                        labelText: 'End Rd',
                        hintText: 'Enter end road',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter the end road';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: roadLenController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Road Length (e.g. 1.23 km)',
                        hintText: 'Enter numeric length',
                        border: OutlineInputBorder(),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter the road length';
                        }
                        final parsed = double.tryParse(val.trim());
                        if (parsed == null) {
                          return 'Must be a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ─── Remarks ─────────────────────────────────────────
                  TextFormField(
                    controller: remarksController,
                    decoration: const InputDecoration(
                      labelText: 'Remarks',
                      hintText: 'Optional comments',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            // ─── Cancel Button ───────────────────────────────────
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

            // ─── Save Button ─────────────────────────────────────
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
              onPressed: () async {
                // 1) Validate required fields first
                if (!formKey.currentState!.validate()) return;

                // 2) Gather all inputs
                final newName       = nameController.text.trim();
                final newDistrictId = selectedDistrictId!;
                final newStartRd    = startRdController.text.trim();
                final newRemarks    = remarksController.text.trim();

                try {
                  // 3) Update the core columns
                  final rowsAffected = await DatabaseHelper().updateSurveyRoadDetails(
                    widget.surveyId,
                    newName,
                    newDistrictId,
                    newStartRd,
                    newRemarks,
                  );

                  // 4) If survey was already marked completed, also update the two extra fields
                  if (isCompleted && rowsAffected > 0) {
                    final newEndRd   = endRdController.text.trim();
                    final newRoadLen = double.parse(roadLenController.text.trim());

                    // This helper should update only end_rd and road_length for a completed survey.
                    await DatabaseHelper().updateSurveyCompletionFields(
                      surveyId:   widget.surveyId,
                      endRd:      newEndRd,
                      roadLength: newRoadLen,
                    );
                  }

                  if (rowsAffected > 0) {
                    CustomSnackbar.show(
                      context,
                      'Road details updated successfully',
                      type: SnackbarType.success,
                    );
                    setState(() {
                      _surveyFuture = DatabaseHelper().getPciSurveyById(widget.surveyId);
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

                // 5) Close the dialog
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
            Polyline(points: points, color: const Color.fromARGB(255, 150, 20, 33), strokeWidth: 4),
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

  // ───────────────────────────────────────────────────────────────────────────
  // This dialog asks the user to “complete” the survey.
  // It warns that no further distress points can be added once completed.
  // It lets them fill in: end_rd, road_length, end_lat, end_lon, remarks.
  // Autofill end_lat/ end_lon from current location if permission is granted.
  // Validate everything; then call DatabaseHelper.updateSurveyCompletion(...).
  // Finally, pop back to Dashboard’s “View” tab.
  //
  // Expects `surveyData` to come from the top‐level FutureBuilder (it contains
  // the existing “remarks”, “end_rd”, “road_length”, “end_lat”, “end_lon”
  // if they’re already partially filled).
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _showCompleteSurveyDialog(Map<String, dynamic> surveyData) async {
    // 1) Extract any existing values (so we can pre‐fill “End Rd” and “Road Length”,
    //    and “Remarks” if they were already set). We drop end_lat/end_lon fields.
    final existingEndRd   = surveyData['end_rd'] as String? ?? '';
    final existingRoadLen = (surveyData['road_length'] != null)
        ? (surveyData['road_length'] as num).toDouble()
        : 0.0;
    final existingRemarks = surveyData['remarks'] as String? ?? '';

    // 2) Controllers for the form fields:
    final endRdController   = TextEditingController(text: existingEndRd);
    final roadLenController = TextEditingController(
      text: existingRoadLen > 0.0 ? existingRoadLen.toString() : '',
    );
    final remarksController = TextEditingController(text: existingRemarks);

    // 3) We'll keep two local variables (not editable) for the fetched end-lat/lon.
    double? endLatValue;
    double? endLonValue;

    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // We need a local setState to update endLatValue/endLonValue inside the dialog.
        return StatefulBuilder(
          builder: (ctx2, setStateDialog) {
            return AlertDialog(
              title: const Text('Complete Survey'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ─── Warning Text ────────────────────────────────────
                      const Text(
                        'Once you complete this survey, you will no longer be able to '
                        'record additional distress points for it.',
                        style: TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 12),

                      // ─── End Rd ──────────────────────────────────────────
                      TextFormField(
                        controller: endRdController,
                        decoration: const InputDecoration(
                          labelText: 'End Rd',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter an end road';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // ─── Road Length ─────────────────────────────────────
                      TextFormField(
                        controller: roadLenController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Road Length (e.g. 1.23 km)',
                          hintText: 'Enter numeric length',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter road length';
                          }
                          final parsed = double.tryParse(val.trim());
                          if (parsed == null) {
                            return 'Must be a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // ─── Autofill End Location ───────────────────────────
                      ElevatedButton.icon(
                        icon: const Icon(Icons.my_location),
                        label: const Text('Autofill End Location'),
                        onPressed: () async {
                          try {
                            final pos = await Geolocator.getCurrentPosition(
                              locationSettings: const LocationSettings(
                                accuracy: LocationAccuracy.high,
                                timeLimit: Duration(seconds: 5),
                              ),
                            );
                            setStateDialog(() {
                              endLatValue = pos.latitude;
                              endLonValue = pos.longitude;
                            });
                          } catch (_) {
                            CustomSnackbar.show(
                              context,
                              'Unable to fetch current location',
                              type: SnackbarType.error,
                            );
                          }
                        },
                      ),

                      // ─── Display the fetched coordinates (read-only) ──────
                      if (endLatValue != null && endLonValue != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'End Latitude: ${endLatValue!.toStringAsFixed(6)}\n'
                          'End Longitude: ${endLonValue!.toStringAsFixed(6)}',
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 12),

                      // ─── Remarks ──────────────────────────────────────────
                      TextFormField(
                        controller: remarksController,
                        decoration: const InputDecoration(
                          labelText: 'Remarks',
                          hintText: 'Optional comments',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),

              actions: [
                // ─── Cancel Button ───────────────────────────────────
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success, // success background
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(ctx2).pop(); // just close the dialog
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white),
                  ),
                ),

                // ─── Complete Button ─────────────────────────────────
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger, // danger background
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    // 1) Validate required fields first
                    if (!formKey.currentState!.validate()) return;

                    // 2) Ensure we have a fetched end location
                    if (endLatValue == null || endLonValue == null) {
                      CustomSnackbar.show(
                        context,
                        'Please autofill end location before completing.',
                        type: SnackbarType.error,
                      );
                      return;
                    }

                    // 3) Parse the other fields
                    final endRdText   = endRdController.text.trim();
                    final roadLenVal  = double.parse(roadLenController.text.trim());
                    final latVal      = endLatValue!;
                    final lonVal      = endLonValue!;
                    final remarksText = remarksController.text.trim();

                    try {
                      // 4) Call DB helper so it updates end_rd, road_length,
                      //    end_lat, end_lon, remarks, and status='completed'
                      final rowsUpdated =
                          await DatabaseHelper().updateSurveyCompletion(
                        surveyId   : widget.surveyId,
                        endRd      : endRdText,
                        roadLength : roadLenVal,
                        endLat     : latVal,
                        endLon     : lonVal,
                        remarks    : remarksText,
                      );

                      if (rowsUpdated > 0) {
                        CustomSnackbar.show(
                          context,
                          'Survey marked as completed.',
                          type: SnackbarType.success,
                        );
                        Navigator.of(ctx2).pop(); // close dialog

                        // 5) Pop back to the Dashboard’s home tab
                        //    (i.e. route '/dashboard' is assumed to show home by default)
                        Navigator.of(context).popUntil((route) {
                          return route.settings.name == '/dashboard';
                        });
                      } else {
                        CustomSnackbar.show(
                          context,
                          'Failed to complete survey (no rows updated).',
                          type: SnackbarType.error,
                        );
                      }
                    } catch (e) {
                      CustomSnackbar.show(
                        context,
                        'Error completing survey: $e',
                        type: SnackbarType.error,
                      );
                    }
                  },
                  child: const Text(
                    'Complete',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }


  Widget _buildFlutterMap(
  Map<String, dynamic> data,
  LatLng start,
  LatLng? end,
  List<Marker> distressMarkers,
  bool isCompleted,
) {
  // Build subdomain list from our Map<String, String> entry:
  final parts = _baseLayers[_currentBaseLayerIndex]['subdomains']!.split(',');
  final subdomainList = parts.where((s) => s.isNotEmpty).toList();
  final providerToUse = switch (_baseLayers[_currentBaseLayerIndex]['provider']) {
    'osm'  => _osmProvider,
    'topo' => _topoProvider,
    'esri' => _esriProvider,
    _      => _osmProvider,
  };

  return Stack(
    children: [
      FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: start,
          initialZoom: _defaultZoom,
        ),
        children: [
            TileLayer(
              key: ValueKey(_currentBaseLayerIndex),

              // 1) URL template & subdomains exactly as before:
              urlTemplate: _baseLayers[_currentBaseLayerIndex]['url']!,
              subdomains: subdomainList,

              // 2) Pass in the *correct* FMTCTileProvider for this layer:
              tileProvider: providerToUse,

              // 3) (NO more `store:` parameter—tileProvider already knows its store)
              userAgentPackageName: 'com.example.pci_survey_application',
            ),

          // TileLayer(
          //   key: ValueKey(_currentBaseLayerIndex),
          //   urlTemplate: _baseLayers[_currentBaseLayerIndex]['url']!,
          //   subdomains: subdomainList,
          //   // tileProvider: _tileProvider,  // now just NetworkTileProvider()
          //   userAgentPackageName: 'com.example.pci_survey_application',
          // ),
          // 2) Blue location marker with heading (default behavior)
          const CurrentLocationLayer(),
          // 3) KML polylines (if any)
          if (_kmzPolylines.isNotEmpty)
            PolylineLayer(polylines: _kmzPolylines),
          // 4) Start, end, and distress markers
          MarkerLayer(
            markers: [
              // Start marker without circular border, just an icon with shadow
              Marker(
                point: start,
                width: 48,
                height: 48,
                child: const Icon(
                  Icons.flag,
                  color: Colors.green,
                  size: 36,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 4,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),

              if (end != null)
                // End marker without circular border, just an icon with shadow
                Marker(
                  point: end,
                  width: 48,
                  height: 48,
                  child: const Icon(
                    Icons.flag,
                    color: Colors.red,
                    size: 36,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),

              ...distressMarkers,
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
              backgroundColor: Theme.of(context).colorScheme.surface,
              heroTag: 'recenterBtn',
              onPressed: _recenterToCurrentLocation,
              child: Icon(
                Icons.my_location,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            // c) Start‐flag recenter button
            FloatingActionButton(
              mini: true,
              backgroundColor: Theme.of(context).colorScheme.surface,
              heroTag: 'recenterStartBtn',
              onPressed: () {
                // Always recenter to the survey's start point
                _mapController.move(start, _defaultZoom);
                _mapController.rotate(0);
              },
              child: const Icon(
                Icons.flag,
                color: Colors.green,
                size: 28,
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

      // Layer‐switch button:
      Positioned(
        top: 16,
        right: 76,
        child: FloatingActionButton(
          mini: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          heroTag: 'baseLayerBtn',
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) {
                return SimpleDialog(
                  title: const Text('Select Base Layer'),
                  children: [
                    for (int i = 0; i < _baseLayers.length; i++)
                      SimpleDialogOption(
                        onPressed: () {
                          print('Switching to layer $i: ${_baseLayers[i]['name']}');
                          setState(() {
                            _currentBaseLayerIndex = i;
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: Text(_baseLayers[i]['name']!),
                      ),
                  ],
                );
              },
            );
          },
          child: Icon(Icons.layers, color: Theme.of(context).colorScheme.onSurface),
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
                  color: Theme.of(context).colorScheme.surface,
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
                  color: Theme.of(context).colorScheme.onSurface,
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
                  _showEditRoadDialog(data, isCompleted);
                },
                child: const Text(
                  'Edit Road Details',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              if (!isCompleted)
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
                    _showCompleteSurveyDialog(data);
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
                  color: Theme.of(context).colorScheme.surface,
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
                  color: Theme.of(context).colorScheme.onSurface,
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
      if (!isCompleted)  // ONLY show if survey is NOT completed
      Positioned(
        bottom: 16,
        right: 16,
        child: FloatingActionButton(
          backgroundColor: AppColors.success,
          heroTag: 'recordDistressBtn',
          onPressed: () async {
            await _updateCurrentLocation();
            if (_currentLocation != null) {
              await Navigator.pushNamed(
                context,
                DistressForm.routeName,
                arguments: {
                  'surveyId': widget.surveyId,
                  'lat': _currentLocation!.latitude,
                  'lon': _currentLocation!.longitude,
                },
              );
              setState(() {
                _distressFuture =
                  DatabaseHelper().getDistressBySurvey(widget.surveyId);
              });
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

      // 9) List All Distress Points button (just above “Record Distress”)
      Positioned(
        bottom: 80, // 16 px from bottom + 56 px (FAB height) + 8 px gap
        right: 16,
        child: FloatingActionButton(
          backgroundColor: AppColors.primary,
          heroTag: 'listDistressBtn',
          mini: true,
          onPressed: () => _showDistressListSheet(isCompleted),
          child: const Icon(Icons.list),
        ),
      ),

    ],
  );
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
          final bool isCompleted = (data['status'] as String?) == 'completed';

          // Wrap the map + overlays in a FutureBuilder for distress points
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _distressFuture,
            builder: (context, distressSnap) {
              // While distress points are loading, show the map without them + a spinner
              if (distressSnap.connectionState != ConnectionState.done) {
                return Stack(
                  children: [
                    _buildFlutterMap(data, start, end, const [], isCompleted),
                    const Center(child: CircularProgressIndicator()),
                  ],
                );
              }

              // Once distress rows arrive, convert them into red markers
              final distressRows = distressSnap.data ?? [];
              final distressMarkers = distressRows.map((row) {
                final lat = row['latitude'] as double;
                final lon = row['longitude'] as double;
                final id = row['id'] as int;
                final type = row['type'] as String? ?? '—';
                final distressType = row['distress_type'] as String? ?? '—';
                final recordedAt = row['recorded_at'] as String? ?? '—';

                return Marker(
                  point: LatLng(lat, lon),
                  width: 36,
                  height: 36,
                  child: GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) {
                          return AlertDialog(
                            titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Distress Details',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                ),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Type: $type'),
                                Text('Distress Type: $distressType'),
                                Text('Recorded at: $recordedAt'),
                              ],
                            ),
                            actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
                            actions: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.warning,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  // 1) First load the complete distress‐row from the database:
                                  DatabaseHelper()
                                    .getDistressPointById(id)
                                    .then((row) {
                                      if (row != null) {
                                        // 2) Pass the entire Map<String,dynamic> as `existingDistressData`
                                        Navigator.pushNamed(
                                          context,
                                          DistressForm.routeName,
                                          arguments: {
                                            'existingDistressData': row,
                                          },
                                        ).then((_) {
                                          // 3) Refresh your markers or list after coming back:
                                          setState(() {
                                            _distressFuture = DatabaseHelper().getDistressBySurvey(widget.surveyId);
                                          });
                                        });
                                      } else {
                                        // In case the row no longer exists:
                                        CustomSnackbar.show(
                                          context,
                                          'This distress point no longer exists.',
                                          type: SnackbarType.error,
                                        );
                                      }
                                    })
                                    .catchError((_) {
                                      CustomSnackbar.show(
                                        context,
                                        'Failed to load distress for editing.',
                                        type: SnackbarType.error,
                                      );
                                    });
                                },
                                child: const Text(
                                  'Edit',
                                  style: TextStyle(color: Colors.black),
                                ),
                              ),
                              if (!isCompleted) ...[
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.danger,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () async {
                                    await DatabaseHelper().deleteDistressPoint(id);
                                    Navigator.of(ctx).pop();
                                    setState(() {
                                      _distressFuture = DatabaseHelper()
                                          .getDistressBySurvey(widget.surveyId);
                                    });
                                    CustomSnackbar.show(
                                      context,
                                      'Distress deleted.',
                                      type: SnackbarType.success,
                                    );
                                  },
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ],
                          );

                        },
                      );
                    },
                    child: const Icon(
                      Icons.warning,
                      color: Colors.purpleAccent,
                      size: 28,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 4,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                );
              
              }).toList();


              // Render the map with distress markers included
              return _buildFlutterMap(data, start, end, distressMarkers, isCompleted);
            },
          );
        },
      ),
    );
  }


}
