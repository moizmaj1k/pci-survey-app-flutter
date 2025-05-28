import 'package:flutter/material.dart';
import 'package:pci_survey_application/theme/theme_factory.dart';

enum SnackbarType { success, error, warning, info }

class CustomSnackbar {
  static void show(
    BuildContext context,
    String message, {
    SnackbarType type = SnackbarType.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    final bg = _backgroundColor(type);
    // pick text/icon color based on bg brightness
    final textColor =
        bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    final icon = _icon(type);

    final overlay = Overlay.of(context)!;
    final entry = OverlayEntry(builder: (ctx) {
      return Positioned(
        top: MediaQuery.of(ctx).padding.top + kToolbarHeight + 8,
        left: 16,
        right: 16,
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(8),
          color: bg,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              children: [
                Icon(icon, color: textColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: textColor, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });

    overlay.insert(entry);
    Future.delayed(duration, () => entry.remove());
  }

  static Color _backgroundColor(SnackbarType type) {
    switch (type) {
      case SnackbarType.success:
        return AppColors.success;
      case SnackbarType.error:
        return AppColors.danger;
      case SnackbarType.warning:
        return AppColors.warning;
      case SnackbarType.info:
      default:
        return AppColors.info;
    }
  }

  static IconData _icon(SnackbarType type) {
    switch (type) {
      case SnackbarType.success:
        return Icons.check_circle_outline;
      case SnackbarType.error:
        return Icons.error_outline;
      case SnackbarType.warning:
        return Icons.warning_amber_outlined;
      case SnackbarType.info:
      default:
        return Icons.info_outline;
    }
  }
}
