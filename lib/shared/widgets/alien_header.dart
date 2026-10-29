import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';

class AlienHeader extends StatelessWidget implements PreferredSizeWidget {
  const AlienHeader({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppBar(
      backgroundColor: theme.appBarTheme.backgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/app_icon.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Image.asset(
                'assets/images/alien_innovations_logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            AppStrings.brandName,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.purpleMid : AppColors.purple,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            onPressed: onOpenSettings,
            tooltip: 'Settings & Device Connections',
            icon: Icon(
              Icons.settings_rounded,
              color: isDark ? AppColors.darkText : AppColors.charcoal,
              size: 24,
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          thickness: 1,
          color:
              theme.dividerTheme.color ??
              (isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);
}
