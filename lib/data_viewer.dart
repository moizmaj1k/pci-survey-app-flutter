// lib/data_viewer.dart

import 'package:flutter/material.dart';
import 'package:pci_survey_application/widgets/app_nav_bar.dart';
import 'database_helper.dart';
import 'theme/theme_factory.dart';

class DataViewer extends StatelessWidget {
  const DataViewer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const AppNavBar(title: 'Data Viewer'),
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color,
                tabs: const [
                  Tab(text: 'Users'),
                  Tab(text: 'Enumerators'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildUsersTable(context),
                  _buildEnumeratorsTable(context),
                ],
              ),
            ),
          ],
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
            // Icon cell:
            (user['is_synced'] == 1)
                ? Icons.check_circle.codePoint.toString()
                : Icons.sync.codePoint.toString(),
            (user['is_synced'] == 1)
                ? AppColors.success
                : AppColors.warning,
          ]).toList(),
          iconColumns: {4}, // 4th column is an icon
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

        final headers = [
          'ID',
          'Name',
          'Phone',
          'District',
          'User ID',
          'Synced'
        ];
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
          iconColumns: {5}, // last column is an icon
        );
      },
    );
  }

  /// Helper to build a horizontally‐scrollable table.
  /// 
  /// - [dataRows] is a List of rows, where each row is a List of cell‐values (all strings except icon color).
  /// - [iconColumns] is a Set of column‐indexes that should render a Flutter Icon instead of text.
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
              // Header
              TableRow(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.1),
                ),
                children: headers.map((h) {
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      h,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
              ),
              // Data
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
                            // render icon
                            ? Icon(
                                IconData(int.parse(row[i]), fontFamily: 'MaterialIcons'),
                                color: row[++i] as Color,
                              )
                            // normal text
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
