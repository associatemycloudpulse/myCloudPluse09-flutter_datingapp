import 'package:flutter/material.dart';

/// Shows a floating snack from the top of the screen (WhatsApp-style alert).
void showTopSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  final messenger = ScaffoldMessenger.of(context);
  final height = MediaQuery.sizeOf(context).height;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: height - 120,
        ),
        dismissDirection: DismissDirection.up,
      ),
    );
}
