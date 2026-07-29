enum FundraisingCategory { building, missions, youth, community, emergency, other }

enum FundraisingStatus { active, completed, cancelled }

class FundraisingVenture {
  final String id;
  final String tenantId;
  final String title;
  final String description;
  final String category;
  final double targetAmount;
  final double raisedAmount;
  final String currency;
  final String status;
  final DateTime startDate;
  final DateTime? endDate;
  final String? imageUrl;
  final bool allowOtherTenants;
  final List<String> allowedTenantIds;
  final String createdBy;
  final DateTime createdAt;
  final List<FundraisingContribution>? recentContributions;

  FundraisingVenture({
    required this.id,
    required this.tenantId,
    required this.title,
    required this.description,
    this.category = 'Other',
    required this.targetAmount,
    this.raisedAmount = 0,
    this.currency = 'ZMW',
    this.status = 'active',
    required this.startDate,
    this.endDate,
    this.imageUrl,
    this.allowOtherTenants = false,
    this.allowedTenantIds = const [],
    required this.createdBy,
    required this.createdAt,
    this.recentContributions,
  });

  factory FundraisingVenture.fromMap(Map<String, dynamic> map) {
    return FundraisingVenture(
      id: map['id'] ?? '',
      tenantId: map['tenant_id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: map['category'] ?? 'Other',
      targetAmount: (map['target_amount'] as num?)?.toDouble() ?? 0,
      raisedAmount: (map['raised_amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] ?? 'ZMW',
      status: map['status'] ?? 'active',
      startDate: map['start_date'] != null ? DateTime.parse(map['start_date']) : DateTime.now(),
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
      imageUrl: map['image_url'],
      allowOtherTenants: map['allow_other_tenants'] ?? false,
      allowedTenantIds: (map['allowed_tenant_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdBy: map['created_by'] ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      recentContributions: map['recent_contributions'] != null
          ? (map['recent_contributions'] as List)
              .map((c) => FundraisingContribution.fromMap(c))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tenant_id': tenantId,
      'title': title,
      'description': description,
      'category': category,
      'target_amount': targetAmount,
      'raised_amount': raisedAmount,
      'currency': currency,
      'status': status,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'image_url': imageUrl,
      'allow_other_tenants': allowOtherTenants,
      'allowed_tenant_ids': allowedTenantIds,
      'created_by': createdBy,
    };
  }

  FundraisingVenture copyWith({
    String? id,
    String? tenantId,
    String? title,
    String? description,
    String? category,
    double? targetAmount,
    double? raisedAmount,
    String? currency,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    String? imageUrl,
    bool? allowOtherTenants,
    List<String>? allowedTenantIds,
    String? createdBy,
    DateTime? createdAt,
    List<FundraisingContribution>? recentContributions,
  }) {
    return FundraisingVenture(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      targetAmount: targetAmount ?? this.targetAmount,
      raisedAmount: raisedAmount ?? this.raisedAmount,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      imageUrl: imageUrl ?? this.imageUrl,
      allowOtherTenants: allowOtherTenants ?? this.allowOtherTenants,
      allowedTenantIds: allowedTenantIds ?? this.allowedTenantIds,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      recentContributions: recentContributions ?? this.recentContributions,
    );
  }
}

class FundraisingContribution {
  final String id;
  final String ventureId;
  final String tenantId;
  final String? tenantName;
  final String contributorId;
  final String? contributorName;
  final double amount;
  final bool isAnonymous;
  final String? message;
  final DateTime createdAt;

  FundraisingContribution({
    required this.id,
    required this.ventureId,
    required this.tenantId,
    this.tenantName,
    required this.contributorId,
    this.contributorName,
    required this.amount,
    this.isAnonymous = false,
    this.message,
    required this.createdAt,
  });

  factory FundraisingContribution.fromMap(Map<String, dynamic> map) {
    return FundraisingContribution(
      id: map['id'] ?? '',
      ventureId: map['venture_id'] ?? '',
      tenantId: map['tenant_id'] ?? '',
      tenantName: map['tenant_name'],
      contributorId: map['contributor_id'] ?? '',
      contributorName: map['contributor_name'],
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      isAnonymous: map['is_anonymous'] ?? false,
      message: map['message'],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'venture_id': ventureId,
      'tenant_id': tenantId,
      'tenant_name': tenantName,
      'contributor_id': contributorId,
      'contributor_name': contributorName,
      'amount': amount,
      'is_anonymous': isAnonymous,
      'message': message,
    };
  }
}

extension FundraisingVentureGetters on FundraisingVenture {
  double get progressPercentage => targetAmount > 0 ? (raisedAmount / targetAmount * 100) : 0;
  int? get daysLeft => endDate?.difference(DateTime.now()).inDays;
  String get formattedRaised => 'K${raisedAmount.toStringAsFixed(0)}';
  String get formattedTarget => 'K${targetAmount.toStringAsFixed(0)}';
  int get contributorCount => recentContributions?.length ?? 0;
  FundraisingCategory get categoryEnum => FundraisingCategory.values.firstWhere(
    (c) => c.name == category.toLowerCase(), orElse: () => FundraisingCategory.other);
  FundraisingStatus get statusEnum => FundraisingStatus.values.firstWhere(
    (s) => s.name == status.toLowerCase(), orElse: () => FundraisingStatus.active);
}

extension FundraisingContributionGetters on FundraisingContribution {
  String get displayName => isAnonymous ? 'Anonymous' : (contributorName ?? 'Anonymous');
  String get formattedAmount => 'K${amount.toStringAsFixed(0)}';
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

class GroupContribution {
  final String id;
  final String tenantId;
  final String title;
  final String description;
  final double targetAmount;
  final double collectedAmount;
  final String currency;
  final String frequency;
  final String status;
  final DateTime startDate;
  final DateTime? endDate;
  final double minAmount;
  final double? maxAmount;
  final int memberCount;
  final String createdBy;
  final DateTime createdAt;

  GroupContribution({
    required this.id,
    required this.tenantId,
    required this.title,
    this.description = '',
    required this.targetAmount,
    this.collectedAmount = 0,
    this.currency = 'ZMW',
    this.frequency = 'one_time',
    this.status = 'active',
    required this.startDate,
    this.endDate,
    this.minAmount = 1,
    this.maxAmount,
    this.memberCount = 0,
    required this.createdBy,
    required this.createdAt,
  });

  factory GroupContribution.fromMap(Map<String, dynamic> map) {
    return GroupContribution(
      id: map['id'] ?? '',
      tenantId: map['tenant_id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      targetAmount: (map['target_amount'] as num?)?.toDouble() ?? 0,
      collectedAmount: (map['collected_amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] ?? 'ZMW',
      frequency: map['frequency'] ?? 'one_time',
      status: map['status'] ?? 'active',
      startDate: map['start_date'] != null ? DateTime.parse(map['start_date']) : DateTime.now(),
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
      minAmount: (map['min_amount'] as num?)?.toDouble() ?? 1,
      maxAmount: (map['max_amount'] as num?)?.toDouble(),
      memberCount: (map['member_count'] as num?)?.toInt() ?? 0,
      createdBy: map['created_by'] ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tenant_id': tenantId,
      'title': title,
      'description': description,
      'target_amount': targetAmount,
      'collected_amount': collectedAmount,
      'currency': currency,
      'frequency': frequency,
      'status': status,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'min_amount': minAmount,
      'max_amount': maxAmount,
      'created_by': createdBy,
    };
  }
}

class GroupContributionMember {
  final String id;
  final String groupId;
  final String userId;
  final String userName;
  final double pledgedAmount;
  final double paidAmount;
  final String status;
  final DateTime joinedAt;

  GroupContributionMember({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    required this.pledgedAmount,
    this.paidAmount = 0,
    this.status = 'active',
    required this.joinedAt,
  });

  factory GroupContributionMember.fromMap(Map<String, dynamic> map) {
    return GroupContributionMember(
      id: map['id'] ?? '',
      groupId: map['group_id'] ?? '',
      userId: map['user_id'] ?? '',
      userName: map['user_name'] ?? '',
      pledgedAmount: (map['pledged_amount'] as num?)?.toDouble() ?? 0,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
      status: map['status'] ?? 'active',
      joinedAt: map['joined_at'] != null ? DateTime.parse(map['joined_at']) : DateTime.now(),
    );
  }
}

class GroupContributionPayment {
  final String id;
  final String groupId;
  final String memberId;
  final String userName;
  final double amount;
  final bool isAnonymous;
  final String? message;
  final DateTime createdAt;

  GroupContributionPayment({
    required this.id,
    required this.groupId,
    required this.memberId,
    required this.userName,
    required this.amount,
    this.isAnonymous = false,
    this.message,
    required this.createdAt,
  });

  factory GroupContributionPayment.fromMap(Map<String, dynamic> map) {
    return GroupContributionPayment(
      id: map['id'] ?? '',
      groupId: map['group_id'] ?? '',
      memberId: map['member_id'] ?? '',
      userName: map['user_name'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      isAnonymous: map['is_anonymous'] ?? false,
      message: map['message'],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }
}

class FundraisingInvite {
  final String id;
  final String ventureId;
  final String fromTenantId;
  final String toTenantId;
  final String status;
  final DateTime createdAt;

  FundraisingInvite({
    required this.id,
    required this.ventureId,
    required this.fromTenantId,
    required this.toTenantId,
    this.status = 'pending',
    required this.createdAt,
  });

  factory FundraisingInvite.fromMap(Map<String, dynamic> map) {
    return FundraisingInvite(
      id: map['id'] ?? '',
      ventureId: map['venture_id'] ?? '',
      fromTenantId: map['from_tenant_id'] ?? '',
      toTenantId: map['to_tenant_id'] ?? '',
      status: map['status'] ?? 'pending',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'venture_id': ventureId,
      'from_tenant_id': fromTenantId,
      'to_tenant_id': toTenantId,
      'status': status,
    };
  }
}
