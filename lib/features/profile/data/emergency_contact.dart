class EmergencyContact {
  final String? id;
  final String? tenantId;
  /// Owner of a PERSONAL contact. Null = a shared (tenant/global) contact.
  final String? userId;
  final String name;
  final String phone;
  final String icon;
  final String category;
  final int sortOrder;

  EmergencyContact({
    this.id,
    this.tenantId,
    this.userId,
    required this.name,
    required this.phone,
    this.icon = 'phone',
    this.category = 'emergency_service',
    this.sortOrder = 0,
  });

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      id: map['id']?.toString(),
      tenantId: map['tenant_id']?.toString(),
      userId: map['user_id']?.toString(),
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      icon: map['icon'] ?? 'phone',
      category: map['category'] ?? 'emergency_service',
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (userId != null) 'user_id': userId,
      'name': name,
      'phone': phone,
      'icon': icon,
      'category': category,
      'sort_order': sortOrder,
    };
  }

  EmergencyContact copyWith({
    String? id,
    String? tenantId,
    String? userId,
    String? name,
    String? phone,
    String? icon,
    String? category,
    int? sortOrder,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
