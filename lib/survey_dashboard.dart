import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:latlong2/latlong.dart';
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
  late Future<Map<String, dynamic>?> _surveyFuture;
  late final FMTCTileProvider _tileProvider;

  @override
  void initState() {
    super.initState();
    // Load the survey data
    _surveyFuture = DatabaseHelper().getPciSurveyById(widget.surveyId);

    // Configure the tile provider for browse caching
    _tileProvider = FMTCTileProvider(
      stores: const { 'osmCache': BrowseStoreStrategy.readUpdateCreate },
    );
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
                snapshot.hasError ? 'Error: \${snapshot.error}' : 'Survey not found',
                style: const TextStyle(color: AppColors.danger),
              ),
            );
          }

          final data = snapshot.data!;
          final start = LatLng(data['start_lat'], data['start_lon']);
          final hasEnd = data['end_lat'] != null && data['end_lon'] != null;
          final end = hasEnd
              ? LatLng(data['end_lat'], data['end_lon'])
              : null;

          return FlutterMap(
            options: MapOptions(
              initialCenter: start,
              initialZoom: 15,
            ),
            children: [
              // Offline-capable OSM tiles
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a','b','c'],
                tileProvider: _tileProvider,
                userAgentPackageName: 'com.example.pci_survey_application',
              ),

              // Real-time user location marker
              CurrentLocationLayer(),

              // Start and end markers
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
          );
        },
      ),
    );
  }
}
