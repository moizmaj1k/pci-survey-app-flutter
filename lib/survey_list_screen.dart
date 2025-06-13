import 'package:flutter/material.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'database_helper.dart';

class SurveyListScreen extends StatefulWidget {
  const SurveyListScreen({Key? key}) : super(key: key);

  @override
  _SurveyListScreenState createState() => _SurveyListScreenState();
}

class _SurveyListScreenState extends State<SurveyListScreen> {
  List<Map<String, dynamic>> _surveys = [];
  Map<int, String> _districtNames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();

    // 1) load districts & debug
    final districts = await db.getAllDistricts();
    debugPrint('District rows: $districts');

    // 2) build id→name map using whichever keys exist
    final districtMap = <int, String>{};
    for (final d in districts) {
      final id = (d['id'] ?? d['district_id']) as int;
      final name = (d['district_name'] ?? d['name']) as String;
      districtMap[id] = name;
    }

    // 3) load surveys
    final surveys = await db.getPushedPciSurveys();

    setState(() {
      _districtNames = districtMap;
      _surveys = surveys;
      _loading = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppNavBar(title: 'Pushed Surveys'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _surveys.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final s = _surveys[i];
                final districtName =
                    _districtNames[s['district_id']] ?? 'Unknown';
                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 4,
                      ),
                    ),
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row: icon + road name
                        Row(
                          children: [
                            Icon(Icons.aod,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s['road_name'] ?? 'Survey #${s['id']}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Chips row: ID, status, district name, date
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Chip(
                              label: Text('ID: ${s['id']}'),
                              visualDensity: VisualDensity.compact,
                            ),
                            Chip(
                              label: Text(s['status']),
                              visualDensity: VisualDensity.compact,
                            ),
                            Chip(
                              label: Text('District: $districtName'),
                              visualDensity: VisualDensity.compact,
                            ),
                            Chip(
                              label: Text(
                                DateTime.tryParse(s['created_at']) != null
                                    ? DateTime.parse(s['created_at'])
                                        .toLocal()
                                        .toString()
                                        .split('.')[0]
                                    : s['created_at'],
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Distress count
                        FutureBuilder<int>(
                          future:
                              DatabaseHelper().getDistressCount(s['id']),
                          builder: (ctx, snap) {
                            final countText = (snap.connectionState ==
                                    ConnectionState.waiting)
                                ? '…'
                                : '${snap.data ?? 0}';
                            return Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error),
                                const SizedBox(width: 6),
                                Text(
                                  'Distress points: $countText',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
