import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  final String title;
  final String description;
  final String assignedToId;
  final String assignedToName;
  final String createdBy;
  final DateTime dueDate;
  final bool isCompleted;
  final String completionNote;
  final String priority;
  final String completedBy;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedToId,
    required this.assignedToName,
    required this.createdBy,
    required this.dueDate,
    this.isCompleted = false,
    this.completionNote = '',
    this.priority = 'Normal',
    this.completedBy = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'assignedToId': assignedToId,
      'assignedToName': assignedToName,
      'createdBy': createdBy,
      'dueDate': Timestamp.fromDate(dueDate),
      'isCompleted': isCompleted,
      'completionNote': completionNote,
      'priority': priority,
      'completedBy': completedBy,
    };
  }

  factory Task.fromMap(String id, Map<String, dynamic> map) {
    return Task(
      id: id,
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      assignedToId: map['assignedToId'] ?? '',
      assignedToName: map['assignedToName'] ?? 'Unknown',
      createdBy: map['createdBy'] ?? '',
      dueDate: (map['dueDate'] as Timestamp).toDate(),
      isCompleted: map['isCompleted'] ?? false,
      completionNote: map['completionNote'] ?? '',
      priority: map['priority'] ?? 'Normal',
      completedBy: map['completedBy'] ?? '',
    );
  }
}
