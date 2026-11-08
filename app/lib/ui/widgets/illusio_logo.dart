import 'package:flutter/material.dart';

class IllusioLogo extends StatelessWidget {
  const IllusioLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Image.asset(
        'assets/brand/logo.jpg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
