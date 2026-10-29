import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The one section-header style used across screens: an optional leading
/// icon, a bold title, and an optional trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 20,
            color: isDark ? AppColors.purpleMid : AppColors.purple,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: -0.2,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
