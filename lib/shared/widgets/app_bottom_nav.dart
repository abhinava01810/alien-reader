import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum MainTab { home, output, files, profile }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentTab,
    required this.onChanged,
  });

  final MainTab currentTab;
  final ValueChanged<MainTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.dividerTheme.color ??
                (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: 1.0,
          ),
        ),
      ),
      child: NavigationBar(
        backgroundColor: theme.navigationBarTheme.backgroundColor,
        indicatorColor: theme.navigationBarTheme.indicatorColor,
        selectedIndex: MainTab.values.indexOf(currentTab),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration: const Duration(milliseconds: 300),
        onDestinationSelected: (index) => onChanged(MainTab.values[index]),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_rounded),
            selectedIcon: Icon(
              Icons.home_rounded,
              color: isDark ? AppColors.purpleMid : AppColors.purple,
            ),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.graphic_eq_rounded),
            selectedIcon: Icon(
              Icons.graphic_eq_rounded,
              color: isDark ? AppColors.purpleMid : AppColors.purple,
            ),
            label: 'Output',
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_rounded),
            selectedIcon: Icon(
              Icons.folder_rounded,
              color: isDark ? AppColors.purpleMid : AppColors.purple,
            ),
            label: 'Files',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_rounded),
            selectedIcon: Icon(
              Icons.person_rounded,
              color: isDark ? AppColors.purpleMid : AppColors.purple,
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
