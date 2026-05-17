import 'package:flutter/material.dart';

class AdminNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  const AdminNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? Colors.white : Colors.white.withValues(alpha: 0.82);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          dense: true,
          minLeadingWidth: 22,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(
            locked ? Icons.lock_outline_rounded : icon,
            color: foreground,
          ),
          title: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: foreground,
            ),
          ),
          trailing: selected
              ? Container(
                  width: 6,
                  height: 22,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                )
              : null,
          onTap: onTap,
        ),
      ),
    );
  }
}
