// lib/data_viewer.dart

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'database_helper.dart';
import 'theme/theme_factory.dart';

class DataViewer extends StatelessWidget {
  const DataViewer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5, // 5 tabs: Users, Enumerators, Districts, Surveys, Distress
      child: Scaffold(
        appBar: const AppNavBar(title: 'Data Viewer'),
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor:
                    Theme.of(context).textTheme.bodyMedium?.color,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Users'),
                  Tab(text: 'Enumerators'),
                  Tab(text: 'Districts'),
                  Tab(text: 'Surveys'),
                  Tab(text: 'Distress'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildUsersTable(context),
                  _buildEnumeratorsTable(context),
                  _buildDistrictsTable(context),
                  _buildSurveysTable(context),
                  _buildDistressTable(context),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.share),
          label: const Text('Share Data'),
          onPressed: () => _exportAndShareXlsx(context),
        ),
      ),
    );
  }

  Widget _buildUsersTable(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllUsers(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final users = snap.data ?? [];
        if (users.isEmpty) {
          return const Center(child: Text('No users found'));
        }

        final headers = ['ID', 'Username', 'Email', 'Designation', 'Synced'];
        return _buildTable(
          context,
          headers,
          users.map((user) => [
            user['id'].toString(),
            user['username'] ?? '',
            user['email'] ?? '',
            user['designation'] ?? '',
            (user['is_synced'] == 1)
                ? Icons.check_circle.codePoint.toString()
                : Icons.sync.codePoint.toString(),
            (user['is_synced'] == 1)
                ? AppColors.success
                : AppColors.warning,
          ]).toList(),
          iconColumns: {4},
        );
      },
    );
  }

  Widget _buildEnumeratorsTable(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllEnumerators(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final enums = snap.data ?? [];
        if (enums.isEmpty) {
          return const Center(child: Text('No enumerators found'));
        }

        final headers = ['ID', 'Name', 'Phone', 'District', 'User ID', 'Synced'];
        return _buildTable(
          context,
          headers,
          enums.map((e) => [
            e['id'].toString(),
            e['name'] ?? '',
            e['phone'] ?? '',
            e['district'] ?? '',
            e['user_id'].toString(),
            (e['is_synced'] == 1)
                ? Icons.check_circle.codePoint.toString()
                : Icons.sync.codePoint.toString(),
            (e['is_synced'] == 1)
                ? AppColors.success
                : AppColors.warning,
          ]).toList(),
          iconColumns: {5},
        );
      },
    );
  }

  Widget _buildDistrictsTable(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllDistricts(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final districts = snap.data ?? [];
        if (districts.isEmpty) {
          return const Center(child: Text('No districts found'));
        }

        final headers = ['ID', 'Name', 'UIC', 'Synced'];
        return _buildTable(
          context,
          headers,
          districts.map((d) => [
            d['id'].toString(),
            d['district_name'] ?? '',
            d['district_uic'] ?? '',
            (d['is_synced'] == 1)
                ? Icons.check_circle.codePoint.toString()
                : Icons.sync.codePoint.toString(),
            (d['is_synced'] == 1)
                ? AppColors.success
                : AppColors.warning,
          ]).toList(),
          iconColumns: {3},
        );
      },
    );
  }

  Widget _buildSurveysTable(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllPciSurveys(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final surveys = snap.data ?? [];
        if (surveys.isEmpty) {
          return const Center(child: Text('No surveys found'));
        }

        final headers = [
          'ID', 'District ID', 'Road Name', 'Start RD', 'End RD',
          'Length', 'Start Lat', 'Start Lon', 'End Lat', 'End Lon',
          'Remarks', 'Created At', 'Created By', 'Status', 'Synced'
        ];
        return _buildTable(
          context,
          headers,
          surveys.map((s) => [
            s['id'].toString(),
            s['district_id'].toString(),
            s['road_name'] ?? '',
            s['start_rd'] ?? '',
            s['end_rd'] ?? '',
            (s['road_length'] ?? '').toString(),
            (s['start_lat'] ?? '').toString(),
            (s['start_lon'] ?? '').toString(),
            (s['end_lat'] ?? '').toString(),
            (s['end_lon'] ?? '').toString(),
            s['remarks'] ?? '',
            s['created_at'] ?? '',
            s['created_by']?.toString() ?? '',
            s['status'] ?? '',
            (s['is_synced'] == 1)
                ? Icons.check_circle.codePoint.toString()
                : Icons.sync.codePoint.toString(),
            (s['is_synced'] == 1)
                ? AppColors.success
                : AppColors.warning,
          ]).toList(),
          iconColumns: {14},
        );
      },
    );
  }

  Widget _buildDistressTable(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper().getAllDistressPoints(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final points = snap.data ?? [];
        if (points.isEmpty) {
          return const Center(child: Text('No distress points found'));
        }

        final headers = [
          'ID', 'Survey ID', 'RD', 'Type', 'Distress Type', 'Severity',
          'Quantity', 'Quantity Unit', 'Latitude', 'Longitude', 'Pics', 'Recorded At'
        ];
        return _buildTable(
          context,
          headers,
          points.map((p) => [
            p['id'].toString(),
            p['survey_id'].toString(),
            p['rd'] ?? '',
            p['type'] ?? '',
            p['distress_type'] ?? '',
            p['severity'] ?? '',
            (p['quantity'] ?? '').toString(),
            p['quantity_unit'] ?? '',
            (p['latitude'] ?? '').toString(),
            (p['longitude'] ?? '').toString(),
            p['pics'] ?? '',
            p['recorded_at'] ?? '',
          ]).toList(),
          iconColumns: {},
        );
      },
    );
  }

  /// Helper to build a horizontally‐scrollable table.
  Widget _buildTable(
    BuildContext context,
    List<String> headers,
    List<List<dynamic>> dataRows, {
    required Set<int> iconColumns,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: Table(
            border: TableBorder.all(color: Theme.of(context).dividerColor),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              // Header row
              TableRow(
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.1),
                ),
                children: headers
                    .map((h) => Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            h,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ))
                    .toList(),
              ),
              // Data rows
              for (var row in dataRows)
                TableRow(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  children: [
                    for (var i = 0; i < row.length; i++)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: iconColumns.contains(i)
                            ? Icon(
                                IconData(
                                  int.parse(row[i] as String),
                                  fontFamily: 'MaterialIcons',
                                ),
                                color: row[++i] as Color,
                              )
                            : Text(row[i].toString()),
                      )
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _exportAndShareXlsx(BuildContext context) async {
  try {
    // 1) Fetch all your data
    final users       = await DatabaseHelper().getAllUsers();
    final enums       = await DatabaseHelper().getAllEnumerators();
    final districts   = await DatabaseHelper().getAllDistricts();
    final surveys     = await DatabaseHelper().getAllPciSurveys();
    final distressPts = await DatabaseHelper().getAllDistressPoints();

    // 2) Create a new Excel workbook and remove the default sheet
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    excel.delete(defaultSheet);

    // 3) Helper to add a sheet with header + rows (all as TextCellValue)
    void addSheet(String name, List<String> header, List<List<dynamic>> rows) {
      final Sheet sheet = excel[name]; // creates if missing
      // write header
      sheet.appendRow(header.map((h) => TextCellValue(h)).toList());
      // write data rows
      for (final row in rows) {
        sheet.appendRow(
          row.map((c) => TextCellValue(c.toString())).toList()
        );
      }
    }

    addSheet(
      'Users',
      ['ID','Username','Email','Designation','Synced'],
      users.map((u) => [
        u['id'],
        u['username'],
        u['email'],
        u['designation'],
        u['is_synced'] == 1 ? 'Yes' : 'No',
      ]).toList(),
    );

    addSheet(
      'Enumerators',
      ['ID','Name','Phone','District','User ID','Synced'],
      enums.map((e) => [
        e['id'],
        e['name'],
        e['phone'],
        e['district'],
        e['user_id'],
        e['is_synced'] == 1 ? 'Yes' : 'No',
      ]).toList(),
    );

    addSheet(
      'Districts',
      ['ID','Name','UIC','Synced'],
      districts.map((d) => [
        d['id'],
        d['district_name'],
        d['district_uic'],
        d['is_synced'] == 1 ? 'Yes' : 'No',
      ]).toList(),
    );

    addSheet(
      'Surveys',
      [
        'ID','District ID','Road Name','Start RD','End RD','Length',
        'Start Lat','Start Lon','End Lat','End Lon',
        'Remarks','Created At','Created By','Status','Synced',
      ],
      surveys.map((s) => [
        s['id'],
        s['district_id'],
        s['road_name'],
        s['start_rd'],
        s['end_rd'],
        s['road_length'],
        s['start_lat'],
        s['start_lon'],
        s['end_lat'],
        s['end_lon'],
        s['remarks'],
        s['created_at'],
        s['created_by'],
        s['status'],
        s['is_synced'] == 1 ? 'Yes' : 'No',
      ]).toList(),
    );

    addSheet(
      'Distress',
      [
        'ID','Survey ID','RD','Type','Distress Type','Severity',
        'Quantity','Quantity Unit','Latitude','Longitude',
        'Pics','Recorded At',
      ],
      distressPts.map((p) => [
        p['id'],
        p['survey_id'],
        p['rd'],
        p['type'],
        p['distress_type'],
        p['severity'],
        p['quantity'],
        p['quantity_unit'],
        p['latitude'],
        p['longitude'],
        p['pics'],
        p['recorded_at'],
      ]).toList(),
    );

    // 4) Save the workbook to bytes
    final bytes = excel.save(); // Uint8List?
    if (bytes == null) throw 'Excel encoding failed';

    // 5) Write to a temp file
    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/pci_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    // 6) Fire up the native share sheet
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: 'PCI Survey data export',
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export/share failed: $e')),
    );
  }
}