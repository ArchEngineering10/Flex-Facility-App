import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/workout_assignment.dart';

// Models
class WorkoutExercise {
  final String name;
  String? videoUrl;
  String? imageUrl;
  bool isSelected;

  WorkoutExercise({
    required this.name,
    this.videoUrl,
    this.imageUrl,
    this.isSelected = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'videoUrl': videoUrl,
    'imageUrl': imageUrl,
  };

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) => WorkoutExercise(
    name: json['name'],
    videoUrl: json['videoUrl'],
    imageUrl: json['imageUrl'],
  );
}

class WorkoutMedia {
  final String url;
  final MediaType type;

  WorkoutMedia({
    required this.url,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'type': type == MediaType.image ? 'image' : 'video',
  };

  factory WorkoutMedia.fromJson(Map<String, dynamic> json) => WorkoutMedia(
    url: json['url'],
    type: json['type'] == 'image' ? MediaType.image : MediaType.video,
  );
}

enum MediaType { image, video }

class StandardWorkout {
  final String id;
  String name;
  List<WorkoutExercise> exercises;
  List<WorkoutMedia> media;
  bool isSelected;

  StandardWorkout({
    required this.id,
    required this.name,
    required this.exercises,
    this.media = const [],
    this.isSelected = false,
  });
}

class CustomWorkoutGroup {
  final String name;
  final String emoji;
  List<WorkoutExercise> exercises;

  CustomWorkoutGroup({
    required this.name,
    required this.emoji,
    required this.exercises,
  });
}

// Main Admin Screen
class AdminWorkoutScreen extends StatefulWidget {
  const AdminWorkoutScreen({super.key});

  @override
  State<AdminWorkoutScreen> createState() => _AdminWorkoutScreenState();
}

class _AdminWorkoutScreenState extends State<AdminWorkoutScreen> with TickerProviderStateMixin {
  // Color Scheme - EXACT same colors
  final Color _primaryColor = const Color(0xFF1C2D5E);
  final Color _secondaryColor = const Color(0xFF00CEFF);
  final Color _accentColor = const Color(0xFFFD79A8);
  final Color _successColor = const Color(0xFF00B894);
  final Color _cardColor = Colors.white;
  final Color _selectedCardColor = const Color(0xFFF5F6FA);
  bool _isLoadingCustom = false;
  bool _isUpdatingCustom = false;

  // App state
  TabController? _tabController;
  TabController? _customGroupTabController;
  final List<String> _workoutTypes = ['Standard', 'Custom', 'Assigned Workouts'];
  int _selectedWorkoutType = 0;
  AssignmentStatus? _filterStatus;
  
  // Client selection
  List<String> _selectedClientIds = [];
  bool _isLoadingClients = false;

  // Search in Assigned Workouts
  String _searchQuery = '';
  
  // Standard workouts - Dynamic
  StandardWorkout? _selectedStandardWorkout;
  List<StandardWorkout> _standardWorkouts = [];
  bool _isLoadingStandard = false;
  
  // Custom workouts - Dynamic
  List<CustomWorkoutGroup> _customWorkoutGroups = [];
  final Map<String, List<String>> _selectedCustomWorkouts = {};

  // Exercise expansion state
  final Map<String, bool> _expandedExercises = {};

  // Video controller management
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, ChewieController> _chewieControllers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController!.addListener(() {
      setState(() {
        _selectedWorkoutType = _tabController!.index;
      });
    });
    _loadWorkouts();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    for (var controller in _chewieControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _createCustomGroupTabController(int groupCount) {
    _customGroupTabController?.dispose();
    _customGroupTabController = TabController(length: groupCount, vsync: this);
  }

  Future<void> _loadWorkouts() async {
    await _loadStandardWorkouts();
    await _loadCustomWorkouts();
  }

  Future<void> _loadStandardWorkouts() async {
    setState(() => _isLoadingStandard = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('standard_workouts')
          .orderBy('name')
          .get();

      _standardWorkouts = snapshot.docs.map((doc) {
        final data = doc.data();
        return StandardWorkout(
          id: doc.id,
          name: data['name'] ?? 'Untitled',
          exercises: (data['exercises'] as List? ?? [])
              .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
              .toList(),
          media: (data['media'] as List? ?? [])
              .map((m) => WorkoutMedia.fromJson(m as Map<String, dynamic>))
              .toList(),
          isSelected: false,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error loading standard workouts: $e');
    } finally {
      setState(() => _isLoadingStandard = false);
    }
  }

  Future<void> _loadCustomWorkouts() async {
    if (_customWorkoutGroups.isEmpty) {
      setState(() => _isLoadingCustom = true);
    } else {
      setState(() => _isUpdatingCustom = true);
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('custom_workout_groups')
          .orderBy('name')
          .get();

      final newGroups = snapshot.docs.map((doc) {
        final data = doc.data();
        return CustomWorkoutGroup(
          name: data['name'] ?? 'Unknown',
          emoji: data['emoji'] ?? '',
          exercises: (data['exercises'] as List? ?? [])
              .map((e) => WorkoutExercise.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      }).toList();

      _customWorkoutGroups = newGroups;

      if (_tabController != null) {
        _tabController?.dispose();
        _tabController = null;
      }

      if (_customWorkoutGroups.isNotEmpty) {
        _tabController = TabController(
          length: _customWorkoutGroups.length,
          vsync: this,
        );
        
        _tabController?.addListener(() {
          if (mounted) setState(() {});
        });
      }

      final oldSelections = Map<String, List<String>>.from(_selectedCustomWorkouts);
      _selectedCustomWorkouts.clear();
      
      for (var group in _customWorkoutGroups) {
        final existingSelections = oldSelections[group.name] ?? [];
        _selectedCustomWorkouts[group.name] = List.from(existingSelections);
        
        for (var exercise in group.exercises) {
          exercise.isSelected = _selectedCustomWorkouts[group.name]?.contains(exercise.name) ?? false;
        }
      }

    } catch (e) {
      debugPrint('Error loading custom workouts: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCustom = false;
          _isUpdatingCustom = false;
        });
      }
    }
  }
  
  // Add this method to _AdminWorkoutScreenState
  void _clearClientSelection() {
    setState(() {
      _selectedClientIds = [];
    });
  }

  // Add Standard Workout with media
  Future<void> _addStandardWorkout() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AddStandardWorkoutDialog(
        primaryColor: _primaryColor,
        accentColor: _accentColor,
      ),
    );

    if (result != null) {
      try {
        debugPrint('📥 [ADD] Dialog returned: ${result.keys.toList()}');

        // Safely extract exercises - they're already WorkoutExercise objects
        final exercises = (result['exercises'] as List?) ?? [];
        debugPrint('📥 [ADD] Exercises: ${exercises.length} items');

        // Safely extract media - they're already WorkoutMedia objects
        final media = (result['media'] as List?) ?? [];
        debugPrint('📥 [ADD] Media: ${media.length} items');

        // Convert exercises and media to JSON safely
        final exercisesJson = [];
        for (var e in exercises) {
          if (e is WorkoutExercise) {
            exercisesJson.add(e.toJson());
          }
        }

        final mediaJson = [];
        for (var m in media) {
          if (m is WorkoutMedia) {
            mediaJson.add(m.toJson());
          }
        }

        debugPrint('📝 [ADD] Converting: ${exercisesJson.length} exercises, ${mediaJson.length} media');

        final docRef = await FirebaseFirestore.instance
            .collection('standard_workouts')
            .add({
          'name': result['name'] ?? 'Untitled Workout',
          'exercises': exercisesJson,
          'media': mediaJson,
          'createdAt': FieldValue.serverTimestamp(),
        });

        debugPrint('✅ [ADD] Saved to Firestore with ID: ${docRef.id}');

        _standardWorkouts.add(StandardWorkout(
          id: docRef.id,
          name: result['name'] ?? 'Untitled Workout',
          exercises: List<WorkoutExercise>.from(exercises),
          media: List<WorkoutMedia>.from(media),
          isSelected: false,
        ));

        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Standard workout added successfully!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding workout: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _deassignWorkouts() async {
    if (_selectedClientIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select at least one client'),
          backgroundColor: Colors.orange[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isLoadingClients = true);
    
    try {
      // Fetch assigned workouts for selected clients
      final assignedWorkouts = <Map<String, dynamic>>[];
      
      for (final clientId in _selectedClientIds) {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(clientId)
            .collection('workouts')
            .orderBy('assigned_at', descending: true)
            .get();
        
        for (final doc in snapshot.docs) {
          assignedWorkouts.add({
            'id': doc.id,
            ...doc.data(),
          });
        }
      }

      setState(() => _isLoadingClients = false);

      if (assignedWorkouts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Selected clients have no assigned workouts'),
            backgroundColor: Colors.orange[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }

      final deassigned = await showDialog<bool>(
        context: context,
        builder: (context) => DeassignWorkoutsDialog(
          assignedWorkouts: assignedWorkouts,
          clientIds: _selectedClientIds,
          primaryColor: _primaryColor,
        ),
      );

      if (deassigned == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Workouts deassigned successfully!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoadingClients = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load assigned workouts: $e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // Edit Standard Workout
  Future<void> _editStandardWorkout(StandardWorkout workout) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditStandardWorkoutDialog(
        workout: workout,
        primaryColor: _primaryColor,
        accentColor: _accentColor,
      ),
    );

    if (result != null) {
      try {
        final docRef = FirebaseFirestore.instance
            .collection('standard_workouts')
            .doc(workout.id);

        // Convert exercises safely
        List<dynamic> exercisesData = [];
        if (result['exercises'] is List) {
          for (var e in result['exercises']) {
            if (e is WorkoutExercise) {
              exercisesData.add(e.toJson());
            } else if (e is Map<String, dynamic>) {
              exercisesData.add(e);
            }
          }
        }

        // Convert media safely
        List<dynamic> mediaData = [];
        if (result['media'] is List) {
          for (var m in result['media']) {
            if (m is WorkoutMedia) {
              mediaData.add(m.toJson());
            } else if (m is Map<String, dynamic>) {
              mediaData.add(m);
            }
          }
        }

        await docRef.update({
          'name': result['name'],
          
          'exercises': exercisesData,
          'media': mediaData,
        });

        workout.name = result['name'];
        workout.exercises = List<WorkoutExercise>.from(result['exercises'] ?? []);
        workout.media = List<WorkoutMedia>.from(result['media'] ?? []);

        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Workout updated successfully!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating workout: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // Add Custom Workout Group
  Future<void> _addCustomWorkoutGroup() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AddCustomGroupDialog(
        primaryColor: _primaryColor,
      ),
    );

    if (result != null) {
      try {
        await FirebaseFirestore.instance
            .collection('custom_workout_groups')
            .add({
          'name': result['name'],
          'emoji': result['emoji'],
          'exercises': [],
        });

        await _loadCustomWorkouts();

        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Custom workout group added!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding group: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // Add Exercise to Standard Workout - WITH MEDIA SUPPORT
  Future<void> _addExerciseToStandard(StandardWorkout workout) async {
    final exercise = await showDialog<WorkoutExercise>(
      context: context,
      builder: (context) => AddStandardExerciseDialog(
        primaryColor: _primaryColor,
        accentColor: _accentColor,
      ),
    );

    if (exercise != null) {
        try {
        final docRef = FirebaseFirestore.instance
            .collection('standard_workouts')
            .doc(workout.id);

        final exercises = workout.exercises.map((e) => e.toJson()).toList();
        exercises.add(exercise.toJson());

        await docRef.update({'exercises': exercises});

        workout.exercises.add(exercise);
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Exercise added successfully!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding exercise: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // Edit Exercise in Standard Workout - NEW METHOD WITH MEDIA
  Future<void> _editExerciseInStandard(StandardWorkout workout, WorkoutExercise exercise) async {
    final updatedExercise = await showDialog<WorkoutExercise>(
      context: context,
      builder: (context) => EditStandardExerciseDialog(
        exercise: exercise,
        primaryColor: _primaryColor,
        accentColor: _accentColor,
      ),
    );

    if (updatedExercise != null) {
        try {
        final index = workout.exercises.indexOf(exercise);
        workout.exercises[index] = updatedExercise;

        final exercisesJson = workout.exercises.map((e) => e.toJson()).toList();

        await FirebaseFirestore.instance
            .collection('standard_workouts')
            .doc(workout.id)
            .update({'exercises': exercisesJson});

        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Exercise updated successfully!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating exercise: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // Add Media to Standard Workout - Updated to support multiple media at once
  Future<void> _addMediaToStandard(StandardWorkout workout) async {
    final mediaList = await showDialog<List<WorkoutMedia>>(
      context: context,
      builder: (context) => AddMultiMediaDialog(
        primaryColor: _primaryColor,
      ),
    );

    if (mediaList != null && mediaList.isNotEmpty) {
        try {
        final docRef = FirebaseFirestore.instance
            .collection('standard_workouts')
            .doc(workout.id);

        final existingMedia = workout.media.map((m) => m.toJson()).toList();
        final newMedia = mediaList.map((m) => m.toJson()).toList();
        final allMedia = [...existingMedia, ...newMedia];

        await docRef.update({'media': allMedia});

        workout.media.addAll(mediaList);
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${mediaList.length} media files successfully!'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding media: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // Delete Media from Standard Workout
  Future<void> _deleteMediaFromStandard(StandardWorkout workout, WorkoutMedia media) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Delete ${media.type == MediaType.image ? 'Image' : 'Video'}',
        message: 'Are you sure you want to delete this ${media.type == MediaType.image ? 'image' : 'video'}?',
        primaryColor: _primaryColor,
      ),
    );

    if (confirmed != true) return;

    try {
      workout.media.remove(media);

      final mediaJson = workout.media.map((m) => m.toJson()).toList();

      await FirebaseFirestore.instance
          .collection('standard_workouts')
          .doc(workout.id)
          .update({'media': mediaJson});

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting media: $e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // Add Exercise to Custom Group - WITH MEDIA
  Future<void> _addExerciseToGroup(CustomWorkoutGroup group) async {
    final exercise = await showDialog<WorkoutExercise>(
      context: context,
      builder: (context) => AddExerciseDialog(
        primaryColor: _primaryColor,
        accentColor: _accentColor,
      ),
    );

    if (exercise != null) {
        try {
        final snapshot = await FirebaseFirestore.instance
            .collection('custom_workout_groups')
            .where('name', isEqualTo: group.name)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final exercises = List<Map<String, dynamic>>.from(doc['exercises'] ?? []);
          exercises.add(exercise.toJson());

          await doc.reference.update({'exercises': exercises});

          group.exercises.add(exercise);
          if (mounted) setState(() {});
            }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding exercise: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // Edit Exercise in Custom Group
  Future<void> _editExerciseInCustom(CustomWorkoutGroup group, WorkoutExercise exercise) async {
    final updatedExercise = await showDialog<WorkoutExercise>(
      context: context,
      builder: (context) => EditExerciseDialog(
        exercise: exercise,
        primaryColor: _primaryColor,
        accentColor: _accentColor,
      ),
    );

    if (updatedExercise != null) {
        try {
        final index = group.exercises.indexOf(exercise);
        group.exercises[index] = updatedExercise;

        final exercisesJson = group.exercises.map((e) => e.toJson()).toList();

        final snapshot = await FirebaseFirestore.instance
            .collection('custom_workout_groups')
            .where('name', isEqualTo: group.name)
            .get();

        if (snapshot.docs.isNotEmpty) {
          await snapshot.docs.first.reference.update({'exercises': exercisesJson});
        }

        // Update selection if name changed
        if (exercise.name != updatedExercise.name) {
          _selectedCustomWorkouts[group.name]?.remove(exercise.name);
          if (updatedExercise.isSelected) {
            _selectedCustomWorkouts[group.name]?.add(updatedExercise.name);
          }
        }

        if (mounted) setState(() {});
        } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error editing exercise: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // Delete Standard Workout
  Future<void> _deleteStandardWorkout(StandardWorkout workout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Delete Workout',
        message: 'Are you sure you want to delete "${workout.name}"?',
        primaryColor: _primaryColor,
      ),
    );

    if (confirmed == true) {
        try {
        await FirebaseFirestore.instance
            .collection('standard_workouts')
            .doc(workout.id)
            .delete();

        _standardWorkouts.remove(workout);
        if (_selectedStandardWorkout == workout) {
          _selectedStandardWorkout = null;
        }
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Workout deleted successfully!'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting workout: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // Delete Custom Group
  Future<void> _deleteCustomGroup(CustomWorkoutGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Delete Group',
        message: 'Are you sure you want to delete "${group.name}"?',
        primaryColor: _primaryColor,
      ),
    );

    if (confirmed == true) {
        try {
        final snapshot = await FirebaseFirestore.instance
            .collection('custom_workout_groups')
            .where('name', isEqualTo: group.name)
            .get();

        for (var doc in snapshot.docs) {
          await doc.reference.delete();
        }

        _selectedCustomWorkouts.remove(group.name);
        await _loadCustomWorkouts();

        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Custom workout group deleted!'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting group: $e'),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // Delete Exercise from Standard
  Future<void> _deleteExerciseFromStandard(StandardWorkout workout, WorkoutExercise exercise) async {
    try {
      workout.exercises.remove(exercise);

      final exercisesJson = workout.exercises.map((e) => e.toJson()).toList();

      await FirebaseFirestore.instance
          .collection('standard_workouts')
          .doc(workout.id)
          .update({'exercises': exercisesJson});

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting exercise: $e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // Delete Exercise from Custom
  Future<void> _deleteExerciseFromCustom(CustomWorkoutGroup group, WorkoutExercise exercise) async {
    try {
      group.exercises.remove(exercise);

      final exercisesJson = group.exercises.map((e) => e.toJson()).toList();

      final snapshot = await FirebaseFirestore.instance
          .collection('custom_workout_groups')
          .where('name', isEqualTo: group.name)
          .get();

      if (snapshot.docs.isNotEmpty) {
        await snapshot.docs.first.reference.update({'exercises': exercisesJson});
      }

      _selectedCustomWorkouts[group.name]?.remove(exercise.name);

      if (mounted) setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting exercise: $e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _selectClients() async {
    setState(() => _isLoadingClients = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'client')
          .get();

      final selected = await showDialog<List<String>>(
        context: context,
        builder: (context) => ClientSelectionDialog(
          clients: snapshot.docs,
          initiallySelected: _selectedClientIds,
          primaryColor: _primaryColor,
        ),
      );

      if (selected != null) {
        setState(() => _selectedClientIds = selected);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load clients: $e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      setState(() => _isLoadingClients = false);
    }
  }

  Widget _buildCustomWorkoutNameDialog() {
    final TextEditingController nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.edit, color: _primaryColor, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Custom Workout Name',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Workout Name',
                  hintText: 'e.g., Push Day, Full Body, Upper Power',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _primaryColor, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.fitness_center),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a workout name';
                  }
                  if (value.length < 3) {
                    return 'Workout name must be at least 3 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Examples: Push Day, Full Body, Strength Session, Athletic Training',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(context, nameController.text.trim());
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Text('Confirm'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _assignWorkouts() async {
    if (_selectedClientIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select at least one client'),
          backgroundColor: Colors.orange[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Confirm Workout Assignment',
        message: _selectedWorkoutType == 0
            ? 'Assign "${_selectedStandardWorkout?.name}" to ${_selectedClientIds.length} Clients?'
            : 'Assign ${_getWorkoutCount()} exercises to ${_selectedClientIds.length} Clients?',
        primaryColor: _primaryColor,
      ),
    );

    if (confirmed != true) return;

    // For custom workouts, ask admin for a workout name
    String? customWorkoutName;
    if (_selectedWorkoutType == 1) {
      customWorkoutName = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _buildCustomWorkoutNameDialog(),
      );

      if (!mounted) return;

      if (customWorkoutName == null || customWorkoutName.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Workout name is required'),
            backgroundColor: Colors.orange[400],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }
    }

    try {
      final assignedAt = Timestamp.now();
      const trainerName = 'Kenny Sims';

      // Prepare workout data based on type
      Map<String, dynamic> workoutData = {
        'assigned_at': assignedAt,
        'trainer': trainerName,
        'clients': _selectedClientIds,
        'type': _workoutTypes[_selectedWorkoutType].toLowerCase(),
      };

      if (_selectedWorkoutType == 0) {
        // STANDARD WORKOUT - Store full workout data with media at workout level
        if (_selectedStandardWorkout != null) {
          workoutData['workout_name'] = _selectedStandardWorkout!.name;
          workoutData['workout_media'] = _selectedStandardWorkout!.media.map((m) => m.toJson()).toList();

          // Store exercises with their data (though standard exercises don't have media)
          workoutData['exercises'] = _selectedStandardWorkout!.exercises
              .map((e) => e.toJson())
              .toList();

          // Also store in workouts map for consistency
          workoutData['workouts'] = {
            _selectedStandardWorkout!.name: _selectedStandardWorkout!.exercises
                .map((e) => e.toJson())
                .toList()
          };
        }
      } else {
        // CUSTOM WORKOUT - Store exercises with their individual media
        final Map<String, List<Map<String, dynamic>>> fullWorkoutMap = {};

        // For each group that has selected exercises
        for (var group in _customWorkoutGroups) {
          final selectedExerciseNames = _selectedCustomWorkouts[group.name] ?? [];

          if (selectedExerciseNames.isNotEmpty) {
            // Get the FULL exercise objects for selected exercises (including media URLs)
            final List<Map<String, dynamic>> selectedFullExercises = [];

            for (var exercise in group.exercises) {
              if (selectedExerciseNames.contains(exercise.name)) {
                // Add the complete exercise data with all media
                selectedFullExercises.add({
                  'name': exercise.name,
                  'videoUrl': exercise.videoUrl,  // Individual video URL
                  'imageUrl': exercise.imageUrl,  // Individual image URL
                  'isSelected': true,
                });
              }
            }

            if (selectedFullExercises.isNotEmpty) {
              fullWorkoutMap[group.name] = selectedFullExercises;
            }
          }
        }

        workoutData['workouts'] = fullWorkoutMap;

        // Also create a flattened exercises list for easier access on client side
        List<Map<String, dynamic>> allExercises = [];
        fullWorkoutMap.forEach((groupName, exercises) {
          for (var exercise in exercises) {
            allExercises.add({
              ...exercise,
              'groupName': groupName,  // Add group info for context
            });
          }
        });

        workoutData['exercises'] = allExercises;
        workoutData['workout_name'] = customWorkoutName ?? 'Custom Workout';
      }

      // ✅ DEBUG: Print the workout data to verify media URLs are included
      debugPrint('Workout Data being saved: ${workoutData.toString()}');

      // Add to master workouts collection
      final workoutRef = await FirebaseFirestore.instance
          .collection('workouts')
          .add(workoutData);

      // Assign to each selected client
      final batch = FirebaseFirestore.instance.batch();
      for (final clientId in _selectedClientIds) {
        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(clientId)
            .collection('workouts')
            .doc(workoutRef.id);

        // For each client, store the same workout data
        batch.set(ref, {
          ...workoutData,
          'assigned_at': assignedAt,
          'client_id': clientId,  // Add client ID for reference
        });
      }

      await batch.commit();


      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Workouts assigned successfully!'),
          backgroundColor: _successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      // Reset selections after successful assignment
      setState(() {
        if (_selectedWorkoutType == 0) {
          if (_selectedStandardWorkout != null) {
            _selectedStandardWorkout!.isSelected = false;
            _selectedStandardWorkout = null;
          }
        } else {
          for (var group in _customWorkoutGroups) {
            _selectedCustomWorkouts[group.name] = [];
            for (var exercise in group.exercises) {
              exercise.isSelected = false;
            }
          }
        }
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign workouts: $e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Map<String, dynamic> _getWorkoutMap() {
    if (_selectedWorkoutType == 0) {
      if (_selectedStandardWorkout == null) return {};
      return {
        _selectedStandardWorkout!.name: _selectedStandardWorkout!.exercises
            .map((e) => e.toJson())
            .toList()
      };
    } else {
      final Map<String, List<String>> workoutMap = {};
      _selectedCustomWorkouts.forEach((groupName, exerciseNames) {
        if (exerciseNames.isNotEmpty) {
          workoutMap[groupName] = exerciseNames;
        }
      });
      return workoutMap;
    }
  }

  // Helper method to check if selected clients have any assigned workouts
  Future<bool> _checkIfClientsHaveAssignedWorkouts() async {
    if (_selectedClientIds.isEmpty) return false;
    
    try {
      for (final clientId in _selectedClientIds) {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(clientId)
            .collection('workouts')
            .limit(1)
            .get();
        
        if (snapshot.docs.isNotEmpty) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error checking assigned workouts: $e');
      return false;
    }
  }

  // BUILD STANDARD WORKOUTS - Updated with workout selection only, no exercise checkboxes, bullet points
  Widget _buildStandardWorkouts() {
    if (_isLoadingStandard) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Add Workout button on right
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'add_standard',
                    onPressed: _addStandardWorkout,
                    backgroundColor: _primaryColor,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add Workout',
                    style: TextStyle(color: _primaryColor, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _standardWorkouts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.fitness_center, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No standard workouts yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add your first workout',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _standardWorkouts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final workout = _standardWorkouts[index];
                    return _WorkoutTemplateCard(
                      workout: workout,
                      isSelected: _selectedStandardWorkout == workout,
                      onSelect: () {
                        setState(() {
                          if (_selectedStandardWorkout == workout) {
                            _selectedStandardWorkout = null;
                            workout.isSelected = false;
                          } else {
                            if (_selectedStandardWorkout != null) {
                              _selectedStandardWorkout!.isSelected = false;
                            }
                            _selectedStandardWorkout = workout;
                            workout.isSelected = true;
                          }
                        });
                      },
                      onEdit: () => _editStandardWorkout(workout),
                      onAddExercise: () => _addExerciseToStandard(workout),
                      onDelete: () => _deleteStandardWorkout(workout),
                      onDeleteExercise: (exercise) => _deleteExerciseFromStandard(workout, exercise),
                      onEditExercise: (exercise) => _editExerciseInStandard(workout, exercise),
                      onDeleteMedia: (media) => _deleteMediaFromStandard(workout, media),
                      primaryColor: _primaryColor,
                      selectedCardColor: _selectedCardColor,
                      cardColor: _cardColor,
                    );
                  },
                ),
        ),
      ],
    );
  }

  // BUILD CUSTOM WORKOUTS
  Widget _buildCustomWorkouts() {
    if (_isLoadingCustom) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading workout groups...'),
          ],
        ),
      );
    }

    if (_customWorkoutGroups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No custom workout groups yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add your first group',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            FloatingActionButton.extended(
              onPressed: _addCustomWorkoutGroup,
              backgroundColor: _primaryColor,
              icon: const Icon(Icons.add),
              label: const Text('Add Group'),
            ),
          ],
        ),
      );
    }

    if (_customGroupTabController == null || _customGroupTabController!.length != _customWorkoutGroups.length) {
      _customGroupTabController?.dispose();
      _customGroupTabController = TabController(
        length: _customWorkoutGroups.length,
        vsync: this,
      );
      _customGroupTabController?.addListener(() {
        if (mounted) setState(() {});
      });
    }

    return Column(
      children: [
        if (_isUpdatingCustom)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: _primaryColor.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Updating...',
                  style: TextStyle(fontSize: 12, color: _primaryColor),
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TabBar(
                    key: ValueKey(_customWorkoutGroups.length),
                    controller: _customGroupTabController,
                    isScrollable: true,
                    labelColor: _primaryColor,
                    unselectedLabelColor: Colors.grey[600],
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(width: 3, color: _primaryColor),
                      insets: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    tabs: _customWorkoutGroups.map((group) => Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(group.emoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
                          Text(group.name, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_customGroupTabController != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.red[300],
                      onPressed: () {
                        if (_customGroupTabController != null &&
                            _customGroupTabController!.index < _customWorkoutGroups.length) {
                          _deleteCustomGroup(_customWorkoutGroups[_customGroupTabController!.index]);
                        }
                      },
                      tooltip: 'Delete current group',
                    ),
                  FloatingActionButton.small(
                    heroTag: 'add_group_${_customWorkoutGroups.length}_${DateTime.now().millisecondsSinceEpoch}',
                    onPressed: _addCustomWorkoutGroup,
                    backgroundColor: _primaryColor,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        
        // Add row with Deassign button and Add Exercise button
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Add Exercise button on right for current group
              if (_customGroupTabController != null && _customGroupTabController!.index < _customWorkoutGroups.length)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'add_exercise_${_customWorkoutGroups[_customGroupTabController!.index].name}',
                      onPressed: () => _addExerciseToGroup(_customWorkoutGroups[_customGroupTabController!.index]),
                      backgroundColor: _primaryColor,
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Add Exercise',
                      style: TextStyle(color: _primaryColor, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
            ],
          ),
        ),
        
        Expanded(
          child: _customGroupTabController == null
              ? const SizedBox()
              : TabBarView(
                  controller: _customGroupTabController,
                  children: _customWorkoutGroups.map((group) {
                    return _MuscleGroupWorkouts(
                      group: group,
                      exercises: group.exercises,
                      selected: _selectedCustomWorkouts[group.name] ?? [],
                      onSelect: (exerciseName, selected) {
                        setState(() {
                          final exercise = group.exercises.firstWhere(
                            (e) => e.name == exerciseName,
                            orElse: () => WorkoutExercise(name: exerciseName),
                          );
                          exercise.isSelected = selected;

                          // Ensure the list exists for this group
                          _selectedCustomWorkouts.putIfAbsent(group.name, () => []);

                          if (selected) {
                            _selectedCustomWorkouts[group.name]!.add(exerciseName);
                          } else {
                            _selectedCustomWorkouts[group.name]!.remove(exerciseName);
                          }
                        });
                      },
                      onAddExercise: () => _addExerciseToGroup(group),
                      onEditExercise: (exercise) => _editExerciseInCustom(group, exercise),
                      onDeleteExercise: (exercise) =>
                          _deleteExerciseFromCustom(group, exercise),
                      primaryColor: _primaryColor,
                      selectedCardColor: _selectedCardColor,
                      cardColor: _cardColor,
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Workouts', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorWeight: 2,
          isScrollable: false,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          tabs: const [
            Tab(
              icon: Icon(Icons.fitness_center, size: 28),
              text: 'Standard',
              iconMargin: EdgeInsets.only(bottom: 6),
            ),
            Tab(
              icon: Icon(Icons.category, size: 28),
              text: 'Custom',
              iconMargin: EdgeInsets.only(bottom: 6),
            ),
            Tab(
              icon: Icon(Icons.assignment_turned_in, size: 28),
              text: 'Assigned',
              iconMargin: EdgeInsets.only(bottom: 6),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStandardTab(),
          _buildCustomTab(),
          _buildAssignedTab(),
        ],
      ),
    );
  }

  Widget _buildStandardTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                icon: _isLoadingClients
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primaryColor,
                        ),
                      )
                    : const Icon(Icons.people_alt, size: 20),
                label: Text(
                  _selectedClientIds.isEmpty
                      ? 'Select Clients'
                      : '${_selectedClientIds.length} Clients selected',
                  style: TextStyle(
                    color: _selectedClientIds.isEmpty
                        ? Colors.grey[600]
                        : _primaryColor,
                  ),
                ),
                onPressed: _selectClients,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: BorderSide(
                    color: _selectedClientIds.isEmpty
                        ? Colors.grey[300]!
                        : _primaryColor,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildStandardWorkouts(),
          ),
        ),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildCustomTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                icon: _isLoadingClients
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primaryColor,
                        ),
                      )
                    : const Icon(Icons.people_alt, size: 20),
                label: Text(
                  _selectedClientIds.isEmpty
                      ? 'Select Clients'
                      : '${_selectedClientIds.length} Clients selected',
                  style: TextStyle(
                    color: _selectedClientIds.isEmpty
                        ? Colors.grey[600]
                        : _primaryColor,
                  ),
                ),
                onPressed: _selectClients,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: BorderSide(
                    color: _selectedClientIds.isEmpty
                        ? Colors.grey[300]!
                        : _primaryColor,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildCustomWorkouts(),
          ),
        ),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildAssignedTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Search Bar - Expanded
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: '🔍 Search by name, Workout...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _primaryColor, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Filter Button - Right side
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: Icon(Icons.filter_list, color: _filterStatus != null ? _primaryColor : Colors.grey[600]),
                  onPressed: _showFilterDialog,
                  tooltip: 'Filter assignments',
                ),
              ),
            ],
          ),
        ),
        // Assigned Workouts List
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildAssignedWorkouts(),
          ),
        ),
      ],
    );
  }

  void _showFilterDialog() {
    AssignmentStatus? tempFilter = _filterStatus;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Filter Assignments'),
          titleTextStyle: TextStyle(color: _primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<AssignmentStatus?>(
                  title: const Text('All', style: TextStyle(fontWeight: FontWeight.w500)),
                  value: null,
                  groupValue: tempFilter,
                  onChanged: (value) => setState(() => tempFilter = value),
                  activeColor: _primaryColor,
                ),
                RadioListTile<AssignmentStatus?>(
                  title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w500)),
                  value: AssignmentStatus.active,
                  groupValue: tempFilter,
                  onChanged: (value) => setState(() => tempFilter = value),
                  activeColor: _successColor,
                ),
                RadioListTile<AssignmentStatus?>(
                  title: const Text('Archived', style: TextStyle(fontWeight: FontWeight.w500)),
                  value: AssignmentStatus.archived,
                  groupValue: tempFilter,
                  onChanged: (value) => setState(() => tempFilter = value),
                  activeColor: Colors.orange,
                ),
                RadioListTile<AssignmentStatus?>(
                  title: const Text('Deassigned', style: TextStyle(fontWeight: FontWeight.w500)),
                  value: AssignmentStatus.deassigned,
                  groupValue: tempFilter,
                  onChanged: (value) => setState(() => tempFilter = value),
                  activeColor: Colors.red,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                this.setState(() => _filterStatus = tempFilter);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
              child: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SUBMIT BUTTON ====================

  Widget _buildSubmitButton() {
    final currentTabIndex = _tabController?.index ?? _selectedWorkoutType;
    final isEnabled = _selectedClientIds.isNotEmpty &&
        ((currentTabIndex == 0 && _selectedStandardWorkout != null) ||
            (currentTabIndex == 1 && _getWorkoutCount() > 0));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: _primaryColor.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.send, size: 20),
          label: const Text('Assign Workouts', style: TextStyle(fontSize: 16)),
          onPressed: isEnabled ? _showAssignmentTimingDialog : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isEnabled ? _primaryColor : Colors.grey[400],
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  int _getWorkoutCount() {
    int count = 0;
    for (final selections in _selectedCustomWorkouts.values) {
      count += selections.length;
    }
    return count;
  }

  // Get selected groups and their exercise counts
  Map<String, List<String>> _getSelectedGroupExercises() {
    final result = <String, List<String>>{};
    for (final group in _customWorkoutGroups) {
      final selected = _selectedCustomWorkouts[group.name] ?? [];
      if (selected.isNotEmpty) {
        result[group.name] = selected;
      }
    }
    return result;
  }

  // Check if all selections are from a single group
  String? _getSingleGroupName() {
    final selected = _getSelectedGroupExercises();
    if (selected.length == 1) {
      return selected.keys.first;
    }
    return null;
  }

  // ==================== ASSIGNMENT TIMING DIALOG ====================

  Future<void> _showAssignmentTimingDialog() async {
    String workoutName = '';
    DateTime? startDate = DateTime.now();
    DateTime? endDate = DateTime.now().add(const Duration(days: 30));
    bool needsWorkoutName = false;
    final currentTabIndex = _tabController?.index ?? _selectedWorkoutType;

    // Auto-set workout name based on type
    if (currentTabIndex == 0) {
      // Standard workout - use selected workout name
      workoutName = _selectedStandardWorkout?.name ?? '';
    } else {
      // Custom workout - check if single or multiple groups
      final singleGroup = _getSingleGroupName();
      if (singleGroup != null) {
        workoutName = singleGroup; // Auto-set to group name
      } else {
        needsWorkoutName = true; // Multiple groups - require user input
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Assign Workout'),
          titleTextStyle: TextStyle(color: _primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Workout name input (only if multiple custom groups)
                  if (needsWorkoutName) ...[
                    Text('🏋️ Workout Name', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (value) {
                        setState(() {
                          workoutName = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'e.g., Full Body Workout',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _primaryColor, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.fitness_center),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else if (workoutName.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _primaryColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, size: 18, color: _primaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Workout: $workoutName',
                              style: TextStyle(fontSize: 13, color: _primaryColor, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Start Date Picker
                  Text('📅 Start Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: startDate!, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => startDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: _secondaryColor), borderRadius: BorderRadius.circular(8), color: _secondaryColor.withValues(alpha: 0.05)),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(DateFormat('MMM dd, yyyy').format(startDate!), style: const TextStyle(color: Colors.black))]),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // End Date Picker
                  Text('📅 End Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: endDate!, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => endDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: _secondaryColor), borderRadius: BorderRadius.circular(8), color: _secondaryColor.withValues(alpha: 0.05)),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(DateFormat('MMM dd, yyyy').format(endDate!), style: const TextStyle(color: Colors.black))]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: workoutName.isNotEmpty
                  ? () {
                      Navigator.pop(ctx);
                      _assignWorkoutsWithTiming(workoutName, startDate ?? DateTime.now(), endDate ?? DateTime.now().add(const Duration(days: 30)));
                    }
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
              child: const Text('Assign', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assignWorkoutsWithTiming(String workoutName, DateTime startDate, DateTime endDate) async {
    try {
      final currentTabIndex = _tabController?.index ?? _selectedWorkoutType;
      final workoutId = currentTabIndex == 0 ? _selectedStandardWorkout!.id : '';
      final workoutType = currentTabIndex == 0 ? 'standard' : 'custom';

      // Collect exercises from selected workouts
      final exercises = <Map<String, dynamic>>[];
      if (currentTabIndex == 0 && _selectedStandardWorkout != null) {
        for (final exercise in _selectedStandardWorkout!.exercises) {
          exercises.add(exercise.toJson());
        }
      } else if (currentTabIndex == 1) {
        for (final groupName in _selectedCustomWorkouts.keys) {
          final selectedExerciseNames = _selectedCustomWorkouts[groupName] ?? [];
          final group = _customWorkoutGroups.firstWhere(
            (g) => g.name == groupName,
            orElse: () => CustomWorkoutGroup(name: '', emoji: '', exercises: []),
          );

          for (final exerciseName in selectedExerciseNames) {
            final exercise = group.exercises.firstWhere(
              (e) => e.name == exerciseName,
              orElse: () => WorkoutExercise(name: exerciseName),
            );

            exercises.add({
              'name': exercise.name,
              'imageUrl': exercise.imageUrl,
              'videoUrl': exercise.videoUrl,
            });
          }
        }
      }

      final clientCount = _selectedClientIds.length;
      debugPrint('🔥 [ASSIGN] Starting: $clientCount clients, workout=$workoutName, dates=$startDate→$endDate, exercises=${exercises.length}');

      for (final clientId in _selectedClientIds) {
        try {
          final clientSnapshot = await FirebaseFirestore.instance.collection('users').doc(clientId).get();
          final clientName = clientSnapshot.data()?['name'] ?? 'Unknown';

          // Get admin name from current user
          final adminUser = await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get();
          final adminName = adminUser.data()?['name'] ?? 'Admin';

          final assignmentData = {
            'clientId': clientId,
            'clientName': clientName,
            'workoutId': workoutId,
            'workoutName': workoutName,

            'workoutType': workoutType,
            'startDate': startDate,
            'endDate': endDate,
            'assignedAt': DateTime.now(),
            'status': 'active',
            'adminId': FirebaseAuth.instance.currentUser!.uid,
            'adminName': adminName,
            'exercises': exercises,
          };

          debugPrint('💾 [ASSIGN] Saving for $clientName: $assignmentData');

          // Save assignment to workout_assignments (used by both admin and client views)
          final docRef = await FirebaseFirestore.instance.collection('workout_assignments').add(assignmentData);
          debugPrint('✅ [ASSIGN] Saved with ID: ${docRef.id}');
        } catch (clientError) {
          debugPrint('❌ [ASSIGN] Error for client $clientId: $clientError');
        }
      }

      if (mounted) {
        setState(() {
          _selectedClientIds.clear();
          _selectedStandardWorkout = null;
          _selectedCustomWorkouts.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Assigned workouts to $clientCount clients'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [ASSIGN] Fatal error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ==================== ASSIGNED WORKOUTS SECTION ====================

  Widget _buildAssignedWorkouts() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('workout_assignments')
          .orderBy('assignedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint('⏳ [STREAM] Waiting for data...');
          return Center(child: CircularProgressIndicator(color: _primaryColor));
        }

        if (snapshot.hasError) {
          debugPrint('❌ [STREAM] Error: ${snapshot.error}');
          return Center(
            child: Text('Error loading assignments: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          debugPrint('📭 [STREAM] No documents in workout_assignments');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_turned_in, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No assignments yet', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
              ],
            ),
          );
        }

        debugPrint('📊 [STREAM] Received ${snapshot.data!.docs.length} raw docs');

        List<WorkoutAssignment> assignments = [];
        for (final doc in snapshot.data!.docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            debugPrint('📄 [PARSE] Doc ${doc.id}: status="${data['status']}", client="${data['clientName']}", workout="${data['workoutName']}"');

            final assignment = WorkoutAssignment.fromJson(doc.id, data);
            assignments.add(assignment);
            debugPrint('✅ [PARSE] Parsed: ${assignment.clientName} → ${assignment.workoutName} (status=${assignment.status})');
          } catch (e) {
            debugPrint('❌ [PARSE] Error parsing doc ${doc.id}: $e');
          }
        }

        debugPrint('📋 [FILTER] Total parsed: ${assignments.length}, filterStatus=$_filterStatus, searchQuery="$_searchQuery"');

        // Filter by status
        var filtered = _filterStatus == null
            ? assignments
            : assignments.where((a) => a.status == _filterStatus).toList();

        debugPrint('🔍 [FILTER] After status filter: ${filtered.length} assignments');

        // Filter by search query (name, workout, or dates)
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          filtered = filtered.where((a) {
            // Search by client name or workout name
            if (a.clientName.toLowerCase().contains(query) || a.workoutName.toLowerCase().contains(query)) {
              return true;
            }

            // Search by dates (year, month, date range)
            final startDateStr = a.formattedStartDate.toLowerCase();
            final endDateStr = a.formattedEndDate.toLowerCase();

            // Check if query matches start or end date
            if (startDateStr.contains(query) || endDateStr.contains(query)) {
              return true;
            }

            // Check for year-only search (e.g., "2026")
            if (query.length == 4 && int.tryParse(query) != null) {
              final year = int.parse(query);
              if (a.startDate.year == year || a.endDate.year == year) {
                return true;
              }
            }

            // Check for month-year search (e.g., "April 2026")
            if (query.contains(' ')) {
              final parts = query.split(' ');
              if (parts.length >= 2) {
                final monthStr = parts[0];
                final yearStr = parts[parts.length - 1];
                if (int.tryParse(yearStr) != null) {
                  final year = int.parse(yearStr);
                  final months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
                  final monthIndex = months.indexOf(monthStr.substring(0, 3));
                  if (monthIndex != -1) {
                    if ((a.startDate.month == monthIndex + 1 && a.startDate.year == year) ||
                        (a.endDate.month == monthIndex + 1 && a.endDate.year == year)) {
                      return true;
                    }
                  }
                }
              }
            }

            return false;
          }).toList();
          debugPrint('🔍 [FILTER] After search filter: ${filtered.length} assignments');
        }

        if (filtered.isEmpty) {
          debugPrint('❌ [FILTER] No results after filtering');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isNotEmpty ? 'No assignments found' : 'No assignments in this filter',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        debugPrint('✅ [DISPLAY] Showing ${filtered.length} filtered assignments');
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: filtered.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildAssignmentCard(filtered[index]),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, AssignmentStatus? status) {
    final isSelected = _filterStatus == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => setState(() => _filterStatus = selected ? status : null),
      backgroundColor: Colors.white,
      selectedColor: _secondaryColor.withValues(alpha: 0.3),
      labelStyle: TextStyle(color: isSelected ? _secondaryColor : Colors.grey[700], fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      side: BorderSide(color: isSelected ? _secondaryColor : Colors.grey[300]!),
    );
  }

  Widget _buildAssignmentCard(WorkoutAssignment assignment) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (assignment.status) {
      case AssignmentStatus.active:
        statusColor = _successColor;
        statusLabel = 'Active';
        statusIcon = Icons.check_circle;
      case AssignmentStatus.archived:
        statusColor = Colors.grey;
        statusLabel = 'Archived';
        statusIcon = Icons.archive;
      case AssignmentStatus.deassigned:
        statusColor = Colors.red;
        statusLabel = 'Deassigned';
        statusIcon = Icons.cancel;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: statusColor, width: 4))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Client name | Menu
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '👤 ${assignment.clientName}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'extend' && assignment.status == AssignmentStatus.active) {
                        _showExtendDialog(assignment);
                      } else if (action == 'archive') {
                        _archiveAssignment(assignment);
                      } else if (action == 'deassign') {
                        _deassignAssignment(assignment);
                      } else if (action == 'reassign') {
                        _reassignAssignment(assignment);
                      } else if (action == 'restore') {
                        _restoreAssignment(assignment);
                      } else if (action == 'delete') {
                        _deleteAssignmentPermanently(assignment);
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      if (assignment.status == AssignmentStatus.active) {
                        return [
                          const PopupMenuItem(value: 'extend', child: Text('Extend')),
                          const PopupMenuItem(value: 'archive', child: Text('Archive')),
                          const PopupMenuItem(value: 'deassign', child: Text('Deassign')),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete', style: TextStyle(color: Colors.red[400])),
                          ),
                        ];
                      } else if (assignment.status == AssignmentStatus.archived) {
                        return [
                          const PopupMenuItem(value: 'restore', child: Text('Restore')),
                          const PopupMenuItem(value: 'deassign', child: Text('Deassign')),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete', style: TextStyle(color: Colors.red[400])),
                          ),
                        ];
                      } else if (assignment.status == AssignmentStatus.deassigned) {
                        return [
                          const PopupMenuItem(value: 'reassign', child: Text('Reassign')),
                          const PopupMenuItem(value: 'archive', child: Text('Archive')),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete', style: TextStyle(color: Colors.red[400])),
                          ),
                        ];
                      }
                      return [];
                    },
                    icon: const Icon(Icons.more_vert, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 2: Workout name | Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '🏋️ ${assignment.workoutName}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 13, color: statusColor),
                        const SizedBox(width: 4),
                        Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 3: Exercise count only
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('workout_assignments').doc(assignment.id).get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Text('💪 Loading...', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500));
                  }
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  final exercises = (data?['exercises'] as List?) ?? [];
                  return Text(
                    '💪 ${exercises.length} Exercise${exercises.length != 1 ? "s" : ""}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                  );
                },
              ),
              const SizedBox(height: 8),

              // Row 4: Date range + Days remaining
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '📅 ${assignment.formattedStartDate} → ${assignment.formattedEndDate}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (assignment.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: _successColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer, size: 12, color: _successColor),
                          const SizedBox(width: 3),
                          Text('${assignment.daysRemaining}d left', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _successColor)),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(18)),
                      child: Text(assignment.status == AssignmentStatus.archived ? 'Archived' : 'Expired', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // View Exercises Button (Expandable)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _expandedExercises[assignment.id] =
                        !(_expandedExercises[assignment.id] ?? false);
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      _expandedExercises[assignment.id] ?? false
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: _primaryColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _expandedExercises[assignment.id] ?? false
                          ? 'Hide Exercises'
                          : 'View Exercises',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primaryColor),
                    ),
                  ],
                ),
              ),

              // Expandable Exercises Section
              if (_expandedExercises[assignment.id] ?? false) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: Colors.grey[200]),
                const SizedBox(height: 14),
                _buildAssignmentExercisesSection(assignment),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showExtendDialog(WorkoutAssignment assignment) async {
    DateTime? newDate = assignment.endDate;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Extend End Date'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current: ${assignment.formattedEndDate}'),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: assignment.endDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (picked != null) setState(() => newDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey[400]!), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [Icon(Icons.calendar_today, color: _primaryColor, size: 20), const SizedBox(width: 12), Text(newDate != null ? DateFormat('MMM dd, yyyy').format(newDate!) : 'Select date', style: TextStyle(color: newDate != null ? Colors.black : Colors.grey[600]))]),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(onPressed: newDate != null ? () async {
              await FirebaseFirestore.instance.collection('workout_assignments').doc(assignment.id).update({'endDate': newDate});
              if (mounted) { Navigator.pop(ctx); setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated successfully'))); }
            } : null, style: ElevatedButton.styleFrom(backgroundColor: _primaryColor), child: const Text('Update', style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Future<void> _archiveAssignment(WorkoutAssignment assignment) async {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Archive?'),
      content: Text('Archive "${assignment.workoutName}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          await FirebaseFirestore.instance.collection('workout_assignments').doc(assignment.id).update({'status': 'archived'});
          if (mounted) { Navigator.pop(ctx); setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Archived'))); }
        }, style: ElevatedButton.styleFrom(backgroundColor: _primaryColor), child: const Text('Archive', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  Future<void> _deassignAssignment(WorkoutAssignment assignment) async {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Deassign?'),
      content: Text('Remove "${assignment.workoutName}" from ${assignment.clientName}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          await FirebaseFirestore.instance.collection('workout_assignments').doc(assignment.id).update({'status': 'deassigned'});
          if (mounted) { Navigator.pop(ctx); setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Deassigned'), backgroundColor: Colors.red)); }
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Deassign', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  Future<void> _deleteAssignmentPermanently(WorkoutAssignment assignment) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Assignment Permanently?'),
        titleTextStyle: TextStyle(color: Colors.red[400], fontSize: 18, fontWeight: FontWeight.bold),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will permanently delete the assignment from both admin and client sides.',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Warning:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red[700]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Workout: ${assignment.workoutName}',
                    style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'Client: ${assignment.clientName}',
                    style: TextStyle(fontSize: 12, color: Colors.red[700], fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This action cannot be undone.',
                    style: TextStyle(fontSize: 11, color: Colors.red[600], fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('workout_assignments')
                    .doc(assignment.id)
                    .delete();

                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('✓ Assignment permanently deleted'),
                      backgroundColor: Colors.red[400],
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting assignment: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[400]),
            child: const Text('Permanently Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _reassignAssignment(WorkoutAssignment assignment) async {
    DateTime? startDate = DateTime.now();
    DateTime? endDate = DateTime.now().add(const Duration(days: 30));

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Reassign - Set Timing'),
          titleTextStyle: TextStyle(color: _primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Client: ${assignment.clientName}', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Workout: ${assignment.workoutName}', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Text('📅 Start Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: startDate!, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => startDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: _secondaryColor), borderRadius: BorderRadius.circular(8), color: _secondaryColor.withValues(alpha: 0.05)),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(DateFormat('MMM dd, yyyy').format(startDate!), style: const TextStyle(color: Colors.black))]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('📅 End Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: endDate!, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => endDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: _secondaryColor), borderRadius: BorderRadius.circular(8), color: _secondaryColor.withValues(alpha: 0.05)),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(DateFormat('MMM dd, yyyy').format(endDate!), style: const TextStyle(color: Colors.black))]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: startDate != null && endDate != null
                  ? () async {
                      await FirebaseFirestore.instance.collection('workout_assignments').doc(assignment.id).update({
                        'status': 'active',
                        'startDate': startDate,
                        'endDate': endDate,
                        'assignedAt': DateTime.now(),
                      });
                      if (mounted) {
                        Navigator.pop(ctx);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('✓ Reassigned'),
                            backgroundColor: _successColor,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: _successColor, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
              child: const Text('Reassign', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreAssignment(WorkoutAssignment assignment) async {
    DateTime? startDate = DateTime.now();
    DateTime? endDate = assignment.endDate.isAfter(DateTime.now()) ? assignment.endDate : DateTime.now().add(const Duration(days: 30));

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Restore Assignment - Set Timing'),
          titleTextStyle: TextStyle(color: _primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Client: ${assignment.clientName}', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Workout: ${assignment.workoutName}', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Text('📅 Start Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: startDate!, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => startDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: startDate != null ? _secondaryColor : Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: startDate != null ? _secondaryColor.withValues(alpha: 0.05) : Colors.transparent),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(startDate != null ? DateFormat('MMM dd, yyyy').format(startDate!) : 'Tap to select', style: TextStyle(color: startDate != null ? Colors.black : Colors.grey[500]))]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('📅 End Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: endDate!, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => endDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: endDate != null ? _secondaryColor : Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: endDate != null ? _secondaryColor.withValues(alpha: 0.05) : Colors.transparent),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(endDate != null ? DateFormat('MMM dd, yyyy').format(endDate!) : 'Tap to select', style: TextStyle(color: endDate != null ? Colors.black : Colors.grey[500]))]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: startDate != null && endDate != null
                  ? () async {
                      await FirebaseFirestore.instance.collection('workout_assignments').doc(assignment.id).update({
                        'status': 'active',
                        'startDate': startDate,
                        'endDate': endDate,
                        'assignedAt': DateTime.now(),
                      });
                      if (mounted) {
                        Navigator.pop(ctx);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('✓ Restored to Active'),
                            backgroundColor: _successColor,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
              child: const Text('Restore', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentExercisesSection(WorkoutAssignment assignment) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('workout_assignments').doc(assignment.id).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: _primaryColor),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final exercisesList = (data?['exercises'] as List?) ?? [];
        final exercises = List.from(exercisesList);

        if (exercises.isEmpty) {
          return Column(
            children: [
              Icon(Icons.info_outline, size: 32, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(
                'No exercises added',
                style: TextStyle(fontSize: 13, color: Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '💪 Exercises (${exercises.length})',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primaryColor),
            ),
            const SizedBox(height: 12),
            ...exercises.asMap().entries.map((entry) {
              final index = entry.key;
              final exercise = entry.value as Map<String, dynamic>?;
              final isLast = index == exercises.length - 1;

              if (exercise == null) return const SizedBox.shrink();

              final name = exercise['name'] ?? 'Unknown';
              final imageUrl = exercise['imageUrl'] as String?;
              final videoUrl = exercise['videoUrl'] as String?;

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[200]!, width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline, size: 16, color: _successColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (imageUrl != null || videoUrl != null) ...[
                          const SizedBox(width: 8),
                          if (imageUrl != null)
                            GestureDetector(
                              onTap: () => _showImageViewer(imageUrl, name),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _secondaryColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.image, size: 11, color: _secondaryColor),
                                    const SizedBox(width: 3),
                                    Text(
                                      'IMG',
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _secondaryColor),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (videoUrl != null) const SizedBox(width: 6),
                          if (videoUrl != null)
                            GestureDetector(
                              onTap: () => _showVideoViewer(videoUrl, name),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.videocam, size: 11, color: Colors.red),
                                    SizedBox(width: 3),
                                    Text(
                                      'VID',
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  if (!isLast) const SizedBox(height: 8),
                ],
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Future<void> _showExercisesDialog(WorkoutAssignment assignment) async {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600, maxWidth: 500),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🏋️ ${assignment.workoutName}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '👤 ${assignment.clientName}',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),

              // Exercises List
              Expanded(
                child: FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('workout_assignments').doc(assignment.id).get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    final exercisesList = (data?['exercises'] as List?) ?? [];
                    final exercises = List.from(exercisesList);

                    if (exercises.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fitness_center, size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('No exercises assigned', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: exercises.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final exercise = exercises[index] as Map<String, dynamic>?;
                        if (exercise == null) return const SizedBox.shrink();

                        final name = exercise['name'] ?? 'Unknown Exercise';
                        final imageUrl = exercise['imageUrl'] as String?;
                        final videoUrl = exercise['videoUrl'] as String?;
                        final hasMedia = imageUrl != null || videoUrl != null;

                        return Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[200]!),
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.grey[50],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(Icons.fitness_center, size: 18, color: _primaryColor),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (hasMedia) ...[
                                Divider(height: 1, color: Colors.grey[200]),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      if (imageUrl != null)
                                        GestureDetector(
                                          onTap: () => _showImageViewer(imageUrl, name),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: _secondaryColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.image, size: 16, color: _secondaryColor),
                                                const SizedBox(width: 6),
                                                const Text('Image', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      if (videoUrl != null)
                                        GestureDetector(
                                          onTap: () => _showVideoViewer(videoUrl, name),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.videocam, size: 16, color: Colors.red),
                                                const SizedBox(width: 6),
                                                const Text('Video', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImageViewer(String imageUrl, String exerciseName) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black,
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(100),
                minScale: 0.5,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.error,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black87, size: 28),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVideoViewer(String videoUrl, String exerciseName) {
    final videoKey = videoUrl;
    bool isLoadingVideo = false;
    bool hasStartedPlaying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> initializeAndPlayVideo() async {
            if (hasStartedPlaying) return;

            setState(() {
              isLoadingVideo = true;
              hasStartedPlaying = true;
            });

            try {
              if (!_videoControllers.containsKey(videoKey)) {
                final controller =
                    VideoPlayerController.networkUrl(Uri.parse(videoUrl));
                await controller.initialize();
                _videoControllers[videoKey] = controller;

                final chewieController = ChewieController(
                  videoPlayerController: controller,
                  autoPlay: true,
                  looping: false,
                  allowFullScreen: true,
                  allowMuting: true,
                  showOptions: false,
                  materialProgressColors: ChewieProgressColors(
                    playedColor: _primaryColor,
                    handleColor: _primaryColor,
                    backgroundColor: Colors.grey[300]!,
                    bufferedColor: Colors.grey[400]!,
                  ),
                );
                _chewieControllers[videoKey] = chewieController;
              }

              if (mounted) {
                setState(() {
                  isLoadingVideo = false;
                });
              }
            } catch (e) {
              if (mounted) {
                setState(() {
                  isLoadingVideo = false;
                });
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Error loading video: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }

          return Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(16),
            child: Container(
              height: 350,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // Video Player
                  Positioned.fill(
                    child: _videoControllers[videoKey] != null &&
                            _chewieControllers[videoKey] != null
                        ? Chewie(
                            controller: _chewieControllers[videoKey]!,
                          )
                        : GestureDetector(
                            onTap: isLoadingVideo ? null : initializeAndPlayVideo,
                            child: Container(
                              width: double.infinity,
                              height: double.infinity,
                              color: Colors.black,
                              child: Center(
                                child: isLoadingVideo
                                    ? const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            'Loading video...',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Container(
                                        width: 80,
                                        height: 80,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white24,
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 48,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                  ),
                  // 3 Vertical Dots Menu (Top Left)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) {
                            return SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.speed),
                                    title: const Text("0.5x"),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _videoControllers[videoKey]?.setPlaybackSpeed(0.5);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.speed),
                                    title: const Text("1x"),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _videoControllers[videoKey]?.setPlaybackSpeed(1.0);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.speed),
                                    title: const Text("1.5x"),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _videoControllers[videoKey]?.setPlaybackSpeed(1.5);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.speed),
                                    title: const Text("2x"),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _videoControllers[videoKey]?.setPlaybackSpeed(2.0);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.play_arrow),
                                    title: const Text("Play"),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _videoControllers[videoKey]?.play();
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.pause),
                                    title: const Text("Pause"),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _videoControllers[videoKey]?.pause();
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // Close Button (Top Right)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        final videoCtrl = _videoControllers[videoKey];
                        if (videoCtrl != null) {
                          videoCtrl.pause();
                          videoCtrl.seekTo(Duration.zero);
                        }
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      // Stop and reset video when dialog closes
      try {
        final videoCtrl = _videoControllers[videoKey];
        if (videoCtrl != null && videoCtrl.value.isInitialized) {
          videoCtrl.pause();
          videoCtrl.seekTo(Duration.zero);
        }
      } catch (_) {
        // Silently handle any errors
      }
      // Dispose controllers after a short delay to allow cleanup
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          _chewieControllers[videoKey]?.dispose();
          _videoControllers.remove(videoKey);
          _chewieControllers.remove(videoKey);
        } catch (_) {
          // Silently handle disposal errors
        }
      });
    });
  }

  Future<void> _showCreateAssignmentDialog() async {
    String? clientId;
    String? clientName;
    String? workoutId;
    String? workoutName;
    String? workoutType;
    DateTime? startDate;
    DateTime? endDate;

    final clients = (await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'client').get()).docs.map((d) => {'id': d.id, 'name': d['name'] ?? 'Unknown'}).toList();
    final standardWorkouts = (await FirebaseFirestore.instance.collection('standard_workouts').get()).docs.map((d) => {'id': d.id, 'name': d['name'] ?? 'Untitled', 'type': 'standard'}).toList();
    final customWorkouts = (await FirebaseFirestore.instance.collection('custom_workout_groups').get()).docs.map((d) => {'id': d.id, 'name': d['name'] ?? 'Untitled', 'type': 'custom'}).toList();
    final allWorkouts = [...standardWorkouts, ...customWorkouts];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Assign Workout to Client'),
          titleTextStyle: TextStyle(color: _primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Client Selection
                  Text('👤 Select Client', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: clientId,
                        hint: const Text('Choose client...'),
                        isExpanded: true,
                        items: clients.map((c) => DropdownMenuItem<String>(value: c['id'] as String, child: Text(c['name'] as String))).toList(),
                        onChanged: (v) => setState(() { clientId = v; if (v != null) clientName = clients.firstWhere((c) => c['id'] == v)['name'] as String; }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Workout Selection
                  Text('🏋️ Select Workout', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: workoutId,
                        hint: const Text('Choose workout...'),
                        isExpanded: true,
                        items: allWorkouts.map((w) => DropdownMenuItem<String>(value: w['id'] as String, child: Text(w['name'] as String))).toList(),
                        onChanged: (v) => setState(() {
                          workoutId = v;
                          if (v != null) {
                            final w = allWorkouts.firstWhere((x) => x['id'] == v);
                            workoutName = w['name'] as String;
                            workoutType = w['type'] as String;
                          }
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Start Date
                  Text('📅 Start Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => startDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: startDate != null ? _secondaryColor : Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: startDate != null ? _secondaryColor.withValues(alpha: 0.05) : Colors.transparent),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(startDate != null ? DateFormat('MMM dd, yyyy').format(startDate!) : 'Tap to select', style: TextStyle(color: startDate != null ? Colors.black : Colors.grey[500]))]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // End Date
                  Text('📅 End Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: startDate ?? DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => endDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: endDate != null ? _secondaryColor : Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: endDate != null ? _secondaryColor.withValues(alpha: 0.05) : Colors.transparent),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(endDate != null ? DateFormat('MMM dd, yyyy').format(endDate!) : 'Tap to select', style: TextStyle(color: endDate != null ? Colors.black : Colors.grey[500]))]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Status Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _successColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: _successColor.withValues(alpha: 0.3))),
                    child: Row(children: [Icon(Icons.info, color: _successColor, size: 18), const SizedBox(width: 8), Expanded(child: Text('Status: ACTIVE', style: TextStyle(color: _successColor, fontWeight: FontWeight.w600, fontSize: 13)))]),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: clientId != null && workoutId != null
                  ? () async {
                      await FirebaseFirestore.instance.collection('workout_assignments').add({
                        'clientId': clientId,
                        'clientName': clientName,
                        'workoutId': workoutId,
                        'workoutName': workoutName,
                        'workoutType': workoutType,
                        'startDate': startDate ?? DateTime.now(),
                        'endDate': endDate ?? DateTime.now().add(const Duration(days: 30)),
                        'assignedAt': DateTime.now(),
                        'status': 'active',
                        'adminId': 'admin',
                      });
                      if (mounted) {
                        Navigator.pop(ctx);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ Assigned "$workoutName" to $clientName'),
                            backgroundColor: _successColor,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
              child: const Text('Assign', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAssignWorkoutDialog(dynamic workout, String workoutType) async {
    String? clientId;
    String? clientName;
    DateTime? startDate;
    DateTime? endDate;

    // Get workout name based on type
    final workoutName = workoutType == 'Standard' ? workout.name : workout.name;
    final workoutId = workoutType == 'Standard' ? workout.id : workout.id;

    final clients = (await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'client').get()).docs.map((d) => {'id': d.id, 'name': d['name'] ?? 'Unknown'}).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Assign "$workoutName" to Client'),
          titleTextStyle: TextStyle(color: _primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Client Selection
                  Text('👤 Select Client', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: clientId,
                        hint: const Text('Choose client...'),
                        isExpanded: true,
                        items: clients.map((c) => DropdownMenuItem<String>(value: c['id'] as String, child: Text(c['name'] as String))).toList(),
                        onChanged: (v) => setState(() { clientId = v; if (v != null) clientName = clients.firstWhere((c) => c['id'] == v)['name'] as String; }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Start Date
                  Text('📅 Start Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => startDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: startDate != null ? _secondaryColor : Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: startDate != null ? _secondaryColor.withValues(alpha: 0.05) : Colors.transparent),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(startDate != null ? DateFormat('MMM dd, yyyy').format(startDate!) : 'Tap to select', style: TextStyle(color: startDate != null ? Colors.black : Colors.grey[500]))]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // End Date
                  Text('📅 End Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryColor)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: startDate ?? DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                      if (picked != null) setState(() => endDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(border: Border.all(color: endDate != null ? _secondaryColor : Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: endDate != null ? _secondaryColor.withValues(alpha: 0.05) : Colors.transparent),
                      child: Row(children: [Icon(Icons.calendar_today, size: 18, color: _primaryColor), const SizedBox(width: 8), Text(endDate != null ? DateFormat('MMM dd, yyyy').format(endDate!) : 'Tap to select', style: TextStyle(color: endDate != null ? Colors.black : Colors.grey[500]))]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Status Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _successColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: _successColor.withValues(alpha: 0.3))),
                    child: Row(children: [Icon(Icons.info, color: _successColor, size: 18), const SizedBox(width: 8), Expanded(child: Text('Status: ACTIVE', style: TextStyle(color: _successColor, fontWeight: FontWeight.w600, fontSize: 13)))]),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: clientId != null && startDate != null && endDate != null
                  ? () async {
                      await FirebaseFirestore.instance.collection('workout_assignments').add({
                        'clientId': clientId,
                        'clientName': clientName,
                        'workoutId': workoutId,
                        'workoutName': workoutName,
                        'workoutType': workoutType.toLowerCase(),
                        'startDate': startDate,
                        'endDate': endDate,
                        'assignedAt': DateTime.now(),
                        'status': 'active',
                        'adminId': 'admin',
                      });
                      if (mounted) {
                        Navigator.pop(ctx);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ Assigned "$workoutName" to $clientName'),
                            backgroundColor: _successColor,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
              child: const Text('Assign', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
// Add this class to your admin screen file

// Deassign Workouts Dialog
class DeassignWorkoutsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> assignedWorkouts;
  final List<String> clientIds;
  final Color primaryColor;

  const DeassignWorkoutsDialog({
    super.key,
    required this.assignedWorkouts,
    required this.clientIds,
    required this.primaryColor,
  });

  @override
  State<DeassignWorkoutsDialog> createState() => _DeassignWorkoutsDialogState();
}

class _DeassignWorkoutsDialogState extends State<DeassignWorkoutsDialog> {
  final Set<String> _selectedWorkoutIds = {};
  bool _isDeassigning = false;

  // In the DeassignWorkoutsDialog's build method, update the workout display section:
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red[400],
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Deassign Workouts',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Client info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.primaryColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people, size: 16, color: widget.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Selected Clients: ${widget.clientIds.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: widget.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Select All checkbox
              if (widget.assignedWorkouts.isNotEmpty)
                Row(
                  children: [
                    Checkbox(
                      value: _selectedWorkoutIds.length == widget.assignedWorkouts.length,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedWorkoutIds.addAll(
                              widget.assignedWorkouts.map((w) => w['id'].toString())
                            );
                          } else {
                            _selectedWorkoutIds.clear();
                          }
                        });
                      },
                      activeColor: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Select All Workouts',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_selectedWorkoutIds.length} selected',
                      style: TextStyle(
                        fontSize: 12,
                        color: _selectedWorkoutIds.isNotEmpty ? Colors.red : Colors.grey,
                      ),
                    ),
                  ],
                ),
              
              const SizedBox(height: 12),
              
              // Workouts list - UPDATED to properly display custom exercise names
              Expanded(
                child: widget.assignedWorkouts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fitness_center, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No assigned workouts found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'These clients have no workouts assigned',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: widget.assignedWorkouts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final workout = widget.assignedWorkouts[index];
                          final workoutId = workout['id'].toString();
                          
                          // Improved workout name extraction
                          String workoutName = 'Unnamed Workout';
                          
                          // Check if it's a custom workout with exercises
                          // In DeassignWorkoutsDialog's build method, update the workout name extraction:
                          if (workout['type'] == 'custom' && workout['workouts'] != null) {
                            final Map<String, dynamic> workouts = workout['workouts'];
                            final List<String> exerciseNames = [];
                            
                            workouts.forEach((groupName, exercises) {
                              if (exercises is List) {
                                for (var exercise in exercises) {
                                  if (exercise is Map<String, dynamic>) {
                                    exerciseNames.add(exercise['name'] ?? 'Unknown');
                                  } else if (exercise is String) {
                                    exerciseNames.add(exercise);
                                  }
                                }
                              }
                            });
                            
                            if (exerciseNames.isNotEmpty) {
                              workoutName = exerciseNames.join(', ');
                            }
                          } else {
                            // Standard workout
                            workoutName = workout['workout_name'] ?? 
                                        workout['title'] ?? 
                                        'Unnamed Workout';
                          }
                          
                          final assignedDate = workout['assigned_at'] != null
                              ? DateFormat('MMM d, yyyy').format(
                                  (workout['assigned_at'] as Timestamp).toDate())
                              : 'Unknown date';
                          final type = workout['type'] ?? 'unknown';
                          
                          return CheckboxListTile(
                            title: Text(
                              workoutName.length > 50 
                                  ? '${workoutName.substring(0, 50)}...' 
                                  : workoutName,
                              style: TextStyle(
                                fontWeight: _selectedWorkoutIds.contains(workoutId)
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Assigned: $assignedDate',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                                Text(
                                  'Type: ${type.toString().toUpperCase()}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                            value: _selectedWorkoutIds.contains(workoutId),
                            onChanged: (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedWorkoutIds.add(workoutId);
                                } else {
                                  _selectedWorkoutIds.remove(workoutId);
                                }
                              });
                            },
                            activeColor: Colors.red,
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: type == 'standard' 
                                    ? Colors.blue[50] 
                                    : Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                type == 'standard' 
                                    ? Icons.fitness_center 
                                    : Icons.category,
                                size: 16,
                                color: type == 'standard' ? Colors.blue : Colors.green,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              
              const SizedBox(height: 20),
              
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedWorkoutIds.isEmpty || _isDeassigning
                          ? null
                          : () {
                              _confirmDeassign(context);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[400],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isDeassigning
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Deassign Selected',
                              style: TextStyle(color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeassign(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Confirm Deassignment',
        message: 'Deassign ${_selectedWorkoutIds.length} workout(s) from ${widget.clientIds.length} client(s)?\n\nThis action cannot be undone.',
        primaryColor: Colors.red[400]!,
      ),
    );

    if (confirmed == true) {
      setState(() => _isDeassigning = true);
      
      try {
        final batch = FirebaseFirestore.instance.batch();
        
        for (final clientId in widget.clientIds) {
          final clientWorkoutsRef = FirebaseFirestore.instance
              .collection('users')
              .doc(clientId)
              .collection('workouts');
          
          for (final workoutId in _selectedWorkoutIds) {
            batch.delete(clientWorkoutsRef.doc(workoutId));
          }
        }
        
        await batch.commit();
        
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isDeassigning = false);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to deassign workouts: $e'),
              backgroundColor: Colors.red[400],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    }
  }
}

// Standard Workout Template Card - Updated with bullet points, no checkboxes, no container issues
// Standard Workout Template Card - Fixed edit button
class _WorkoutTemplateCard extends StatelessWidget {
  final StandardWorkout workout;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onAddExercise;
  final VoidCallback onDelete;
  final Function(WorkoutExercise) onDeleteExercise;
  final Function(WorkoutExercise) onEditExercise;
  final Function(WorkoutMedia) onDeleteMedia;
  final Color primaryColor;
  final Color selectedCardColor;
  final Color cardColor;

  const _WorkoutTemplateCard({
    required this.workout,
    required this.isSelected,
    required this.onSelect,
    required this.onEdit,
    required this.onAddExercise,
    required this.onDelete,
    required this.onDeleteExercise,
    required this.onEditExercise,
    required this.onDeleteMedia,
    required this.primaryColor,
    required this.selectedCardColor,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? selectedCardColor : cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? primaryColor : Colors.grey[200]!,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Selection circle - wrapped in GestureDetector with higher priority
                GestureDetector(
                  onTap: onSelect,
                  behavior: HitTestBehavior.deferToChild,

                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? primaryColor : Colors.grey[400]!,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Icon(Icons.check, size: 16, color: primaryColor)
                        : null,
                  ),
                ),
                const SizedBox(width: 16),

                // Workout title - with onTap for selection as well
                Expanded(
                  child: GestureDetector(
                    onTap: onSelect,
                    behavior: HitTestBehavior.deferToChild,
                    child: Text(
                      workout.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? primaryColor : Colors.grey[800],
                      ),
                    ),
                  ),
                ),

                // ACTION ICONS - FIXED: Wrap each button in a container with onTap
                // to prevent parent gesture detectors from interfering
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Edit button - fixed
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTapDown: (_) {}, // ⛔ stops parent selection
                            onTap: () {
                              // Add debug print to verify it's being called
                              debugPrint('Edit button tapped for: ${workout.name}');
                              onEdit();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.edit,
                                size: 20,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Add Exercise button
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onAddExercise,
                            borderRadius: BorderRadius.circular(20),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.add_circle_outline,
                                size: 22,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Delete button
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onDelete,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.delete_outline,
                                size: 22,
                                color: Colors.red[300],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Workout Media Section
            if (workout.media.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: workout.media.map((media) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: media.type == MediaType.image 
                                ? Colors.green[50] 
                                : Colors.blue[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: media.type == MediaType.image 
                                  ? Colors.green[200]! 
                                  : Colors.blue[200]!,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                media.type == MediaType.image 
                                    ? Icons.image 
                                    : Icons.video_library,
                                size: 14,
                                color: media.type == MediaType.image 
                                    ? Colors.green 
                                    : Colors.blue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                media.type == MediaType.image ? 'Image' : 'Video',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: media.type == MediaType.image 
                                      ? Colors.green 
                                      : Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => onDeleteMedia(media),
                                  borderRadius: BorderRadius.circular(12),
                                  child: const Padding(
                                    padding: EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            
            // Exercises with bullet points and media
            ...workout.exercises.map((exercise) => Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isSelected ? primaryColor : Colors.grey[600],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exercise.name,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.1,
                                color: isSelected ? primaryColor : Colors.grey[800],
                              ),
                            ),
                            // Show media badges if available
                            if (exercise.imageUrl != null || exercise.videoUrl != null) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (exercise.imageUrl != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green[50],
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.green[200]!),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.image, size: 12, color: Colors.green),
                                          const SizedBox(width: 3),
                                          const Text('Image', style: TextStyle(fontSize: 10, color: Colors.green)),
                                        ],
                                      ),
                                    ),
                                  if (exercise.videoUrl != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.blue[200]!),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.video_library, size: 12, color: Colors.blue),
                                          const SizedBox(width: 3),
                                          const Text('Video', style: TextStyle(fontSize: 10, color: Colors.blue)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onEditExercise(exercise),
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.edit,
                              size: 16,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onDeleteExercise(exercise),
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )),

            if (workout.exercises.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 8),
                child: Text(
                  'No exercises yet. Tap + to add.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500], fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Muscle Group Workouts - Updated with Edit button for exercises (UNCHANGED)
class _MuscleGroupWorkouts extends StatelessWidget {
  final CustomWorkoutGroup group;
  final List<WorkoutExercise> exercises;
  final List<String> selected;
  final Function(String, bool) onSelect;
  final VoidCallback onAddExercise;
  final Function(WorkoutExercise) onEditExercise;
  final Function(WorkoutExercise) onDeleteExercise;
  final Color primaryColor;
  final Color selectedCardColor;
  final Color cardColor;

  const _MuscleGroupWorkouts({
    required this.group,
    required this.exercises,
    required this.selected,
    required this.onSelect,
    required this.onAddExercise,
    required this.onEditExercise,
    required this.onDeleteExercise,
    required this.primaryColor,
    required this.selectedCardColor,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: exercises.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.fitness_center, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'No exercises in ${group.name}',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add exercises',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: exercises.length,
                  itemBuilder: (context, index) {
                    final exercise = exercises[index];
                    final isSelected = selected.contains(exercise.name);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        elevation: isSelected ? 2 : 0,
                        color: isSelected ? selectedCardColor : cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected ? primaryColor : Colors.grey[200]!,
                            width: isSelected ? 1 : 0.5,
                          ),
                        ),
                        child: CheckboxListTile(
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exercise.name,
                                style: TextStyle(
                                  color: isSelected ? primaryColor : Colors.grey[800],
                                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                              if (exercise.videoUrl != null || exercise.imageUrl != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      if (exercise.videoUrl != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[50],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.video_library, size: 14, color: Colors.blue),
                                              SizedBox(width: 4),
                                              Text('Video', style: TextStyle(fontSize: 11, color: Colors.blue)),
                                            ],
                                          ),
                                        ),
                                      if (exercise.imageUrl != null)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green[50],
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.image, size: 14, color: Colors.green),
                                                SizedBox(width: 4),
                                                Text('Image', style: TextStyle(fontSize: 11, color: Colors.green)),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          subtitle: null,
                          value: isSelected,
                          onChanged: (value) => onSelect(exercise.name, value ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          secondary: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, size: 18, color: primaryColor),
                                onPressed: () => onEditExercise(exercise),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, size: 18, color: Colors.grey[400]),
                                onPressed: () => onDeleteExercise(exercise),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// Add Standard Workout Dialog - Updated with Workout Media (UNCHANGED)
class AddStandardWorkoutDialog extends StatefulWidget {
  final Color primaryColor;
  final Color accentColor;

  const AddStandardWorkoutDialog({
    super.key,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  State<AddStandardWorkoutDialog> createState() => _AddStandardWorkoutDialogState();
}

class _AddStandardWorkoutDialogState extends State<AddStandardWorkoutDialog> {
  final TextEditingController _nameController = TextEditingController();
  final List<WorkoutExercise> _exercises = [];
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    final exercise = await showDialog<WorkoutExercise>(
      context: context,
      builder: (context) => AddStandardExerciseDialog(
        primaryColor: widget.primaryColor,
        accentColor: widget.accentColor,
      ),
    );

    if (exercise != null) {
      setState(() {
        _exercises.add(exercise);
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 750,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Row(
                  children: [
                    Icon(Icons.fitness_center, color: widget.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Add Standard Workout',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Workout Name',
                    hintText: 'e.g., Upper Body Strength',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: widget.primaryColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a workout name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Exercises',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Exercise'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  fit: FlexFit.loose,
                  child: _exercises.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.fitness_center, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'No exercises added',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap "Add Exercise" to begin',
                                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: List.generate(
                              _exercises.length,
                              (index) {
                                final exercise = _exercises[index];
                                final hasImage = exercise.imageUrl != null && exercise.imageUrl!.isNotEmpty;
                                final hasVideo = exercise.videoUrl != null && exercise.videoUrl!.isNotEmpty;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: widget.primaryColor.withValues(alpha: 0.15),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: widget.primaryColor.withValues(alpha: 0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Exercise name with number and action buttons
                                        Row(
                                          children: [
                                            Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: widget.primaryColor,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '${index + 1}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                exercise.name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  color: widget.primaryColor,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                              onPressed: () async {
                                                final updatedExercise = await showDialog<WorkoutExercise>(
                                                  context: context,
                                                  builder: (context) => EditStandardExerciseDialog(
                                                    exercise: exercise,
                                                    primaryColor: widget.primaryColor,
                                                    accentColor: widget.accentColor,
                                                  ),
                                                );
                                                if (updatedExercise != null) {
                                                  setState(() {
                                                    _exercises[index] = updatedExercise;
                                                  });
                                                }
                                              },
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                              onPressed: () {
                                                setState(() {
                                                  _exercises.removeAt(index);
                                                });
                                              },
                                              padding: const EdgeInsets.all(8),
                                              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                              splashRadius: 24,
                                            ),
                                          ],
                                        ),

                                        // Media badges
                                        if (hasImage || hasVideo) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 6,
                                            children: [
                                              if (hasImage)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green[50],
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(color: Colors.green[200]!),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.image, size: 13, color: Colors.green[700]),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        'Image',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.green[700],
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (hasVideo)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue[50],
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(color: Colors.blue[200]!),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.video_library, size: 13, color: Colors.blue[700]),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        'Video',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.blue[700],
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[400]!),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate() && _exercises.isNotEmpty) {
                            Navigator.pop(context, {
                              'name': _nameController.text,
                              'exercises': _exercises,
                              'media': [],
                            });
                          } else if (_exercises.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please add at least one exercise'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Add Workout',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Edit Standard Workout Dialog (UNCHANGED)
class EditStandardWorkoutDialog extends StatefulWidget {
  final StandardWorkout workout;
  final Color primaryColor;
  final Color accentColor;

  const EditStandardWorkoutDialog({
    super.key,
    required this.workout,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  State<EditStandardWorkoutDialog> createState() => _EditStandardWorkoutDialogState();
}

class _EditStandardWorkoutDialogState extends State<EditStandardWorkoutDialog> {
  late TextEditingController _nameController;
  late List<WorkoutExercise> _exercises;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.workout.name);
    _exercises = List.from(widget.workout.exercises);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    final exercise = await showDialog<WorkoutExercise>(
      context: context,
      builder: (context) => AddStandardExerciseDialog(
        primaryColor: widget.primaryColor,
        accentColor: widget.accentColor,
      ),
    );

    if (exercise != null) {
      setState(() {
        _exercises.add(exercise);
      });
    }
  }

  Future<void> _editExercise(WorkoutExercise exercise) async {
    final updatedExercise = await showDialog<WorkoutExercise>(
      context: context,
      builder: (context) => EditStandardExerciseDialog(
        exercise: exercise,
        primaryColor: widget.primaryColor,
        accentColor: widget.accentColor,
      ),
    );

    if (updatedExercise != null) {
      setState(() {
        final index = _exercises.indexOf(exercise);
        _exercises[index] = updatedExercise;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 750,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Row(
                  children: [
                    Icon(Icons.edit, color: widget.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Edit Standard Workout',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Workout Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: widget.primaryColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a workout name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Exercises',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Exercise'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),

                Flexible(
                  fit: FlexFit.loose,
                  child: _exercises.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.fitness_center, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                'No exercises added',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap "Add Exercise" to begin',
                                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: List.generate(
                              _exercises.length,
                              (index) {
                                final exercise = _exercises[index];
                                final hasImage = exercise.imageUrl != null && exercise.imageUrl!.isNotEmpty;
                                final hasVideo = exercise.videoUrl != null && exercise.videoUrl!.isNotEmpty;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: widget.primaryColor.withValues(alpha: 0.15),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: widget.primaryColor.withValues(alpha: 0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Exercise name with number and actions
                                        Row(
                                          children: [
                                            Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: widget.primaryColor,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '${index + 1}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                exercise.name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  color: widget.primaryColor,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            // Action buttons
                                            SizedBox(
                                              width: 70,
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  IconButton(
                                                    icon: Icon(Icons.edit, color: widget.primaryColor, size: 18),
                                                    onPressed: () => _editExercise(exercise),
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  IconButton(
                                                    icon: const Icon(Icons.close, color: Colors.red, size: 18),
                                                    onPressed: () {
                                                      setState(() {
                                                        _exercises.removeAt(index);
                                                      });
                                                    },
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),

                                        // Media badges
                                        if (hasImage || hasVideo) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 6,
                                            children: [
                                              if (hasImage)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green[50],
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(color: Colors.green[200]!),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.image, size: 13, color: Colors.green[700]),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        'Image',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.green[700],
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (hasVideo)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue[50],
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(color: Colors.blue[200]!),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.video_library, size: 13, color: Colors.blue[700]),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        'Video',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.blue[700],
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[400]!),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate() && _exercises.isNotEmpty) {
                            Navigator.pop(context, {
                              'name': _nameController.text,
                              'exercises': _exercises,
                              'media': [],
                            });
                          } else if (_exercises.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please add at least one exercise'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Add Standard Exercise Dialog - NO MEDIA (UNCHANGED)
class AddStandardExerciseDialog extends StatefulWidget {
  final Color primaryColor;
  final Color accentColor;

  const AddStandardExerciseDialog({
    super.key,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  State<AddStandardExerciseDialog> createState() => _AddStandardExerciseDialogState();
}

class _AddStandardExerciseDialogState extends State<AddStandardExerciseDialog> {
  final TextEditingController _nameController = TextEditingController();
  String? _videoUrl;
  String? _imageUrl;
  bool _isUploadingImage = false;
  bool _isUploadingVideo = false;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _uploadToStorage(XFile file, bool isImage) async {
    setState(() {
      if (isImage) {
        _isUploadingImage = true;
      } else {
        _isUploadingVideo = true;
      }
    });

    try {
      String fileType = isImage ? 'images' : 'videos';
      String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      Reference storageRef = _storage.ref().child('exercise_media/$fileType/$fileName');

      final metadata = SettableMetadata(
        contentType: isImage ? 'image/jpeg' : 'video/mp4',
        customMetadata: {
          'uploaded_at': DateTime.now().toIso8601String(),
          'source': 'admin_panel',
        },
      );

      UploadTask uploadTask = storageRef.putFile(File(file.path), metadata);

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      if (mounted) {
        setState(() {
          if (isImage) {
            _imageUrl = downloadUrl;
            _isUploadingImage = false;
          } else {
            _videoUrl = downloadUrl;
            _isUploadingVideo = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isImage ? 'Image' : 'Video'} uploaded successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Upload failed: $e');
      if (mounted) {
        setState(() {
          if (isImage) {
            _isUploadingImage = false;
          } else {
            _isUploadingVideo = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        await _uploadToStorage(image, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        final file = File(video.path);
        final fileSize = await file.length();
        final fileSizeInMB = fileSize / (1024 * 1024);

        if (fileSizeInMB > 500) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video size exceeds 500MB limit'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        await _uploadToStorage(video, false);
      }
    } catch (e) {
      debugPrint('❌ Error picking video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking video: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearImage() {
    setState(() {
      _imageUrl = null;
    });
  }

  void _clearVideo() {
    setState(() {
      _videoUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 750,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.fitness_center,
                          color: widget.primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Add Exercise',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: widget.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 24),

                // Exercise Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Exercise Name',
                    hintText: 'e.g., Bench Press 3x12',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: widget.primaryColor, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.fitness_center),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an exercise name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Media Section Header
                Text(
                  'Media Attachments (Optional)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),

                const SizedBox(height: 12),

                // Image and Video Upload Buttons
                Row(
                  children: [
                    Expanded(
                      child: _isUploadingImage
                          ? Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: _pickImage,
                              icon: Icon(
                                Icons.image,
                                color: _imageUrl != null ? Colors.green : Colors.grey[600],
                              ),
                              label: Text(
                                _imageUrl != null ? 'Change Image' : 'Add Image',
                                style: TextStyle(
                                  color: _imageUrl != null ? Colors.green : Colors.grey[600],
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: _imageUrl != null ? Colors.green : Colors.grey[300]!,
                                  width: _imageUrl != null ? 1.5 : 1,
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _isUploadingVideo
                          ? Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: _pickVideo,
                              icon: Icon(
                                Icons.video_library,
                                color: _videoUrl != null ? Colors.blue : Colors.grey[600],
                              ),
                              label: Text(
                                _videoUrl != null ? 'Change Video' : 'Add Video',
                                style: TextStyle(
                                  color: _videoUrl != null ? Colors.blue : Colors.grey[600],
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: _videoUrl != null ? Colors.blue : Colors.grey[300]!,
                                  width: _videoUrl != null ? 1.5 : 1,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),

                // Selected Media Display
                if (_imageUrl != null || _videoUrl != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        if (_imageUrl != null) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.image, color: Colors.green, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Image',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _imageUrl!.split('/').last,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _clearImage,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],

                        if (_imageUrl != null && _videoUrl != null) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1),
                          ),
                        ],

                        if (_videoUrl != null) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.video_library, color: Colors.blue, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Video',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _videoUrl!.split('/').last,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _clearVideo,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[400]!),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            if (_isUploadingImage || _isUploadingVideo) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please wait for uploads to complete'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }

                            Navigator.pop(
                              context,
                              WorkoutExercise(
                                name: _nameController.text.trim(),
                                videoUrl: _videoUrl,
                                imageUrl: _imageUrl,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          'Add Exercise',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Upload warning if in progress
                if (_isUploadingImage || _isUploadingVideo) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Upload in progress. Please wait...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

// Edit Standard Exercise Dialog - WITH MEDIA SUPPORT
class EditStandardExerciseDialog extends StatefulWidget {
  final WorkoutExercise exercise;
  final Color primaryColor;
  final Color accentColor;

  const EditStandardExerciseDialog({
    super.key,
    required this.exercise,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  State<EditStandardExerciseDialog> createState() => _EditStandardExerciseDialogState();
}

class _EditStandardExerciseDialogState extends State<EditStandardExerciseDialog> {
  late TextEditingController _nameController;
  String? _videoUrl;
  String? _imageUrl;
  bool _isUploadingImage = false;
  bool _isUploadingVideo = false;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.exercise.name);
    _videoUrl = widget.exercise.videoUrl;
    _imageUrl = widget.exercise.imageUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _uploadToStorage(XFile file, bool isImage) async {
    setState(() {
      if (isImage) {
        _isUploadingImage = true;
      } else {
        _isUploadingVideo = true;
      }
    });

    try {
      String fileType = isImage ? 'images' : 'videos';
      String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      Reference storageRef = _storage.ref().child('exercise_media/$fileType/$fileName');

      final metadata = SettableMetadata(
        contentType: isImage ? 'image/jpeg' : 'video/mp4',
        customMetadata: {
          'uploaded_at': DateTime.now().toIso8601String(),
          'source': 'admin_panel',
        },
      );

      UploadTask uploadTask = storageRef.putFile(File(file.path), metadata);

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      if (mounted) {
        setState(() {
          if (isImage) {
            _imageUrl = downloadUrl;
            _isUploadingImage = false;
          } else {
            _videoUrl = downloadUrl;
            _isUploadingVideo = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isImage ? 'Image' : 'Video'} uploaded successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Upload failed: $e');
      if (mounted) {
        setState(() {
          if (isImage) {
            _isUploadingImage = false;
          } else {
            _isUploadingVideo = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        await _uploadToStorage(image, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        final file = File(video.path);
        final fileSize = await file.length();
        final fileSizeInMB = fileSize / (1024 * 1024);

        if (fileSizeInMB > 500) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video size exceeds 500MB limit'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        await _uploadToStorage(video, false);
      }
    } catch (e) {
      debugPrint('❌ Error picking video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking video: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearImage() {
    setState(() {
      _imageUrl = null;
    });
  }

  void _clearVideo() {
    setState(() {
      _videoUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 750,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.edit,
                          color: widget.primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Edit Exercise',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: widget.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 24),

                // Exercise Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Exercise Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: widget.primaryColor, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.fitness_center),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an exercise name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Media Section Header
                Text(
                  'Media Attachments (Optional)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),

                const SizedBox(height: 12),

                // Image and Video Upload Buttons
                Row(
                  children: [
                    Expanded(
                      child: _isUploadingImage
                          ? Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: _pickImage,
                              icon: Icon(
                                Icons.image,
                                color: _imageUrl != null ? Colors.green : Colors.grey[600],
                              ),
                              label: Text(
                                _imageUrl != null ? 'Change Image' : 'Add Image',
                                style: TextStyle(
                                  color: _imageUrl != null ? Colors.green : Colors.grey[600],
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: _imageUrl != null ? Colors.green : Colors.grey[300]!,
                                  width: _imageUrl != null ? 1.5 : 1,
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _isUploadingVideo
                          ? Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: _pickVideo,
                              icon: Icon(
                                Icons.video_library,
                                color: _videoUrl != null ? Colors.blue : Colors.grey[600],
                              ),
                              label: Text(
                                _videoUrl != null ? 'Change Video' : 'Add Video',
                                style: TextStyle(
                                  color: _videoUrl != null ? Colors.blue : Colors.grey[600],
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: _videoUrl != null ? Colors.blue : Colors.grey[300]!,
                                  width: _videoUrl != null ? 1.5 : 1,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),

                // Selected Media Display
                if (_imageUrl != null || _videoUrl != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        if (_imageUrl != null) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.image, color: Colors.green, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Image',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _imageUrl!.split('/').last,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _clearImage,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],

                        if (_imageUrl != null && _videoUrl != null) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1),
                          ),
                        ],

                        if (_videoUrl != null) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.video_library, color: Colors.blue, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Video',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _videoUrl!.split('/').last,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _clearVideo,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[400]!),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            if (_isUploadingImage || _isUploadingVideo) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please wait for uploads to complete'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }

                            Navigator.pop(
                              context,
                              WorkoutExercise(
                                name: _nameController.text.trim(),
                                videoUrl: _videoUrl,
                                imageUrl: _imageUrl,
                                isSelected: widget.exercise.isSelected,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Upload warning if in progress
                if (_isUploadingImage || _isUploadingVideo) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Upload in progress. Please wait...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

// Add Workout Media Dialog (UNCHANGED)
class AddWorkoutMediaDialog extends StatefulWidget {
  final Color primaryColor;

  const AddWorkoutMediaDialog({
    super.key,
    required this.primaryColor,
  });

  @override
  State<AddWorkoutMediaDialog> createState() => _AddWorkoutMediaDialogState();
}

class _AddWorkoutMediaDialogState extends State<AddWorkoutMediaDialog> {
  String? _mediaUrl;
  MediaType? _mediaType;
  bool _isUploading = false;
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<void> _uploadMedia(XFile file, MediaType type) async {
    setState(() {
      _isUploading = true;
    });

    try {
      String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      Reference storageRef = _storage.ref().child('workout_media/$fileName');
      
      UploadTask uploadTask = storageRef.putFile(File(file.path));
      TaskSnapshot snapshot = await uploadTask;
      
      String downloadUrl = await snapshot.ref.getDownloadURL();
      
      setState(() {
        _mediaUrl = downloadUrl;
        _mediaType = type;
        _isUploading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${type == MediaType.image ? 'Image' : 'Video'} uploaded successfully!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (image != null) {
      await _uploadMedia(image, MediaType.image);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video == null) return;

      final file = File(video.path);
      final double sizeMB = (await file.length()) / (1024 * 1024);

      if (sizeMB > 500) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video size must be under 500 MB'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await _uploadMedia(video, MediaType.video);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _reset() {
    setState(() {
      _mediaUrl = null;
      _mediaType = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_file, color: widget.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Add Workout Media',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            if (_isUploading) ...[
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Uploading...'),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'Select Media Type',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: Icon(Icons.image, color: Colors.grey[600]),
                      label: const Text('Add Image'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickVideo,
                      icon: Icon(Icons.video_library, color: Colors.grey[600]),
                      label: const Text('Add Video'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            
            if (_mediaUrl != null && !_isUploading) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _mediaType == MediaType.image ? Colors.green[50] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _mediaType == MediaType.image ? Colors.green[200]! : Colors.blue[200]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: _mediaType == MediaType.image ? Colors.green : Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_mediaType == MediaType.image ? 'Image' : 'Video'} ready to add',
                        style: TextStyle(
                          fontSize: 13,
                          color: _mediaType == MediaType.image ? Colors.green : Colors.blue,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _reset,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Click "Add Media" to add this file, or select another type to add more',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _mediaUrl != null && !_isUploading
                        ? () {
                            Navigator.pop(
                              context,
                              WorkoutMedia(
                                url: _mediaUrl!,
                                type: _mediaType!,
                              ),
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Add Media',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AddExerciseDialog extends StatefulWidget {
  final Color primaryColor;
  final Color accentColor;

  const AddExerciseDialog({
    super.key,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  State<AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends State<AddExerciseDialog> {
  final TextEditingController _nameController = TextEditingController();
  String? _videoUrl;
  String? _imageUrl;
  bool _isUploadingImage = false;
  bool _isUploadingVideo = false;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _uploadToStorage(XFile file, bool isImage) async {
    setState(() {
      if (isImage) {
        _isUploadingImage = true;
      } else {
        _isUploadingVideo = true;
      }
    });

    try {
      String fileType = isImage ? 'images' : 'videos';
      String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      Reference storageRef = _storage.ref().child('exercise_media/$fileType/$fileName');
      
      final metadata = SettableMetadata(
        contentType: isImage ? 'image/jpeg' : 'video/mp4',
        customMetadata: {
          'uploaded_at': DateTime.now().toIso8601String(),
          'source': 'admin_panel',
        },
      );
      
      UploadTask uploadTask = storageRef.putFile(File(file.path), metadata);
      
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        debugPrint('Upload progress: ${(progress * 100).toStringAsFixed(2)}%');
      });

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      
      debugPrint('✅ Uploaded ${isImage ? "image" : "video"} URL: $downloadUrl'); // 🔍 DEBUG
      
      if (mounted) {
        setState(() {
          if (isImage) {
            _imageUrl = downloadUrl;  // ✅ Save the Firebase URL, not local path
            _isUploadingImage = false;
          } else {
            _videoUrl = downloadUrl;  // ✅ Save the Firebase URL, not local path
            _isUploadingVideo = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isImage ? 'Image' : 'Video'} uploaded successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Upload failed: $e');
      if (mounted) {
        setState(() {
          if (isImage) {
            _isUploadingImage = false;
          } else {
            _isUploadingVideo = false;
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        await _uploadToStorage(image, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      
      if (video != null) {
        final file = File(video.path);
        final fileSize = await file.length();
        final fileSizeInMB = fileSize / (1024 * 1024);
        
        if (fileSizeInMB > 500) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video size exceeds 500MB limit'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        
        debugPrint('📹 Selected video: ${video.path}');
        await _uploadToStorage(video, false);  // This will now save the Firebase URL
      }
    } catch (e) {
      debugPrint('❌ Error picking video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking video: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearImage() {
    setState(() {
      _imageUrl = null;
    });
  }

  void _clearVideo() {
    setState(() {
      _videoUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.fitness_center,
                      color: widget.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add Exercise',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Exercise Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Exercise Name',
                  hintText: 'e.g., Bench Press 3x12',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.primaryColor, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.fitness_center),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an exercise name';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // Media Section Header
              Text(
                'Media Attachments (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Image and Video Upload Buttons - UPDATED to allow both
              Row(
                children: [
                  // Image Button
                  Expanded(
                    child: _isUploadingImage
                        ? Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: _pickImage, // Always allow picking even if image exists
                            icon: Icon(
                              Icons.image,
                              color: _imageUrl != null ? Colors.green : Colors.grey[600],
                            ),
                            label: Text(
                              _imageUrl != null ? 'Change Image' : 'Add Image',
                              style: TextStyle(
                                color: _imageUrl != null ? Colors.green : Colors.grey[600],
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: _imageUrl != null ? Colors.green : Colors.grey[300]!,
                                width: _imageUrl != null ? 1.5 : 1,
                              ),
                            ),
                          ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Video Button
                  Expanded(
                    child: _isUploadingVideo
                        ? Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: _pickVideo, // Always allow picking even if video exists
                            icon: Icon(
                              Icons.video_library,
                              color: _videoUrl != null ? Colors.blue : Colors.grey[600],
                            ),
                            label: Text(
                              _videoUrl != null ? 'Change Video' : 'Add Video',
                              style: TextStyle(
                                color: _videoUrl != null ? Colors.blue : Colors.grey[600],
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: _videoUrl != null ? Colors.blue : Colors.grey[300]!,
                                width: _videoUrl != null ? 1.5 : 1,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
              
              // Selected Media Display - UPDATED to show both
              if (_imageUrl != null || _videoUrl != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      if (_imageUrl != null) ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.image, color: Colors.green, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Image',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _imageUrl!.split('/').last,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => ConfirmationDialog(
                                    title: 'Delete Image',
                                    message: 'Are you sure you want to delete this image?',
                                    primaryColor: widget.primaryColor,
                                  ),
                                );
                                if (confirmed == true) {
                                  _clearImage();
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],

                      if (_imageUrl != null && _videoUrl != null) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1),
                        ),
                      ],

                      if (_videoUrl != null) ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.video_library, color: Colors.blue, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Video',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _videoUrl!.split('/').last,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => ConfirmationDialog(
                                    title: 'Delete Video',
                                    message: 'Are you sure you want to delete this video?',
                                    primaryColor: widget.primaryColor,
                                  ),
                                );
                                if (confirmed == true) {
                                  _clearVideo();
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Action Buttons
              Row(
                children: [
                  // Cancel Button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Add Exercise Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          // Check if still uploading
                          if (_isUploadingImage || _isUploadingVideo) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please wait for uploads to complete'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          
                          Navigator.pop(
                            context,
                            WorkoutExercise(
                              name: _nameController.text.trim(),
                              videoUrl: _videoUrl,
                              imageUrl: _imageUrl,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Add Exercise',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Upload warning if in progress
              if (_isUploadingImage || _isUploadingVideo) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Upload in progress. Please wait...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getFileNameFromUrl(String url) {
    try {
      Uri uri = Uri.parse(url);
      String path = uri.path;
      return path.split('/').last;
    } catch (e) {
      return 'Media file';
    }
  }
}

// Edit Exercise Dialog for Custom workouts - UNCHANGED
class EditExerciseDialog extends StatefulWidget {
  final WorkoutExercise exercise;
  final Color primaryColor;
  final Color accentColor;

  const EditExerciseDialog({
    super.key,
    required this.exercise,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  State<EditExerciseDialog> createState() => _EditExerciseDialogState();
}

// Add Multi-Media Dialog for Standard Workouts - FIXED VERSION
class AddMultiMediaDialog extends StatefulWidget {
  final Color primaryColor;

  const AddMultiMediaDialog({
    super.key,
    required this.primaryColor,
  });

  @override
  State<AddMultiMediaDialog> createState() => _AddMultiMediaDialogState();
}

class _AddMultiMediaDialogState extends State<AddMultiMediaDialog> {
  final List<WorkoutMedia> _selectedMedia = [];
  final ImagePicker _picker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  bool _isUploading = false;
  String _uploadStatus = '';
  int _uploadProgress = 0;
  int _totalUploads = 0;

  Future<void> _pickImage() async {
    final images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    setState(() {
      _isUploading = true;
      _totalUploads = images.length;
      _uploadProgress = 0;
      _uploadStatus = 'Uploading images...';
    });

    for (final img in images) {
      try {
        // Create a unique filename
        String fileName = '${DateTime.now().millisecondsSinceEpoch}_${img.name}';
        Reference storageRef = _storage.ref().child('workout_media/images/$fileName');
        
        // Upload the file
        UploadTask uploadTask = storageRef.putFile(File(img.path));
        
        // Track progress
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          double progress = snapshot.bytesTransferred / snapshot.totalBytes;
          setState(() {
            _uploadStatus = 'Uploading ${img.name}: ${(progress * 100).toStringAsFixed(1)}%';
          });
        });

        // Wait for upload to complete
        TaskSnapshot snapshot = await uploadTask;
        
        // Get the download URL
        String downloadUrl = await snapshot.ref.getDownloadURL();
        
        debugPrint('✅ Image uploaded: $downloadUrl');

        setState(() {
          _selectedMedia.add(
            WorkoutMedia(url: downloadUrl, type: MediaType.image),
          );
          _uploadProgress++;
          _uploadStatus = 'Uploaded $_uploadProgress of $_totalUploads images';
        });

      } catch (e) {
        debugPrint('❌ Error uploading image ${img.name}: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload ${img.name}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }

    setState(() {
      _isUploading = false;
      _uploadStatus = '';
    });
  }

  Future<void> _pickVideo() async {
    final video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    // Check file size
    final file = File(video.path);
    final sizeMB = (await file.length()) / (1024 * 1024);
    
    if (sizeMB > 500) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video must be under 500MB'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading video...';
    });

    try {
      // Create a unique filename
      String fileName = '${DateTime.now().millisecondsSinceEpoch}_${video.name}';
      Reference storageRef = _storage.ref().child('workout_media/videos/$fileName');
      
      // Upload the file
      UploadTask uploadTask = storageRef.putFile(file);
      
      // Track progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        setState(() {
          _uploadStatus = 'Uploading video: ${(progress * 100).toStringAsFixed(1)}%';
        });
      });

      // Wait for upload to complete
      TaskSnapshot snapshot = await uploadTask;
      
      // Get the download URL
      String downloadUrl = await snapshot.ref.getDownloadURL();
      
      debugPrint('✅ Video uploaded: $downloadUrl');

      setState(() {
        _selectedMedia.add(
          WorkoutMedia(url: downloadUrl, type: MediaType.video),
        );
        _isUploading = false;
        _uploadStatus = '';
      });

    } catch (e) {
      debugPrint('❌ Error uploading video: $e');
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 480,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(
              'Add Workout Media',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.primaryColor,
              ),
            ),

            const SizedBox(height: 16),

            // Upload buttons
            Row(
              children: [
                Expanded(
                  child: _isUploading
                      ? Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(widget.primaryColor),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Uploading...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ElevatedButton.icon(
                          icon: const Icon(Icons.image),
                          label: const Text('Add Images'),
                          onPressed: _pickImage,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _isUploading
                      ? Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: const Center(
                            child: Text('Please wait...'),
                          ),
                        )
                      : ElevatedButton.icon(
                          icon: const Icon(Icons.video_library),
                          label: const Text('Add Video'),
                          onPressed: _pickVideo,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                ),
              ],
            ),

            // Upload status
            if (_uploadStatus.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _uploadStatus,
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Selected media list - pill-shaped badges like reference image
            if (_selectedMedia.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(
                      _selectedMedia.length,
                      (i) {
                        final media = _selectedMedia[i];
                        final isImage = media.type == MediaType.image;
                        final bgColor = isImage ? const Color(0xFFE8F5E9) : const Color(0xFFE3F2FD);
                        final borderColor = isImage ? const Color(0xFF4CAF50) : const Color(0xFF2196F3);
                        final textColor = isImage ? const Color(0xFF4CAF50) : const Color(0xFF2196F3);

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: borderColor, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isImage ? Icons.image : Icons.play_circle_filled,
                                color: textColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isImage ? 'Image' : 'Video',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedMedia.removeAt(i);
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedMedia.isEmpty || _isUploading
                        ? null
                        : () => Navigator.pop(context, _selectedMedia),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _isUploading ? 'Uploading...' : 'Add Selected (${_selectedMedia.length})',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      return path.split('/').last;
    } catch (e) {
      return 'Media file';
    }
  }
}


class _EditExerciseDialogState extends State<EditExerciseDialog> {
  late TextEditingController _nameController;
  String? _videoUrl;
  String? _imageUrl;
  bool _isUploadingImage = false;
  bool _isUploadingVideo = false;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.exercise.name);
    _videoUrl = widget.exercise.videoUrl;
    _imageUrl = widget.exercise.imageUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _uploadToStorage(XFile file, bool isImage) async {
    setState(() {
      if (isImage) {
        _isUploadingImage = true;
      } else {
        _isUploadingVideo = true;
      }
    });

    try {
      String fileType = isImage ? 'images' : 'videos';
      String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      Reference storageRef = _storage.ref().child('exercise_media/$fileType/$fileName');
      
      final metadata = SettableMetadata(
        contentType: isImage ? 'image/jpeg' : 'video/mp4',
        customMetadata: {
          'uploaded_at': DateTime.now().toIso8601String(),
          'source': 'admin_panel_edit',
        },
      );
      
      UploadTask uploadTask = storageRef.putFile(File(file.path), metadata);
      
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        debugPrint('Edit upload progress: ${(progress * 100).toStringAsFixed(2)}%');
      });

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      
      debugPrint('✅ Edited ${isImage ? "image" : "video"} URL: $downloadUrl');
      
      if (mounted) {
        setState(() {
          if (isImage) {
            _imageUrl = downloadUrl;
            _isUploadingImage = false;
          } else {
            _videoUrl = downloadUrl;
            _isUploadingVideo = false;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isImage ? 'Image' : 'Video'} uploaded successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Edit upload failed: $e');
      if (mounted) {
        setState(() {
          if (isImage) {
            _isUploadingImage = false;
          } else {
            _isUploadingVideo = false;
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (image != null) {
        await _uploadToStorage(image, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      
      if (video != null) {
        final file = File(video.path);
        final fileSize = await file.length();
        final fileSizeInMB = fileSize / (1024 * 1024);
        
        if (fileSizeInMB > 500) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video size exceeds 500MB limit'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        
        debugPrint('📹 Selected video for edit: ${video.path}');
        await _uploadToStorage(video, false);
      }
    } catch (e) {
      debugPrint('❌ Error picking video: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking video: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Update the build method's UI to show upload progress
  // Replace the existing media section with this updated version:

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.edit, color: widget.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Edit Exercise',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: widget.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Exercise Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.primaryColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.fitness_center),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an exercise name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Media Attachments (Optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _isUploadingImage
                        ? Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: Icon(Icons.image, color: _imageUrl != null ? Colors.green : Colors.grey[600]),
                            label: Text(
                              _imageUrl != null ? 'Change Image' : 'Add Image',
                              style: TextStyle(
                                color: _imageUrl != null ? Colors.green : Colors.grey[600],
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: _imageUrl != null ? Colors.green : Colors.grey[300]!,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _isUploadingVideo
                        ? Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: _pickVideo,
                            icon: Icon(Icons.video_library, color: _videoUrl != null ? Colors.blue : Colors.grey[600]),
                            label: Text(
                              _videoUrl != null ? 'Change Video' : 'Add Video',
                              style: TextStyle(
                                color: _videoUrl != null ? Colors.blue : Colors.grey[600],
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(
                                color: _videoUrl != null ? Colors.blue : Colors.grey[300]!,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
              if (_imageUrl != null || _videoUrl != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      if (_imageUrl != null)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.image, color: Colors.green, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _getFileNameFromUrl(_imageUrl!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => ConfirmationDialog(
                                    title: 'Delete Image',
                                    message: 'Are you sure you want to delete this image?',
                                    primaryColor: widget.primaryColor,
                                  ),
                                );
                                if (confirmed == true) {
                                  setState(() => _imageUrl = null);
                                }
                              },
                            ),
                          ],
                        ),
                      if (_imageUrl != null && _videoUrl != null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1),
                        ),
                      if (_videoUrl != null)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.video_library, color: Colors.blue, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _getFileNameFromUrl(_videoUrl!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => ConfirmationDialog(
                                    title: 'Delete Video',
                                    message: 'Are you sure you want to delete this video?',
                                    primaryColor: widget.primaryColor,
                                  ),
                                );
                                if (confirmed == true) {
                                  setState(() => _videoUrl = null);
                                }
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
              // Upload warning if in progress
              if (_isUploadingImage || _isUploadingVideo) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Upload in progress. Please wait...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          if (_isUploadingImage || _isUploadingVideo) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please wait for uploads to complete'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          
                          Navigator.pop(
                            context,
                            WorkoutExercise(
                              name: _nameController.text,
                              videoUrl: _videoUrl,
                              imageUrl: _imageUrl,
                              isSelected: widget.exercise.isSelected,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Changes',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      return path.split('/').last;
    } catch (e) {
      return 'Media file';
    }
  }
}

// Add Custom Group Dialog (UNCHANGED)
class AddCustomGroupDialog extends StatefulWidget {
  final Color primaryColor;

  const AddCustomGroupDialog({
    super.key,
    required this.primaryColor,
  });

  @override
  State<AddCustomGroupDialog> createState() => _AddCustomGroupDialogState();
}

class _AddCustomGroupDialogState extends State<AddCustomGroupDialog> {
  final TextEditingController _nameController = TextEditingController();
  String? _selectedEmoji;
  final _formKey = GlobalKey<FormState>();

  final List<String> _commonEmojis = [
    '🏋🏻', '🏃🏼‍♀️', '🦵', '⬆️', '📉', '📈', '💪', '🏋🏻‍♀️', '🧍‍♂️',
    '🏋️‍♂️', '🤸', '🏃', '🧘', '🎯', '⚡', '🔥', '💯', '⭐'
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.category, color: widget.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Add Workout Group',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: widget.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Group Name',
                  hintText: 'e.g., Core, Cardio, Arms',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.primaryColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a group name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Choose Emoji',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    childAspectRatio: 1,
                  ),
                  itemCount: _commonEmojis.length,
                  itemBuilder: (context, index) {
                    final emoji = _commonEmojis[index];
                    return InkWell(
                      onTap: () => setState(() => _selectedEmoji = emoji),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: _selectedEmoji == emoji
                              ? widget.primaryColor.withValues(alpha: 0.1)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          border: _selectedEmoji == emoji
                              ? Border.all(color: widget.primaryColor)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          Navigator.pop(context, {
                            'name': _nameController.text,
                            'emoji': _selectedEmoji ?? '',
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Add Group',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Client Selection Dialog (UNCHANGED)
class ClientSelectionDialog extends StatefulWidget {
  final List<QueryDocumentSnapshot> clients;
  final List<String> initiallySelected;
  final Color primaryColor;

  const ClientSelectionDialog({
    super.key,
    required this.clients,
    required this.initiallySelected,
    required this.primaryColor,
  });

  @override
  State<ClientSelectionDialog> createState() => _ClientSelectionDialogState();
}

class _ClientSelectionDialogState extends State<ClientSelectionDialog> {
  late Set<String> _selectedIds;
  final TextEditingController _searchController = TextEditingController();
  List<QueryDocumentSnapshot> _filteredClients = [];

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initiallySelected);
    _filteredClients = widget.clients;
    _searchController.addListener(_filterClients);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterClients() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredClients = widget.clients.where((client) {
        final data = client.data() as Map<String, dynamic>;
        final name = data['name']?.toString().toLowerCase() ?? '';
        final email = data['email']?.toString().toLowerCase() ?? '';
        return name.contains(query) || email.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 4,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            Text(
              'Select Clients',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search clients',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: widget.primaryColor),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: _filteredClients.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'No clients found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredClients.length,
                      itemBuilder: (context, index) {
                        final client = _filteredClients[index];
                        final data = client.data() as Map<String, dynamic>;
                        final name = data['name'] ?? 'Unnamed Client';
                        final email = data['email'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: _selectedIds.contains(client.id)
                                    ? widget.primaryColor
                                    : Colors.grey[200]!,
                                width: _selectedIds.contains(client.id) ? 1.5 : 1,
                              ),
                            ),
                            child: CheckboxListTile(
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: _selectedIds.contains(client.id)
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _selectedIds.contains(client.id)
                                      ? widget.primaryColor
                                      : Colors.grey[800],
                                ),
                              ),
                              subtitle: Text(
                                email,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              value: _selectedIds.contains(client.id),
                              onChanged: (selected) {
                                setState(() {
                                  if (selected == true) {
                                    _selectedIds.add(client.id);
                                  } else {
                                    _selectedIds.remove(client.id);
                                  }
                                });
                              },
                              activeColor: widget.primaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selectedIds.toList()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Confirmation Dialog (UNCHANGED)
// Confirmation Dialog (UPDATED to support custom color)
class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final Color primaryColor;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}