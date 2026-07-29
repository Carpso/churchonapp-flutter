
class Job {
  final String id;
  final String title;
  final String company;
  final String location;
  final String type; // Full-time, Volunteer, etc.
  final String description;
  final String? salary;
  final String contact;
  final String employerId;
  final DateTime createdAt;

  final bool isFeatured;

  bool get isPromoted => isFeatured;

  Job({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.type,
    required this.description,
    this.salary,
    required this.contact,
    required this.employerId,
    required this.createdAt,
    this.isFeatured = false,
  });

  factory Job.fromMap(Map<String, dynamic> map) {
    return Job(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      company: map['company']?.toString() ?? '',
      location: map['location']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      salary: map['salary']?.toString(),
      contact: map['contact']?.toString() ?? '',
      employerId: map['employer_id']?.toString() ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'].toString()) : DateTime.now(),
      isFeatured: map['is_featured'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'company': company,
      'location': location,
      'type': type,
      'description': description,
      'salary': salary,
      'contact': contact,
      'employer_id': employerId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class JobApplication {
  final String id;
  final String jobId;
  final String applicantId;
  final String applicantName;
  final String status; // pending, accepted, rejected
  final DateTime createdAt;

  JobApplication({
    required this.id,
    required this.jobId,
    required this.applicantId,
    required this.applicantName,
    required this.status,
    required this.createdAt,
  });

  factory JobApplication.fromMap(Map<String, dynamic> map) {
    return JobApplication(
      id: map['id'],
      jobId: map['job_id'],
      applicantId: map['applicant_id'],
      applicantName: map['applicant_name'] ?? "Anonymous Believer",
      status: map['status'] ?? 'pending',
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'job_id': jobId,
      'applicant_id': applicantId,
      'applicant_name': applicantName,
      'status': status,
    };
  }
}

