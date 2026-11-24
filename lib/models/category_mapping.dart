import 'dart:convert';

class CategoryMapping {
  final String category;
  final List<String> keywords;

  CategoryMapping({
    required this.category,
    required this.keywords,
  });

  /// Check if text (message or payee name) matches any of the keywords
  bool matches(String text) {
    if (text.trim().isEmpty) return false;
    final lower = text.toLowerCase();
    for (final k in keywords) {
      final cleanK = k.trim().toLowerCase();
      if (cleanK.isNotEmpty && lower.contains(cleanK)) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'keywords': keywords,
    };
  }

  factory CategoryMapping.fromMap(Map<String, dynamic> map) {
    return CategoryMapping(
      category: map['category'] ?? '',
      keywords: (map['keywords'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [],
    );
  }

  String toJson() => json.encode(toMap());

  factory CategoryMapping.fromJson(String source) =>
      CategoryMapping.fromMap(json.decode(source));

  CategoryMapping copyWith({
    String? category,
    List<String>? keywords,
  }) {
    return CategoryMapping(
      category: category ?? this.category,
      keywords: keywords ?? List.from(this.keywords),
    );
  }
}
