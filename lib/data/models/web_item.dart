class WebItem {
  final String label;
  final String url;

  WebItem({required this.label, required this.url});

  factory WebItem.fromJson(Map<String, dynamic> json) {
    return WebItem(
      label: json['label'] ?? '',
      url: json['url'] ?? '',
    );
  }
}
