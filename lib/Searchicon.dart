import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class SearchIcon extends StatelessWidget {
  const SearchIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const double radius = 28.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: CupertinoColors.white.withOpacity(0.14),
              border: Border.all(
                color: CupertinoColors.white.withOpacity(0.22),
                width: 0.8,
              ),
            ),
            child: CupertinoSearchTextField(
              placeholder: 'Search',
              placeholderStyle: TextStyle(
                color: CupertinoColors.white.withOpacity(0.6),
                fontWeight: FontWeight.w400,
              ),
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 16,
              ),
              prefixIcon: Icon(
                CupertinoIcons.search,
                color: CupertinoColors.white.withOpacity(0.7),
                size: 20,
              ),
              suffixIcon: Icon(
                CupertinoIcons.clear_circled_solid,
                color: CupertinoColors.white.withOpacity(0.6),
                size: 18,
              ),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            ),
          ),
        ),
      ),
    );
  }
}

