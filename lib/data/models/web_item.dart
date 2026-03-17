import 'package:flutter/material.dart';

class WebItem {
  final String label;
  final String url;
  final IconData? icon;

  WebItem({required this.label, required this.url, this.icon});

  factory WebItem.fromJson(Map<String, dynamic> json) {
    return WebItem(
      label: json['label'] ?? '',
      url: json['url'] ?? '',
    );
  }
}

