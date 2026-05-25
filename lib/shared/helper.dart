import 'package:flutter/material.dart';

String formatFilterString(String value) {
  if (value == "ASSIGNMENT_PENDING") return "Assignment pending";
  if (value == "NEWLEADS") return "New Leads";

  // General formatting: remove underscores and Title Case
  return value.replaceAll('_', ' ').toLowerCase().split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }).join(' ');
}

void removeFocus(BuildContext context) {
  FocusScope.of(context).requestFocus(FocusNode());
  return;
}
