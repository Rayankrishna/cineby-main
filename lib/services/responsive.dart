import 'package:flutter/widgets.dart';

int posterGridColumns(double width) {
  if (width >= 1500) return 7;
  if (width >= 1200) return 6;
  if (width >= 950) return 5;
  if (width >= 700) return 4;
  return 3;
}

double contentMaxWidth(double width) {
  if (width >= 1200) return 1100;
  if (width >= 900) return 880;
  if (width >= 700) return double.infinity;
  return double.infinity;
}

bool isWide(BuildContext context) =>
    MediaQuery.of(context).size.width >= 700;

class CenteredMaxWidth extends StatelessWidget {
  const CenteredMaxWidth({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final maxW = contentMaxWidth(width);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
