import 'package:flutter/material.dart';

class SqueezeButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleValue;

  /// Deeper scale held while a long-press is in progress. When `null`
  /// (default) long-press behaves exactly like before — same scale as
  /// a tap. Set to e.g. `0.92` to make the child visibly "peek" smaller
  /// for the duration of the press, then spring back on release.
  final double? longPressScaleValue;

  const SqueezeButton({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleValue = 0.95,
    this.longPressScaleValue,
  });

  @override
  State<SqueezeButton> createState() => _SqueezeButtonState();
}

class _SqueezeButtonState extends State<SqueezeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _longPressing = false;

  static const Duration _tapDuration = Duration(milliseconds: 10);
  static const Duration _longPressDownDuration = Duration(milliseconds: 160);
  static const Duration _longPressUpDuration = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: _tapDuration,
    );
    _rebuildTween(widget.scaleValue);
  }

  void _rebuildTween(double end) {
    _scaleAnimation = Tween<double>(begin: 1.0, end: end).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    // While a long-press is being held its deeper squeeze owns the
    // controller — don't let a transient tap-down event re-target it.
    if (_longPressing) return;
    _animationController.duration = _tapDuration;
    _rebuildTween(widget.scaleValue);
    _animationController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (_longPressing) return;
    _animationController.reverse();
  }

  void _onTapCancel() {
    if (_longPressing) return;
    _animationController.reverse();
  }

  void _onLongPressStart(LongPressStartDetails _) {
    final double? deeper = widget.longPressScaleValue;
    if (deeper == null) return;
    _longPressing = true;
    _animationController.duration = _longPressDownDuration;
    // Tween from CURRENT value (likely already at scaleValue from the
    // preceding tap-down) to the deeper long-press target.
    final from = _scaleAnimation.value;
    _scaleAnimation = Tween<double>(begin: from, end: deeper).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward(from: 0);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!_longPressing) return;
    _longPressing = false;
    _animationController.duration = _longPressUpDuration;
    final from = _scaleAnimation.value;
    _scaleAnimation = Tween<double>(begin: from, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _animationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final hasLongPressSqueeze = widget.longPressScaleValue != null;
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onLongPressStart: hasLongPressSqueeze ? _onLongPressStart : null,
      onLongPressEnd: hasLongPressSqueeze ? _onLongPressEnd : null,
      onLongPressCancel:
          hasLongPressSqueeze ? () => _onLongPressEnd(LongPressEndDetails()) : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
