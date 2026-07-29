enum Testament { old, nt }

class BibleBook {
  final String name;
  final String abbreviation;
  final Testament testament;
  final int chapters;
  final String description;
  final String testamentOrder;
  final int bookOrder;
  final List<String> alternateNames;

  const BibleBook({
    required this.name,
    required this.abbreviation,
    required this.testament,
    required this.chapters,
    required this.description,
    required this.testamentOrder,
    required this.bookOrder,
    this.alternateNames = const [],
  });

  factory BibleBook.fromJson(Map<String, dynamic> json) {
    return BibleBook(
      name: json['name'] ?? '',
      abbreviation: json['abbreviation'] ?? json['abbrev'] ?? '',
      testament: json['testament'] == 'OT' ? Testament.old : Testament.nt,
      chapters: json['chapters'] ?? json['chapterCount'] ?? 0,
      description: json['description'] ?? json['summary'] ?? '',
      testamentOrder: json['testamentOrder'] ?? json['testament_order'] ?? '',
      bookOrder: json['bookOrder'] ?? json['book_order'] ?? json['order'] ?? 0,
      alternateNames: List<String>.from(json['alternateNames'] ?? json['alternate_names'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'abbreviation': abbreviation,
        'testament': testament == Testament.old ? 'OT' : 'NT',
        'chapters': chapters,
        'description': description,
        'testamentOrder': testamentOrder,
        'bookOrder': bookOrder,
        'alternateNames': alternateNames,
      };

  BibleBook copyWith({
    String? name,
    String? abbreviation,
    Testament? testament,
    int? chapters,
    String? description,
    String? testamentOrder,
    int? bookOrder,
    List<String>? alternateNames,
  }) {
    return BibleBook(
      name: name ?? this.name,
      abbreviation: abbreviation ?? this.abbreviation,
      testament: testament ?? this.testament,
      chapters: chapters ?? this.chapters,
      description: description ?? this.description,
      testamentOrder: testamentOrder ?? this.testamentOrder,
      bookOrder: bookOrder ?? this.bookOrder,
      alternateNames: alternateNames ?? this.alternateNames,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BibleBook && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'BibleBook(name: $name, abbr: $abbreviation, chapters: $chapters)';
}

class BibleBookAuditResult {
  final List<BibleBook> books;
  final List<String> missingBooks;
  final List<String> duplicateBooks;
  final Map<String, dynamic> statistics;
  final DateTime auditedAt;

  const BibleBookAuditResult({
    required this.books,
    required this.missingBooks,
    required this.duplicateBooks,
    required this.statistics,
    required this.auditedAt,
  });

  factory BibleBookAuditResult.fromJson(Map<String, dynamic> json) {
    return BibleBookAuditResult(
      books: (json['books'] as List).map((e) => BibleBook.fromJson(e)).toList(),
      missingBooks: List<String>.from(json['missingBooks'] ?? []),
      duplicateBooks: List<String>.from(json['duplicateBooks'] ?? []),
      statistics: Map<String, dynamic>.from(json['statistics'] ?? {}),
      auditedAt: DateTime.parse(json['auditedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'books': books.map((e) => e.toJson()).toList(),
        'missingBooks': missingBooks,
        'duplicateBooks': duplicateBooks,
        'statistics': statistics,
        'auditedAt': auditedAt.toIso8601String(),
      };
}