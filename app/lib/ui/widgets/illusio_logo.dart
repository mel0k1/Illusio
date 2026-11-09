import 'package:flutter/material.dart';

class IllusioLogo extends StatelessWidget {
  const IllusioLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Image.asset(
      'assets/brand/splash.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}
