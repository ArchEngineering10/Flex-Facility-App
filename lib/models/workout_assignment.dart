// ================================
// workout_assignment.dart
// Workout Assignment Model with Lifecycle Management
// ================================

import 'package:cloud_firestore/cloud_firestore.dart';

enum AssignmentStatus { active, archived, deassigned }

class WorkoutAssignment {
  final String id;
  final String clientId;
  final String clientName;
  final String workoutId;
  final String workoutName;
  final String workoutType; // 'standard' or 'custom'
  final DateTime startDate;
  final DateTime endDate;
  final DateTime assignedAt;
  final AssignmentStatus status;
  final String adminId;
  final String adminName;

  WorkoutAssignment({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.workoutId,
    required this.workoutName,
    required this.workoutType,
    required this.startDate,
    required this.endDate,
    required this.assignedAt,
    required this.status,
    required this.adminId,
    required this.adminName,
  });

  // Calculate days remaining
  int get daysRemaining {
    return endDate.difference(DateTime.now()).inDays;
  }

  // Check if expired
  bool get isExpired {
    return DateTime.now().isAfter(endDate);
  }

  // Check if active
  bool get isActive {
    return status == AssignmentStatus.active && !isExpired;
  }

  // Format date for display (e.g., "June 30, 2026")
  String get formattedEndDate {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[endDate.month - 1]} ${endDate.day}, ${endDate.year}';
  }

  String get formattedStartDate {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[startDate.month - 1]} ${startDate.day}, ${startDate.year}';
  }

  // Convert to Firestore document
  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'clientName': clientName,
    'workoutId': workoutId,
    'workoutName': workoutName,
    'workoutType': workoutType,
    'startDate': startDate,
    'endDate': endDate,
    'assignedAt': assignedAt,
    'status': status.toString().split('.').last,
    'adminId': adminId,
    'adminName': adminName,
  };

  // Create from Firestore document
  factory WorkoutAssignment.fromJson(String docId, Map<String, dynamic> json) {
    return WorkoutAssignment(
      id: docId,
      clientId: json['clientId'] ?? '',
      clientName: json['clientName'] ?? 'Unknown',
      workoutId: json['workoutId'] ?? '',
      workoutName: json['workoutName'] ?? 'Untitled',
      workoutType: json['workoutType'] ?? 'standard',
      startDate: (json['startDate'] as Timestamp).toDate(),
      endDate: (json['endDate'] as Timestamp).toDate(),
      assignedAt: (json['assignedAt'] as Timestamp).toDate(),
      status: _parseStatus(json['status'] ?? 'active'),
      adminId: json['adminId'] ?? '',
      adminName: json['adminName'] ?? 'Admin',
    );
  }

  static AssignmentStatus _parseStatus(String status) {
    switch (status) {
      case 'active':
        return AssignmentStatus.active;
      case 'archived':
        return AssignmentStatus.archived;
      case 'deassigned':
        return AssignmentStatus.deassigned;
      default:
        return AssignmentStatus.active;
    }
  }
}
