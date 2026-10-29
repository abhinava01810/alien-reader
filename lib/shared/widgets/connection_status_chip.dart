import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/device/domain/reader_device.dart';

class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip({super.key, required this.status});

  final ReaderConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ReaderConnectionStatus.connected => ('Connected', AppColors.success),
      ReaderConnectionStatus.connecting => ('Connecting', AppColors.orange),
      ReaderConnectionStatus.disconnected => ('Disconnected', AppColors.danger),
      ReaderConnectionStatus.busy => ('Processing', AppColors.purple),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle_rounded, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
