class TitheCard {
  final String id;
  final String tenantId;
  final String memberId;
  final String memberName;
  final String? memberEmail;
  final String? memberPhone;
  final double totalTitheAmount;
  final int titheCount;
  final String frequency;
  final DateTime lastTitheDate;
  final List<TitheRecord> recentTithes;
  final String? qrCodeData;

  TitheCard({
    required this.id,
    required this.tenantId,
    required this.memberId,
    required this.memberName,
    this.memberEmail,
    this.memberPhone,
    this.totalTitheAmount = 0,
    this.titheCount = 0,
    this.frequency = 'irregular',
    required this.lastTitheDate,
    this.recentTithes = const [],
    this.qrCodeData,
  });

  factory TitheCard.fromMap(Map<String, dynamic> map, {List<TitheRecord> recentTithes = const []}) {
    return TitheCard(
      id: map['id']?.toString() ?? '',
      tenantId: map['tenant_id']?.toString() ?? '',
      memberId: map['member_id']?.toString() ?? '',
      memberName: map['member_name']?.toString() ?? '',
      memberEmail: map['member_email']?.toString(),
      memberPhone: map['member_phone']?.toString(),
      totalTitheAmount: (map['total_tithe_amount'] as num?)?.toDouble() ?? 0,
      titheCount: (map['tithe_count'] as num?)?.toInt() ?? 0,
      frequency: map['frequency']?.toString() ?? 'irregular',
      lastTitheDate: map['last_tithe_date'] != null ? DateTime.parse(map['last_tithe_date'].toString()) : DateTime.now(),
      recentTithes: recentTithes,
      qrCodeData: map['qr_data'],
    );
  }
}

class TitheRecord {
  final String id;
  final double amount;
  final String currency;
  final DateTime date;
  final String? paymentMethod;
  final String status;

  TitheRecord({
    required this.id,
    required this.amount,
    this.currency = 'ZMW',
    required this.date,
    this.paymentMethod,
    this.status = 'confirmed',
  });

  factory TitheRecord.fromMap(Map<String, dynamic> map) {
    return TitheRecord(
      id: map['id']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency']?.toString() ?? 'ZMW',
      date: map['given_at'] != null ? DateTime.parse(map['given_at'].toString()) : DateTime.now(),
      paymentMethod: map['payment_method']?.toString(),
      status: map['status']?.toString() ?? 'confirmed',
    );
  }
}