import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import '../models/workout_assignment.dart';

class ClientWorkoutScreen extends StatefulWidget {
  const ClientWorkoutScreen({super.key});

  @override
  State<ClientWorkoutScreen> createState() => _ClientWorkoutScreenState();
}

class _ClientWorkoutScreenState extends State<ClientWorkoutScreen>
    with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _dateFormatter = DateFormat('MMM d, yyyy');
  final _timeFormatter = DateFormat('hh:mm a');
  final Color _primaryColor = const Color(0xFF1C2D5E);
  final Color _accentColor = Colors.blue[700]!;
  final Color _textColor = Colors.blue[900]!;
  final Map<String, bool> _expandedWorkouts = {};
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, ChewieController> _chewieControllers = {};

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    for (var controller in _chewieControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid;

    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'My Workouts',
            style: TextStyle(
              color: Colors.white,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: _primaryColor,
        ),
        body: const Center(
          child: Text('Please log in to view workouts'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'My Workouts',
          style: TextStyle(
            color: Colors.white,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: _primaryColor,
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.assignment_turned_in, size: 20),
              text: 'Active',
            ),
            Tab(
              icon: Icon(Icons.archive, size: 20),
              text: 'Archive',
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() {});
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveWorkouts(currentUserId),
          _buildArchivedWorkouts(currentUserId),
        ],
      ),
    );
  }

  Widget _buildActiveWorkouts(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('workout_assignments')
          .where('clientId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No active workouts assigned yet'));
        }

        final assignments = snapshot.data!.docs
            .map((doc) => WorkoutAssignment.fromJson(doc.id, doc.data() as Map<String, dynamic>))
            .where((a) => a.status == AssignmentStatus.active && !a.isExpired)
            .toList()
            ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

        if (assignments.isEmpty) {
          return const Center(child: Text('No active workouts'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: assignments.length,
          itemBuilder: (context, index) {
            return _buildWorkoutCard(
              assignment: assignments[index],
              index: index,
              isMostRecent: index == 0,
            );
          },
        );
      },
    );
  }

  Widget _buildArchivedWorkouts(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('workout_assignments')
          .where('clientId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No archived workouts'));
        }

        final assignments = snapshot.data!.docs
            .map((doc) => WorkoutAssignment.fromJson(doc.id, doc.data() as Map<String, dynamic>))
            .where((a) => a.status == AssignmentStatus.archived)
            .toList()
            ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

        if (assignments.isEmpty) {
          return const Center(child: Text('No archived workouts'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: assignments.length,
          itemBuilder: (context, index) {
            return _buildWorkoutCard(
              assignment: assignments[index],
              index: index,
              isMostRecent: false,
            );
          },
        );
      },
    );
  }

  Widget _buildWorkoutCard({
    required WorkoutAssignment assignment,
    required int index,
    required bool isMostRecent,
  }) {
    final isExpanded = _expandedWorkouts[assignment.id] ?? isMostRecent;

    return Card(
      elevation: isMostRecent ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isMostRecent ? _accentColor : Colors.grey.withValues(alpha: 0.2),
          width: isMostRecent ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expandedWorkouts[assignment.id] = !isExpanded;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isMostRecent ? _primaryColor : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (index + 1).toString(),
                        style: TextStyle(
                          color: isMostRecent ? Colors.white : _primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                assignment.workoutName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: _primaryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (assignment.status == AssignmentStatus.active && !assignment.isExpired)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [const Color(0xFF00B894), const Color(0xFF00B894).withValues(alpha: 0.8)],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  '${assignment.daysRemaining}d left',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 14, color: _textColor),
                            const SizedBox(width: 4),
                            Text(
                              '${assignment.formattedStartDate} → ${assignment.formattedEndDate}',
                              style: TextStyle(fontSize: 12, color: _textColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 14, color: _textColor),
                            const SizedBox(width: 4),
                            Text(
                              _timeFormatter.format(assignment.assignedAt),
                              style: TextStyle(fontSize: 12, color: _textColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.person_outline, size: 14, color: _textColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'By: Kenny Sims',
                                style: TextStyle(fontSize: 12, color: _textColor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _primaryColor,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildExercisesSection(assignment),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExercisesSection(WorkoutAssignment assignment) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('workout_assignments').doc(assignment.id).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final exercisesList = (data?['exercises'] as List?) ?? [];
        final exercises = List.from(exercisesList);

        if (exercises.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No exercises in this workout',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EXERCISES',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: _primaryColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            ...exercises.map((exercise) {
              if (exercise is Map<String, dynamic>) {
                return _buildExerciseItem(exercise);
              }
              return const SizedBox.shrink();
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildExerciseItem(Map<String, dynamic> exercise) {
    final exerciseName = exercise['name'] ?? exercise['exerciseName'] ?? 'Exercise';
    final sets = exercise['sets'];
    final reps = exercise['reps'];
    final imageUrl = exercise['imageUrl'] as String?;
    final videoUrl = exercise['videoUrl'] as String?;

    final hasImage = _isValidUrl(imageUrl);
    final hasVideo = _isValidUrl(videoUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            Colors.grey[50]!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _primaryColor.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_primaryColor, _primaryColor.withValues(alpha: 0.8)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _primaryColor.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('💪', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        exerciseName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: _primaryColor,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (hasImage || hasVideo) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (hasImage)
                        GestureDetector(
                          onTap: () => _showMediaDialog(imageUrl!, 'image', exerciseName),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green[50]!,
                                  Colors.green[100]!,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.green[300]!,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.image_rounded, size: 15, color: Colors.green[700]),
                                const SizedBox(width: 4),
                                Text(
                                  'Exercise Guide',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (hasVideo)
                        GestureDetector(
                          onTap: () async {
                            await _openVideoDialog(videoUrl!, exerciseName);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue[50]!,
                                  Colors.blue[100]!,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.blue[300]!,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_circle_rounded, size: 15, color: Colors.blue[700]),
                                const SizedBox(width: 4),
                                Text(
                                  'Demo Video',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (sets != null || reps != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Wrap(
                spacing: 16,
                children: [
                  if (sets != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.repeat, size: 16, color: _primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          'Sets: $sets',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  if (reps != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fitness_center, size: 16, color: _primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          'Reps: $reps',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool _isValidUrl(dynamic url) {
    if (url == null) return false;
    final urlStr = url.toString().trim();
    return urlStr.isNotEmpty && (urlStr.startsWith('http://') || urlStr.startsWith('https://'));
  }

  void _showMediaDialog(String url, String type, String title) {
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
                    imageUrl: url,
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

  Future<void> _openVideoDialog(String videoUrl, String exerciseName) async {
    final videoKey = 'dialog-$exerciseName-$videoUrl';
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
                final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
                await controller.initialize();
                _videoControllers[videoKey] = controller;

                final chewieController = ChewieController(
                  videoPlayerController: controller,
                  autoPlay: true,
                  looping: false,
                  allowFullScreen: true,
                  allowMuting: true,
                  showOptions: false,
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
              }
            }
          }

          return WillPopScope(
            onWillPop: () async {
              _videoControllers[videoKey]?.pause();
              Navigator.pop(context);
              return false;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _videoControllers[videoKey]?.pause();
              },
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(16),
                child: Container(
                  height: 350,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _videoControllers[videoKey] != null && _chewieControllers[videoKey] != null
                            ? Chewie(controller: _chewieControllers[videoKey]!)
                            : GestureDetector(
                                onTap: isLoadingVideo ? null : initializeAndPlayVideo,
                                child: Container(
                                  color: Colors.black,
                                  child: Center(
                                    child: isLoadingVideo
                                        ? const Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                              SizedBox(height: 16),
                                              Text(
                                                'Loading video...',
                                                style: TextStyle(color: Colors.white70, fontSize: 14),
                                              ),
                                            ],
                                          )
                                        : Container(
                                            width: 80,
                                            height: 80,
                                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
                                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
                                          ),
                                  ),
                                ),
                              ),
                      ),
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
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            _videoControllers[videoKey]?.pause();
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
