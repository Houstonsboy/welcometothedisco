// lib/widgets/expanding_search_bar.dart

import 'package:flutter/material.dart';
import 'package:welcometothedisco/theme/app_theme.dart';

class ExpandingSearchBar extends StatefulWidget {
  const ExpandingSearchBar({
    super.key,
    this.onChanged,
    this.onSubmitted,
    this.hint = 'Search artists…',
  });

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hint;

  @override
  State<ExpandingSearchBar> createState() => _ExpandingSearchBarState();
}

class _ExpandingSearchBarState extends State<ExpandingSearchBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _widthFactor;
  late final Animation<double> _fadeText;

  final _focusNode = FocusNode();
  final _textCtrl = TextEditingController();
  bool _isExpanded = false;

  static const double _iconSize = 44.0;
  static const double _expandedHeight = 44.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _widthFactor = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeInOutCubic,
    );

    _fadeText = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _isExpanded = true);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _collapse() {
    _focusNode.unfocus();
    _textCtrl.clear();
    widget.onChanged?.call('');
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _isExpanded = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final currentWidth = (_iconSize +
                    (_widthFactor.value * (maxWidth - _iconSize)))
                .clamp(0.0, maxWidth);

            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: currentWidth,
                height: _expandedHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(44),
                child: _GlassPill(
                  isExpanded: _isExpanded,
                  widthFactor: _widthFactor.value,
                  fadeFactor: _fadeText.value,
                  focusNode: _focusNode,
                  textCtrl: _textCtrl,
                  hint: widget.hint,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  onIconTap: _isExpanded ? null : _expand,
                  onClose: _collapse,
                ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.isExpanded,
    required this.widthFactor,
    required this.fadeFactor,
    required this.focusNode,
    required this.textCtrl,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
    required this.onIconTap,
    required this.onClose,
  });

  final bool isExpanded;
  final double widthFactor;
  final double fadeFactor;
  final FocusNode focusNode;
  final TextEditingController textCtrl;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onIconTap;
  final VoidCallback onClose;

  static const _kGreen = AppTheme.createGreen;

  @override
  Widget build(BuildContext context) {
    final borderColor = Color.lerp(
      Colors.white.withOpacity(0.15),
      _kGreen.withOpacity(0.55),
      widthFactor,
    )!;

    final bgColor = Color.lerp(
      Colors.white.withOpacity(0.08),
      Colors.white.withOpacity(0.10),
      widthFactor,
    )!;

    return GestureDetector(
      onTap: onIconTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(44),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: _kGreen.withOpacity(0.08 * widthFactor),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: Center(
                child: Icon(
                  Icons.search_rounded,
                  color: Color.lerp(
                    Colors.white.withOpacity(0.55),
                    _kGreen,
                    widthFactor,
                  ),
                  size: 20,
                ),
              ),
            ),
            if (isExpanded)
              Expanded(
                child: FadeTransition(
                  opacity: AlwaysStoppedAnimation(fadeFactor),
                  child: TextField(
                    controller: textCtrl,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontFamily: AppTheme.fontBody,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textInputAction: TextInputAction.search,
                    cursorColor: _kGreen,
                    cursorWidth: 1.5,
                  ),
                ),
              ),
            if (isExpanded && fadeFactor > 0.1)
              FadeTransition(
                opacity: AlwaysStoppedAnimation(fadeFactor),
                child: GestureDetector(
                  onTap: onClose,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withOpacity(0.45),
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
