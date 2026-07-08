// ================================
// admin_workout_assignment_screen.dart
// Manage Workout Assignments with Lifecycle Control
// ================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/workout_assignment.dart';
import 'package:intl/intl.dart';

class AdminWorkoutAssignmentScreen extends StatefulWidget {
  const AdminWorkoutAssignmentScreen({super.key});

  @override
  State<AdminWorkoutAssignmentScreen> createState() => _AdminWorkoutAssignmentScreenState();
}

class _AdminWorkoutAssignmentScreenState extends State<AdminWorkoutAssignmentScreen> {
  final Color _primaryColor = const Color(0xFF1C2D5E);
  final Color _secondaryColor = const Color(0xFF00CEFF);
  final Color _successColor = const Color(0xFF00B894);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<WorkoutAssignment> _assignments = [];
  bool _isLoading = true;
  AssignmentStatus? _filterStatus;

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _firestore
          .collection('workout_assignments')
          .orderBy('assignedAt', descending: true)
          .get();

      _assignments = snapshot.docs
          .map((doc) => WorkoutAssignment.fromJson(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Error loading assignments: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<WorkoutAssignment> get _filteredAssignments {
    if (_filterStatus == null) return _assignments;
    return _assignments.where((a) => a.status == _filterStatus).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assigned Workouts'),
        backgroundColor: _primaryColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildFilterChip('All', null),
                const SizedBox(width: 8),
                _buildFilterChip('Active', AssignmentStatus.active),
                const SizedBox(width: 8),
                _buildFilterChip('Archived', AssignmentStatus.archived),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: _primaryColor))
                : _filteredAssignments.isEmpty
                    ? Center(
                        child: Text(
                          'No assignments found',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filteredAssignments.length,
                        itemBuilder: (context, index) {
                          return _buildAssignmentCard(_filteredAssignments[index]);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAssignmentDialog(),
        backgroundColor: _primaryColor,
        label: const Text('New Assignment'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFilterChip(String label, AssignmentStatus? status) {
    final isSelected = _filterStatus == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterStatus = selected ? status : null);
      },
      backgroundColor: Colors.white,
      selectedColor: _secondaryColor.withValues(alpha: 0.3),
      labelStyle: TextStyle(
        color: isSelected ? _secondaryColor : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? _secondaryColor : Colors.grey[300]!,
      ),
    );
  }

  Widget _buildAssignmentCard(WorkoutAssignment assignment) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (assignment.status) {
      case AssignmentStatus.active:
        statusColor = _successColor;
        statusLabel = 'ACTIVE';
        statusIcon = Icons.check_circle;
        break;
      case AssignmentStatus.archived:
        statusColor = Colors.grey;
        statusLabel = 'ARCHIVED';
        statusIcon = Icons.archive;
        break;
      case AssignmentStatus.deassigned:
        statusColor = Colors.red;
        statusLabel = 'DEASSIGNED';
        statusIcon = Icons.cancel;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: statusColor,
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          assignment.clientName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          assignment.workoutName,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start: ${assignment.formattedStartDate}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'End: ${assignment.formattedEndDate}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  if (assignment.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _secondaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${assignment.daysRemaining} days left',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _secondaryColor,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (assignment.status != AssignmentStatus.deassigned &&
                      assignment.status != AssignmentStatus.archived)
                    TextButton.icon(
                      onPressed: () => _showExtendDatesDialog(assignment),
                      icon: const Icon(Icons.edit),
                      label: const Text('Extend'),
                      style: TextButton.styleFrom(foregroundColor: _secondaryColor),
                    ),
                  const SizedBox(width: 8),
                  if (assignment.status != AssignmentStatus.archived &&
                      assignment.status != AssignmentStatus.deassigned)
                    TextButton.icon(
                      onPressed: () => _archiveAssignment(assignment),
                      icon: const Icon(Icons.archive),
                      label: const Text('Archive'),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _deassignWorkout(assignment),
                    icon: const Icon(Icons.close),
                    label: const Text('Deassign'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAssignmentDialog() async {
    String? selectedClientId;
    String? selectedClientName;
    String? selectedWorkoutId;
    String? selectedWorkoutName;
    String? selectedWorkoutType;
    DateTime? startDate;
    DateTime? endDate;

    List<Map<String, dynamic>> clients = [];
    List<Map<String, dynamic>> workouts = [];

    // Load clients
    final clientSnapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'client')
        .get();

    clients = clientSnapshot.docs
        .map((doc) => {
              'id': doc.id,
              'name': doc.data()['name'] ?? 'Unknown',
            })
        .toList();

    // Load standard workouts
    final standardSnapshot = await _firestore.collection('standard_workouts').get();
    for (var doc in standardSnapshot.docs) {
      workouts.add({
        'id': doc.id,
        'name': doc.data()['name'] ?? 'Untitled',
        'type': 'standard',
      });
    }

    // Load custom workouts
    final customSnapshot = await _firestore.collection('custom_workout_groups').get();
    for (var doc in customSnapshot.docs) {
      workouts.add({
        'id': doc.id,
        'name': doc.data()['name'] ?? 'Untitled',
        'type': 'custom',
      });
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Assign New Workout'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Client dropdown
                Text(
                  'Select Client',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedClientId,
                  hint: const Text('Choose a client'),
                  items: clients
                      .map((c) => DropdownMenuItem<String>(
                            value: c['id'] as String,
                            child: Text(c['name'] as String),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedClientId = value;
                      if (value != null) {
                        selectedClientName =
                            clients.firstWhere((c) => c['id'] == value)['name'] as String?;
                      }
                    });
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Workout dropdown
                Text(
                  'Select Workout',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedWorkoutId,
                  hint: const Text('Choose a workout'),
                  items: workouts
                      .map((w) => DropdownMenuItem<String>(
                            value: w['id'] as String,
                            child: Text(w['name'] as String),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedWorkoutId = value;
                      if (value != null) {
                        final workout = workouts.firstWhere((w) => w['id'] == value);
                        selectedWorkoutName = workout['name'] as String?;
                        selectedWorkoutType = workout['type'] as String?;
                      }
                    });
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Start date picker
                Text(
                  'Start Date',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => startDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: _primaryColor, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          startDate != null
                              ? DateFormat('MMM dd, yyyy').format(startDate!)
                              : 'Select start date',
                          style: TextStyle(
                            color: startDate != null ? Colors.black : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // End date picker
                Text(
                  'End Date',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => endDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: _primaryColor, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          endDate != null
                              ? DateFormat('MMM dd, yyyy').format(endDate!)
                              : 'Select end date',
                          style: TextStyle(
                            color: endDate != null ? Colors.black : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedClientId != null &&
                      selectedWorkoutId != null &&
                      startDate != null &&
                      endDate != null)
                  ? () => _saveAssignment(
                        selectedClientId!,
                        selectedClientName!,
                        selectedWorkoutId!,
                        selectedWorkoutName!,
                        selectedWorkoutType!,
                        startDate!,
                        endDate!,
                      ).then((_) => Navigator.pop(context))
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
              ),
              child: const Text('Assign', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAssignment(
    String clientId,
    String clientName,
    String workoutId,
    String workoutName,
    String workoutType,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      await _firestore.collection('workout_assignments').add({
        'clientId': clientId,
        'clientName': clientName,
        'workoutId': workoutId,
        'workoutName': workoutName,
        'workoutType': workoutType,
        'startDate': startDate,
        'endDate': endDate,
        'assignedAt': DateTime.now(),
        'status': 'active',
        'adminId': 'current_admin_id', // Get from auth in real implementation
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Workout assigned successfully')),
        );
        _loadAssignments();
      }
    } catch (e) {
      debugPrint('Error saving assignment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showExtendDatesDialog(WorkoutAssignment assignment) async {
    DateTime? newEndDate = assignment.endDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Extend End Date'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current end date: ${assignment.formattedEndDate}',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: assignment.endDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => newEndDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, color: _primaryColor, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        newEndDate != null
                            ? DateFormat('MMM dd, yyyy').format(newEndDate!)
                            : 'Select new end date',
                        style: TextStyle(
                          color: newEndDate != null ? Colors.black : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: newEndDate != null
                  ? () async {
                      await _firestore
                          .collection('workout_assignments')
                          .doc(assignment.id)
                          .update({'endDate': newEndDate});
                      if (mounted) {
                        Navigator.pop(context);
                        _loadAssignments();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('End date updated successfully')),
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
              ),
              child: const Text('Update', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _archiveAssignment(WorkoutAssignment assignment) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Assignment?'),
        content: Text(
          'Archive "${assignment.workoutName}" for ${assignment.clientName}? '
          'This will move it to the archive section in the client app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _firestore
                  .collection('workout_assignments')
                  .doc(assignment.id)
                  .update({'status': 'archived'});
              if (mounted) {
                Navigator.pop(context);
                _loadAssignments();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Workout archived successfully')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
            ),
            child: const Text('Archive', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deassignWorkout(WorkoutAssignment assignment) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deassign Workout?'),
        content: Text(
          'Remove "${assignment.workoutName}" from ${assignment.clientName}? '
          'They will not see this workout in their app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _firestore
                  .collection('workout_assignments')
                  .doc(assignment.id)
                  .update({'status': 'deassigned'});
              if (mounted) {
                Navigator.pop(context);
                _loadAssignments();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Workout deassigned successfully')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Deassign', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
