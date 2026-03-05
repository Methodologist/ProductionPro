import 'package:cloud_firestore/cloud_firestore.dart';
import 'company_membership.dart';

class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String companyId;
  final String role;
  final List<CompanyMembership> memberships;
  final DateTime? createdAt;
  final bool isPro;
  final String? stripeCustomerId;

  UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.companyId,
    required this.role,
    required this.memberships,
    this.createdAt,
    this.isPro = false,
    this.stripeCustomerId,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    List<CompanyMembership> parsedMemberships = [];

    if (data['memberships'] != null) {
      parsedMemberships = (data['memberships'] as List).map((m) {
        return CompanyMembership.fromMap(m);
      }).toList();
    }

    DateTime? parsedDate;
    final rawDate = data['created_at'] ?? data['createdAt'];

    if (rawDate != null) {
      if (rawDate is Timestamp) {
        parsedDate = rawDate.toDate();
      } else if (rawDate is String) {
        parsedDate = DateTime.tryParse(rawDate);
      }
    }

    return UserProfile(
      uid: uid,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      companyId: data['companyId'] ?? '',
      role: data['role'] ?? 'user',
      memberships: parsedMemberships,
      createdAt: parsedDate,
      isPro: data['isPro'] ?? false,
      stripeCustomerId: data['stripeCustomerId'],
    );
  }

  UserProfile copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? companyId,
    String? role,
    List<CompanyMembership>? memberships,
    DateTime? createdAt,
    bool? isPro,
    String? stripeCustomerId,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      companyId: companyId ?? this.companyId,
      role: role ?? this.role,
      memberships: memberships ?? this.memberships,
      createdAt: createdAt ?? this.createdAt,
      isPro: isPro ?? this.isPro,
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
    );
  }

  bool get isOwner => role == 'owner';
  bool get isBusinessAdmin => role == 'business_admin';
  bool get canManageStock => role == 'owner' || role == 'business_admin' || role == 'manager';
  bool get canManageTeam => role == 'owner' || role == 'business_admin' || role == 'manager';
}
