class CompanyMembership {
  final String companyId;
  final String companyName;
  String role;

  CompanyMembership({
    required this.companyId,
    required this.companyName,
    required this.role,
  });

  factory CompanyMembership.fromMap(Map<String, dynamic> data) {
    return CompanyMembership(
      companyId: data['companyId'] ?? '',
      companyName: data['companyName'] ?? 'Unknown Org',
      role: data['role'] ?? 'user',
    );
  }

  Map<String, dynamic> toMap() => {
    'companyId': companyId,
    'companyName': companyName,
    'role': role,
  };
}
