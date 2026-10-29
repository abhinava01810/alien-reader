import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class OutputDeviceSheet extends StatelessWidget {
  const OutputDeviceSheet({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  static const List<String> devices = [
    'Phone Speaker',
    'Bluetooth Earbuds',
    'Bluetooth Headphones',
    'Bluetooth Speaker',
    'Alien Reader Speaker',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Audio Output Device',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...devices.map(
              (device) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(device),
                trailing: Icon(
                  selected == device
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected == device ? AppColors.purple : null,
                ),
                onTap: () => onSelected(device),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select your preferred speaker or connected Bluetooth headset for TTS audio playback.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
