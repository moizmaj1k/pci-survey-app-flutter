import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static const _dbName = 'pci_survey.db';
  static const _dbVersion = 1;
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // USERS
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        designation TEXT NOT NULL,
        password TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    // ENUMERATORS
    await db.execute('''
      CREATE TABLE enumerators(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        district_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(district_id) REFERENCES districts(id) ON DELETE CASCADE
      )
    ''');

    // DISTRICTS
    await db.execute('''
      CREATE TABLE districts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        district_name TEXT NOT NULL,
        district_uic TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    // Preload a few districts
    const seedDistricts = [
        {'district_name': 'Abbottabad', 'district_uic': '100ABT'},
        {'district_name': 'Bajaur', 'district_uic': '200BAJ'},
        {'district_name': 'Bannu', 'district_uic': '300BAN'},
        {'district_name': 'Batagram', 'district_uic': '400BAT'},
        {'district_name': 'Buner', 'district_uic': '500BUN'},
        {'district_name': 'Charsadda', 'district_uic': '600CHA'},
        {'district_name': 'Chitral Lower', 'district_uic': '700CHL'},
        {'district_name': 'Chitral Upper', 'district_uic': '800CHU'},
        {'district_name': 'D. I. Khan', 'district_uic': '900DIK'},
        {'district_name': 'Hangu', 'district_uic': '010HAN'},
        {'district_name': 'Haripur', 'district_uic': '020HAR'},
        {'district_name': 'Karak', 'district_uic': '030KAR'},
        {'district_name': 'Khyber', 'district_uic': '040KHY'},
        {'district_name': 'Kohat', 'district_uic': '050KOH'},
        {'district_name': 'Kohistan Lower', 'district_uic': '060KOL'},
        {'district_name': 'Kohistan Upper', 'district_uic': '070KOU'},
        {'district_name': 'Kolai Palas Kohistan', 'district_uic': '080KPK'},
        {'district_name': 'Kurram', 'district_uic': '090KUR'},
        {'district_name': 'Lakki Marwat', 'district_uic': '001LAK'},
        {'district_name': 'Lower Dir', 'district_uic': '002LOD'},
        {'district_name': 'Malakand', 'district_uic': '003MAL'},
        {'district_name': 'Mansehra', 'district_uic': '004MAN'},
        {'district_name': 'Mardan', 'district_uic': '005MAR'},
        {'district_name': 'Mohmand', 'district_uic': '006MOH'},
        {'district_name': 'North Waziristan', 'district_uic': '007NWA'},
        {'district_name': 'Nowshera', 'district_uic': '008NOW'},
        {'district_name': 'Orakzai', 'district_uic': '009ORA'},
        {'district_name': 'Peshawar', 'district_uic': '110PES'},
        {'district_name': 'Shangla', 'district_uic': '210SHA'},
        {'district_name': 'South Waziristan', 'district_uic': '310SWA'},
        {'district_name': 'Swabi', 'district_uic': '410SWI'},
        {'district_name': 'Swat', 'district_uic': '510SWT'},
        {'district_name': 'Tank', 'district_uic': '610TAN'},
        {'district_name': 'Tor Ghar', 'district_uic': '710TOG'},
        {'district_name': 'Upper Dir', 'district_uic': '810UPD'},
    ];
    for (var d in seedDistricts) {
      await db.insert('districts', d);
    }

    // PCI Survey
    await db.execute('''
      CREATE TABLE pci_survey (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        district_id INTEGER NOT NULL,
        road_name TEXT,
        start_rd TEXT,
        end_rd TEXT,
        road_length REAL,
        start_lat REAL,
        start_lon REAL,
        end_lat REAL,
        end_lon REAL,
        remarks TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_by INTEGER,
        status TEXT DEFAULT 'draft',
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (created_by) REFERENCES enumerators(id)
          ON DELETE SET NULL ON UPDATE CASCADE,
        FOREIGN KEY (district_id) REFERENCES districts(id)
          ON DELETE SET NULL ON UPDATE CASCADE
      )
    ''');

    // Distress Points
    await db.execute('''
      CREATE TABLE distress_point (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        survey_id INTEGER NOT NULL,
        rd TEXT,
        type TEXT,
        distress_type TEXT,
        severity TEXT,
        quantity REAL,
        quantity_unit TEXT,
        latitude REAL,
        longitude REAL,
        pics TEXT,
        remarks TEXT,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (survey_id) REFERENCES pci_survey(id)
          ON DELETE CASCADE
      )
    ''');

  }

  // USER METHODS

  String _hash(String input) => sha256.convert(utf8.encode(input)).toString();

  Future<int> insertUser({
    required String username,
    required String email,
    required String designation,
    required String password,
  }) async {
    final db = await database;
    return db.insert('users', {
      'username': username,
      'email': email,
      'designation': designation,
      'password': _hash(password),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String,dynamic>?> getUser(String email, String password) async {
    final db = await database;
    final hashed = _hash(password);
    final res = await db.query(
      'users',
      where: 'email=? AND password=?',
      whereArgs: [email, hashed],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<List<Map<String,dynamic>>> getAllUsers() async {
    return (await database).query('users');
  }

  Future<void> saveCurrentUser(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('currentUserId', id);
  }

  // Retrieve the currently logged-in user ID from SharedPreferences
  Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('currentUserId');
  }

  
  
  // DISTRICT METHODS

  /// Looks up a district row by name.
  Future<Map<String, dynamic>?> getDistrictByName(String districtName) async {
    final db = await database;
    final result = await db.query(
      'districts',
      where: 'district_name = ?',
      whereArgs: [districtName],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Fetches all districts.
  Future<List<Map<String, dynamic>>> getAllDistricts() async {
    return (await database).query('districts');
  }



  // ENUMERATOR METHODS

  Future<int> insertEnumerator({
    required String name,
    required String phone,
    required int districtId,
    required int userId,
  }) async {
    final db = await database;
    return db.insert('enumerators', {
      'name': name,
      'phone': phone,
      'district_id': districtId,
      'user_id': userId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns the enumerator + district name for the logged in user (or null).
  Future<Map<String, dynamic>?> getEnumeratorDetails() async {
    final db = await database;
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('currentUserId');
    if (userId == null) return null;

    final results = await db.rawQuery('''
      SELECT e.id, e.name, e.phone, e.district_id, d.district_name AS district
      FROM enumerators e
      JOIN districts d ON e.district_id = d.id
      WHERE e.user_id = ? LIMIT 1
    ''', [userId]);

    return results.isNotEmpty ? results.first : null;
  }

  /// Updates the enumerator’s name, phone, and district for the current user.
  Future<void> updateEnumeratorDetails(
    String name,
    String phone,
    String newDistrictName,
  ) async {
    final db = await database;

    final districtRow = await getDistrictByName(newDistrictName);
    if (districtRow == null) throw Exception('District not found');

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('currentUserId');
    if (userId == null) throw Exception('No logged in user');

    await db.update(
      'enumerators',
      {'name': name, 'phone': phone, 'district_id': districtRow['id']},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Fetches all enumerators along with their district name.
  Future<List<Map<String, dynamic>>> getAllEnumerators() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        e.id,
        e.name,
        e.phone,
        e.district_id,
        d.district_name AS district,
        e.user_id,
        e.is_synced
      FROM enumerators e
      LEFT JOIN districts d ON e.district_id = d.id
      ORDER BY e.id
    ''');
    return rows;
  }



  // PCI SURVEY METHODS

  /// Inserts a new PCI survey draft.
  /// Only the “start” fields are required at creation time.
  Future<int> insertPciSurvey({
    required int districtId,
    required String roadName,
    required String startRd,
    required double startLat,
    required double startLon,
    required int createdBy,
  }) async {
    final db = await database;
    return db.insert(
      'pci_survey',
      {
        'district_id':   districtId,
        'road_name':     roadName,
        'start_rd':      startRd,
        'start_lat':     startLat,
        'start_lon':     startLon,
        'created_by':    createdBy,
        // status defaults to 'draft', is_synced defaults to 0
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Called when the user “completes” a survey.
  /// Sets end_rd, road_length, end_lat, end_lon, remarks, AND status='completed'
  Future<int> updateSurveyCompletion({
    required int surveyId,
    required String endRd,
    required double roadLength,
    required double endLat,
    required double endLon,
    required String remarks,
  }) async {
    final db = await database;

    return await db.update(
      'pci_survey',
      {
        'end_rd'     : endRd,
        'road_length': roadLength,
        'end_lat'    : endLat,
        'end_lon'    : endLon,
        'remarks'    : remarks,
        // mark status as “completed”
        'status'     : 'completed',
      },
      where: 'id = ?',
      whereArgs: [surveyId],
    );
  }

  /// Fetches all surveys matching the given status AND created_by the current user.
  Future<List<Map<String, dynamic>>> getPciSurveysByStatus(String status) async {
    final db = await database;
    // Assume getCurrentUserId() returns the logged‐in user’s ID (or null if none).
    final userId = await getCurrentUserId() ?? 0;

    return db.query(
      'pci_survey',
      where: 'status = ? AND created_by = ?',
      whereArgs: [status, userId],
      orderBy: 'created_at DESC',
    );
  }

  /// Get a single survey by its ID.
  Future<Map<String, dynamic>?> getPciSurveyById(int id) async {
    final db = await database;
    final results = await db.query(
      'pci_survey',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Fetch all surveys, regardless of status.
  Future<List<Map<String, dynamic>>> getAllPciSurveys() async {
    final db = await database;
    return db.query('pci_survey', orderBy: 'created_at DESC');
  }

  /// Count surveys by a single status (e.g. "completed" or "draft")
  Future<int> getSurveyCountByStatus(String status) async {
    final db = await database; // however you get your DB instance
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM pci_survey WHERE status = ?',
      [status],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Count completed surveys that have been pushed (is_synced = 1)
  Future<int> getPushedSurveyCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt '
      'FROM pci_survey '
      'WHERE status = ? AND is_synced = ?',
      ['completed', 1],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Count completed surveys that have NOT been pushed (is_synced = 0)
  Future<int> getUnpushedSurveyCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt '
      'FROM pci_survey '
      'WHERE status = ? AND is_synced = ?',
      ['completed', 0],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }


  /// Returns the number of rows affected.
  Future<int> updateSurveyRoadDetails(
      int surveyId,
      String newName,
      int newDistrict,
      String newStartRd,
      String newRemarks,
  ) async {
    final db = await database; // however you obtain your Database instance

    return await db.update(
      'pci_survey',
      {
        'road_name': newName,
        'district_id': newDistrict,
        'start_rd': newStartRd,
        'remarks': newRemarks,
      },
      where: 'id = ?',
      whereArgs: [surveyId],
    );
  }

  /// Updates only the `end_rd` and `road_length` columns for an already‐completed survey.
  /// Returns the number of rows affected.
  Future<int> updateSurveyCompletionFields({
    required int surveyId,
    required String endRd,
    required double roadLength,
  }) async {
    final db = await database;
    return await db.update(
      'pci_survey',
      {
        'end_rd': endRd,
        'road_length': roadLength,
      },
      where: 'id = ?',
      whereArgs: [surveyId],
    );
  }

  /// Deletes all distress points for [surveyId], then deletes the survey row itself.
  /// Wrapping them in a single transaction ensures consistency.
  Future<void> deletePciSurvey(int surveyId) async {
    final db = await database; // however you get your Database instance

    await db.transaction((txn) async {
      // 1) Delete any distress points tied to this survey
      await txn.delete(
        'distress_point',
        where: 'survey_id = ?',
        whereArgs: [surveyId],
      );

      // 2) Delete the survey row
      await txn.delete(
        'pci_survey',
        where: 'id = ?',
        whereArgs: [surveyId],
      );
    });
  }


  // DISTRESS POINT METHODS

  // INSERT a new distress record
  Future<int> insertDistressPoint({
    required int surveyId,
    required String rd,
    String? type,
    String? distressType,
    String? severity,
    double? quantity,
    String? quantityUnit,
    required double latitude,
    required double longitude,
    String? pics,           // comma-separated paths or JSON array
    String? remarks,        // NEW parameter
  }) async {
    final db = await database;
    return db.insert(
      'distress_point',
      {
        'survey_id':     surveyId,
        'rd':            rd,
        'type':          type,
        'distress_type': distressType,
        'severity':      severity,
        'quantity':      quantity,
        'quantity_unit': quantityUnit,
        'latitude':      latitude,
        'longitude':     longitude,
        'pics':          pics,
        'remarks':       remarks,        // pass remarks here
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
    
  // FETCH all distress records for one survey
  Future<List<Map<String, dynamic>>> getDistressBySurvey(int surveyId) async {
    final db = await database;
    return db.query(
      'distress_point',
      where: 'survey_id = ?',
      whereArgs: [surveyId],
      orderBy: 'recorded_at ASC',
    );
  }

  // FETCH a single distress record by its ID
  Future<Map<String, dynamic>?> getDistressPointById(int id) async {
    final db = await database;
    final rows = await db.query(
      'distress_point',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  // UPDATE an existing distress record
  Future<int> updateDistressPoint({
    required int id,
    String? rd,
    String? type,
    String? distressType,
    String? severity,
    double? quantity,
    String? quantityUnit,
    double? latitude,
    double? longitude,
    String? pics,
    String? remarks,        // NEW parameter
  }) async {
    final db = await database;
    final data = <String, dynamic>{};
    if (rd != null)            data['rd'] = rd;
    if (type != null)          data['type'] = type;
    if (distressType != null)  data['distress_type'] = distressType;
    if (severity != null)      data['severity'] = severity;
    if (quantity != null)      data['quantity'] = quantity;
    if (quantityUnit != null)  data['quantity_unit'] = quantityUnit;
    if (latitude != null)      data['latitude'] = latitude;
    if (longitude != null)     data['longitude'] = longitude;
    if (pics != null)          data['pics'] = pics;
    if (remarks != null)       data['remarks'] = remarks; // include remarks

    if (data.isEmpty) return 0; // nothing to update

    return db.update(
      'distress_point',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns all distress points (for your “Distress” tab).
  Future<List<Map<String, dynamic>>> getAllDistressPoints() async {
    final db = await database;
    return db.query(
      'distress_point',
      orderBy: 'recorded_at ASC',
    );
  }

  // DELETE a distress record by ID
  Future<int> deleteDistressPoint(int id) async {
    final db = await database;
    return db.delete(
      'distress_point',
      where: 'id = ?',
      whereArgs: [id],
    );
  }


  /// Deletes the entire SQLite database file.
  Future<void> deleteDatabaseFile() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    await close(); // close any open database connection
    await deleteDatabase(path);
    _db = null;
  }

  /// Closes the database if it's open.
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
