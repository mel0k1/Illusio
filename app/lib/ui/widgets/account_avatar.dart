import 'dart:io';

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.controller,
    required this.name,
    this.radius = 14,
    this.letterStyle,
    this.idleColor,
    this.onIdleColor,
  });

  final AppController controller;
  final String name;
  final double radius;
  final TextStyle? letterStyle;
  final Color? idleColor;
  final Color? onIdleColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = controller.avatarFile;
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: path == null
          ? (idleColor ?? scheme.primaryContainer)
          : scheme.surfaceContainerHigh,
      foregroundImage: path == null ? null : FileImage(File(path)),
      child: path == null
          ? Text(
              letter,
              style: (letterStyle ?? Theme.of(context).textTheme.labelMedium)
                  ?.copyWith(color: onIdleColor ?? scheme.onPrimaryContainer),
            )
          : null,
    );
  }
}
