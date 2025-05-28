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



}
