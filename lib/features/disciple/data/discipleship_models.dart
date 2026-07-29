class Mentor {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? phone;
  final String? bio;

  Mentor({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.phone,
    this.bio,
  });

  factory Mentor.fromMap(Map<String, dynamic> map) {
    return Mentor(
      id: map['id']?.toString() ?? '',
      name: map['full_name']?.toString() ?? 'Unknown',
      avatarUrl: map['avatar_url']?.toString(),
      phone: map['phone_number']?.toString(),
      bio: map['bio']?.toString(),
    );
  }
}

class Disciple {
  final String id;
  final String name;
  final String? avatarUrl;
  final String status;
  final DateTime? startedAt;
  final int completedMilestones;
  final int totalMilestones;

  Disciple({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.status = 'active',
    this.startedAt,
    this.completedMilestones = 0,
    this.totalMilestones = 8,
  });

  factory Disciple.fromMap(Map<String, dynamic> map) {
    final mentee = map['mentee'] as Map<String, dynamic>?;
    return Disciple(
      id: mentee?['id']?.toString() ?? map['mentee_id']?.toString() ?? '',
      name: mentee?['full_name']?.toString() ?? 'Unknown',
      avatarUrl: mentee?['avatar_url']?.toString(),
      status: map['status']?.toString() ?? 'active',
      startedAt: map['started_at'] != null
          ? DateTime.tryParse(map['started_at'].toString())
          : null,
    );
  }
}

class DiscipleshipMilestone {
  final String id;
  final String discipleId;
  final String title;
  final String? description;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;

  DiscipleshipMilestone({
    required this.id,
    required this.discipleId,
    required this.title,
    this.description,
    this.status = 'pending',
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory DiscipleshipMilestone.fromMap(Map<String, dynamic> map) {
    return DiscipleshipMilestone(
      id: map['id']?.toString() ?? '',
      discipleId: map['disciple_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString(),
      status: map['status']?.toString() ?? 'pending',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'disciple_id': discipleId,
    'title': title,
    'description': description,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
  };

  bool get isCompleted => status == 'completed' || completedAt != null;
}

class DiscipleshipPlan {
  final String id;
  final String title;
  final String? description;
  final int order;

  DiscipleshipPlan({
    required this.id,
    required this.title,
    this.description,
    required this.order,
  });

  factory DiscipleshipPlan.fromMap(Map<String, dynamic> map) {
    return DiscipleshipPlan(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString(),
      order: int.tryParse(map['order']?.toString() ?? '0') ?? 0,
    );
  }

  static const List<Map<String, dynamic>> defaultPlans = [
    {'title': 'Water Baptism', 'description': 'Understanding and receiving water baptism', 'order': 1},
    {'title': 'Bible Reading Plan', 'description': 'Daily Bible reading habit', 'order': 2},
    {'title': 'Prayer Foundation', 'description': 'Building a prayer life', 'order': 3},
    {'title': 'Church Membership', 'description': 'Understanding church membership', 'order': 4},
    {'title': 'Spiritual Gifts', 'description': 'Discover your spiritual gifts', 'order': 5},
    {'title': 'Worship Lifestyle', 'description': 'Living a life of worship', 'order': 6},
    {'title': 'Evangelism Training', 'description': 'Sharing your faith', 'order': 7},
    {'title': 'Leadership Development', 'description': 'Growing as a leader', 'order': 8},
  ];
}
