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
  double  _progress    = 0.0;   // 0.0–1.0
  String? _current;            // e.g. "#42"
  int     _doneImages   = 0;
  int     _totalImages  = 0;

  bool    get busy        => _busy;
  double  get progress    => _progress;
  String? get current     => _current;
  int     get doneImages  => _doneImages;
  int     get totalImages => _totalImages;

  /// Uploads all distress-point images for every completed survey
  /// whose pics_state != 'done'. If [context] is non-null,
  /// shows snackbars for success/error; otherwise runs silently.
  Future<void> uploadAllPending({BuildContext? context}) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();

    final db      = DatabaseHelper();
    final surveys = await db.getPciSurveysByStatus('completed');

    for (final survey in surveys) {
      final surveyId = survey['id'] as int;
      final state    = survey['pics_state'] as String? ?? 'pending';
      if (state != 'done') {
        await _uploadSurveyImages(surveyId, context);
      }
    }

    _busy = false;
    notifyListeners();

    if (context != null) {
      CustomSnackbar.show(
        context,
        'All pending images processed.',
        type: SnackbarType.success,
      );
    }
  }

  /// Uploads images for a single survey.
  Future<void> _uploadSurveyImages(int surveyId, BuildContext? context) async {
    final db   = DatabaseHelper();
    _current   = '#$surveyId';

    // Load distress points for this survey
    final rows = await db.getDistressBySurvey(surveyId);

    // Count total images
    _totalImages = rows.fold<int>(
      0, (sum, row) => sum + _decodePics(row['pics']).length
    );
    _doneImages = 0;
    _progress   = 0.0;
    notifyListeners();

    for (final row in rows) {
      final distressId = row['id'] as int;
      final pics       = _decodePics(row['pics']);

      if (pics.isEmpty) {
        await db.updateDistressPicsState(distressId, 'done');
        continue;
      }

      // Mark uploading
      await db.updateDistressPicsState(distressId, 'uploading');

      final newUrls = <String>[];

      for (final path in pics) {
        try {
          final url = await _uploadFile(path);
          newUrls.add(url);
        } catch (e) {
          newUrls.add(path);
          if (context != null) {
            CustomSnackbar.show(
              context,
              'Failed to upload ${p.basename(path)}',
              type: SnackbarType.error,
            );
          }
        }

        _doneImages++;
        _progress = _totalImages > 0 ? _doneImages / _totalImages : 1.0;
        notifyListeners();
      }

      // Persist URLs
      final rowsAffected = await db.updateDistressPicsPaths(
        distressId,
        jsonEncode(newUrls),
      );

      if (rowsAffected > 0) {
        // Delete local files
        for (final pth in pics) {
          try { await File(pth).delete(); } catch (_) {}
        }
        await db.updateDistressPicsState(distressId, 'done');
        if (context != null) {
          CustomSnackbar.show(
            context,
            'Uploaded images for distress #$distressId',
            type: SnackbarType.success,
          );
        }
      } else {
        await db.updateDistressPicsState(distressId, 'error');
        if (context != null) {
          CustomSnackbar.show(
            context,
            'Failed to save URLs for distress #$distressId',
            type: SnackbarType.error,
          );
        }
      }
    }

    // All distress images done for this survey
    await db.updateSurveyPicsState(surveyId, 'done');
    if (context != null) {
      CustomSnackbar.show(
        context,
        'Survey $surveyId images completed.',
        type: SnackbarType.success,
      );
    }
  }

  /// Uploads a single file to:
  ///   /pci_survey_application/distress_points/{filename}
  /// Returns the download URL.
  Future<String> _uploadFile(String localPath) async {
    final file      = File(localPath);
    final fileName  = p.basename(localPath);
    final ref       = FirebaseStorage.instance
        .ref('pci_survey_application/distress_points/$fileName');
    final task      = ref.putFile(file);
    await task;
    return ref.getDownloadURL();
  }

  /// Decodes the JSON or List<String> stored in the `pics` field.
  List<String> _decodePics(dynamic pics) {
    if (pics is List) return List<String>.from(pics);
    if (pics is String && pics.isNotEmpty) {
      final decoded = jsonDecode(pics);
      if (decoded is List) return List<String>.from(decoded);
    }
    return [];
  }
}
