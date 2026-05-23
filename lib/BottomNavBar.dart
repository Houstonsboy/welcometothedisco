import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

class _NavIconSpec {
  final String? asset;
  final bool svg;
  final IconData? materialIcon;

  const _NavIconSpec.asset(this.asset, {this.svg = false}) : materialIcon = null;

  const _NavIconSpec.material(this.materialIcon)
      : asset = null,
        svg = false;
}

class BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  /// Home · Search · Posts · Friends
  static const List<_NavIconSpec> _items = [
    _NavIconSpec.asset('assets/images/icons8-homepage.svg', svg: true),
    _NavIconSpec.asset('assets/images/icons8-search.svg', svg: true),
    _NavIconSpec.material(Icons.menu_book_rounded),
    _NavIconSpec.asset('assets/images/icons8-friends-50.png'),
  ];

  static const double _iconSize = 26;

  Widget _icon(_NavIconSpec spec, Color color) {
    if (spec.materialIcon != null) {
      return Icon(spec.materialIcon, size: _iconSize, color: color);
    }
    if (spec.svg) {
      return SvgPicture.asset(
        spec.asset!,
        width: _iconSize,
        height: _iconSize,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Image.asset(
      spec.asset!,
      width: _iconSize,
      height: _iconSize,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: AppTheme.glassNavGradient(),
                border: Border.all(
                  color: Colors.white.withOpacity(0.14),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_items.length, (index) {
                  final bool isSelected = selectedIndex == index;
                  final Color iconColor = isSelected
                      ? AppTheme.navSelectedIcon
                      : Colors.white.withOpacity(0.55);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.white.withOpacity(0.10)
                            : Colors.transparent,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.gradientEnd.withOpacity(0.55),
                                  blurRadius: 14,
                                  spreadRadius: 0,
                                ),
                              ]
                            : null,
                      ),
                      child: _icon(_items[index], iconColor),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
