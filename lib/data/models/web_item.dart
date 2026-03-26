import 'package:flutter/material.dart';

class WebItem {
  final String label;
  final String url;
  final IconData? icon;
  final List<WebItem> subItems;

  WebItem({
    required this.label, 
    required this.url, 
    this.icon,
    this.subItems = const [],
  });
}


