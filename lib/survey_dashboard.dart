import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
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

  @override
  void initState() {
    super.initState();

    // Load survey data
    _surveyFuture = DatabaseHelper().getPciSurveyById(widget.surveyId);

    // Initialize offline tile provider
    _tileProvider = FMTCTileProvider(
      stores: const {'osmCache': BrowseStoreStrategy.readUpdateCreate},
    );
  }

  Future<void> _updateCurrentLocation() async {
    try {
        final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,            // only update if moved 10 meters
          timeLimit: Duration(seconds: 5), // timeout after 5 seconds
        ),
      );

          setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      // If location permission is denied or unavailable, leave _currentLocation null
    }
  }

  Future<void> _recenterToCurrentLocation() async {
    // Ensure we have the latest coordinates
    await _updateCurrentLocation();

    if (_currentLocation != null) {
      // Move map to user's location at fixed zoom and reset rotation
      _mapController.move(_currentLocation!, _defaultZoom);
      _mapController.rotate(0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for location data…')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppNavBar(title: 'Survey #${widget.surveyId}'),
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

                  // 2) Blue location marker with heading (default behavior)
                  const CurrentLocationLayer(),

                  // 3) Start and end markers (using `child`)
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

              // 4) Recenter button (top-right)
              Positioned(
                top: 16,
                right: 16,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  heroTag: 'recenterBtn',
                  onPressed: _recenterToCurrentLocation,
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.black54,
                  ),
                ),
              ),

              // 5) Dropdown for Edit Road Details & Complete Survey (top-left)
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
                          borderRadius: BorderRadius.circular(8), // rounded rectangle
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
                            borderRadius: BorderRadius.circular(6), // less rounded
                          ),
                        ),
                        onPressed: () {
                          setState(() => _showDropdown = false);
                          Navigator.pushNamed(
                            context,
                            '/editStartDetails',
                            arguments: widget.surveyId,
                          );
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
                            borderRadius: BorderRadius.circular(6), // less rounded
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

                      // More visible, styled collapse arrow:
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8), // rounded rectangle
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

              // 6) Record Distress Point button (bottom-right)
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton(
                  backgroundColor: AppColors.success,
                  heroTag: 'recordDistressBtn',
                  onPressed: () async {
                    // Update and fetch current location
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Current location not available yet')),
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
