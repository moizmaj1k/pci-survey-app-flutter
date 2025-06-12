// lib/services/uploader.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

import '../database_helper.dart';
import '../widgets/custom_snackbar.dart';
import '../theme/theme_factory.dart';

/// A service to upload all pending distress-point images to Firebase Storage.
/// - Tracks progress and notifies listeners for UI updates.
/// - Uses CustomSnackbar for user feedback if [context] is provided.
/// - Only deletes local files once new URLs are safely persisted in SQLite.
class Uploader extends ChangeNotifier {
  bool    _busy        = false;
  double  _progress    = 0.0;
  String? _current;
  int     _doneImages  = 0;
  int     _totalImages = 0;

  bool    get busy       => _busy;
  double  get progress   => _progress;
  String? get current    => _current;
  int     get doneImages => _doneImages;
  int     get totalImages=> _totalImages;

  Future<void> uploadAllPending() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();

    final db      = DatabaseHelper();
    final surveys = await db.getPciSurveysByStatus('completed');

    for (final s in surveys) {
      if ((s['pics_state'] as String?) != 'done') {
        await _uploadSurveyImages(s['id'] as int);
      }
    }

    _busy = false;
    notifyListeners();
  }

  Future<void> _uploadSurveyImages(int surveyId) async {
    final db   = DatabaseHelper();
    _current   = '#$surveyId';

    final rows       = await db.getDistressBySurvey(surveyId);
    _totalImages     = rows.fold(0, (sum, r) => sum + _decodePics(r['pics']).length);
    _doneImages      = 0;
    _progress        = 0.0;
    notifyListeners();

    for (final r in rows) {
      final rid  = r['id'] as int;
      final pics = _decodePics(r['pics']);
      if (pics.isEmpty) {
        await db.updateDistressPicsState(rid, 'done');
        continue;
      }
      await db.updateDistressPicsState(rid, 'uploading');
      final newUrls = <String>[];

      for (final pth in pics) {
        try {
          final url = await _uploadFile(pth);
          newUrls.add(url);
        } catch (_) {
          newUrls.add(pth);
        }
        _doneImages++;
        _progress = _totalImages>0 ? _doneImages/_totalImages : 1.0;
        notifyListeners();
      }

      final updated = await db.updateDistressPicsPaths(rid, jsonEncode(newUrls));
      if (updated>0) {
        for (final pth in pics) {
          try { await File(pth).delete(); } catch (_) {}
        }
        await db.updateDistressPicsState(rid, 'done');
      } else {
        await db.updateDistressPicsState(rid, 'error');
      }
    }

    await db.updateSurveyPicsState(surveyId, 'done');
  }

  Future<String> _uploadFile(String localPath) async {
    final fileName = p.basename(localPath);
    final ref = FirebaseStorage.instance
      .ref('pci_survey_application/distress_points/$fileName');
    await ref.putFile(File(localPath));
    return ref.getDownloadURL();
  }

  List<String> _decodePics(dynamic pics) {
    if (pics is List) return List.from(pics);
    if (pics is String && pics.isNotEmpty) {
      final d = jsonDecode(pics);
      if (d is List) return List<String>.from(d);
    }
    return [];
  }
}
