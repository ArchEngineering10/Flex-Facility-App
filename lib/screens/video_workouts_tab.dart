import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'square_checkout.dart';
import '../constants.dart';

class VideoWorkoutsTab extends StatefulWidget {
  const VideoWorkoutsTab({super.key});

  @override
  State<VideoWorkoutsTab> createState() => _VideoWorkoutsTabState();
}

class _VideoWorkoutsTabState extends State<VideoWorkoutsTab> {
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  List<Map<String, dynamic>> _videoWorkouts = [];
  List<Map<String, dynamic>> _filteredWorkouts = [];
  Set<String> _categories = {};
  Map<String, IconData> _categoryIcons = {};
  String _selectedCategory = '';
  Set<String> _savedVideoIds = {};
  String _filterType = 'all'; // 'all' or 'saved'

  // Subscription variables
  bool _hasActiveVideoSubscription = false;
  DateTime? _videoSubscriptionEndDate;
  bool _isCheckingVideoSubscription = true;
  bool _isProcessingVideoPayment = false;
  int _daysRemainingUntilExpiry = 0;
  bool _showExpirationWarning = false;

  // Expiration warning shows when 3 days or less remain
  static const int EXPIRATION_WARNING_DAYS = 3;

  // Square payment configuration
  static const String _squareApplicationId = AppConstants.squareApplicationId;
  static const String _squareLocationId = 'L8S08PC1N6RPJ';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _videoWorkoutsSubscription;

  final Map<String, IconData> _defaultIcons = {
    'strength': Icons.fitness_center,
    'cardio': Icons.favorite,
    'yoga': Icons.self_improvement,
    'hiit': Icons.local_fire_department,
    'mobility': Icons.sports_gymnastics,
  };

  final Map<String, Color> _defaultColors = {
    'strength': const Color(0xFF7C3AED),
    'cardio': const Color(0xFFEC4899),
    'yoga': const Color(0xFF10B981),
    'hiit': const Color(0xFFF97316),
    'mobility': const Color(0xFF3B82F6),
  };

  final List<IconData> _customIcons = [
    Icons.fitness_center,
    Icons.favorite,
    Icons.self_improvement,
    Icons.local_fire_department,
    Icons.sports_gymnastics,
    Icons.directions_run,
    Icons.sports_tennis,
    Icons.pool,
    Icons.hiking,
    Icons.sports_basketball,
    Icons.sports_soccer,
    Icons.sports_volleyball,
  ];

  @override
  void initState() {
    super.initState();
    _checkVideoSubscriptionStatus();
    _setupVideoWorkoutsListener();
    _loadSavedVideos();
  }

  // ---------- Video Subscription Status Check ----------
  Future<void> _checkVideoSubscriptionStatus() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        setState(() => _isCheckingVideoSubscription = false);
        return;
      }

      final subscriptionSnapshot = await _firestore
          .collection('client_subscriptions')
          .where('userId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .where('type', isEqualTo: 'video')
          .get();

      if (subscriptionSnapshot.docs.isNotEmpty) {
        final subscription = subscriptionSnapshot.docs.first.data();
        DateTime endDate;
        if (subscription['endDate'] is String) {
          endDate = DateTime.parse(subscription['endDate'] as String).toLocal();
        } else if (subscription['endDate'] is Timestamp) {
          endDate = (subscription['endDate'] as Timestamp).toDate().toLocal();
        } else {
          throw Exception('Invalid endDate format');
        }

        final currentLocalTime = DateTime.now().toLocal();

        // Calculate days remaining
        final daysUntilExpiry = endDate.difference(currentLocalTime).inDays;

        // Show warning if 5 days or less remaining
        final shouldShowWarning = daysUntilExpiry <= EXPIRATION_WARNING_DAYS && daysUntilExpiry > 0;

        setState(() {
          _hasActiveVideoSubscription = currentLocalTime.isBefore(endDate);
          _videoSubscriptionEndDate = endDate;
          _daysRemainingUntilExpiry = daysUntilExpiry > 0 ? daysUntilExpiry : 0;
          _showExpirationWarning = shouldShowWarning;
        });
      } else {
        setState(() {
          _hasActiveVideoSubscription = false;
          _videoSubscriptionEndDate = null;
        });
      }
    } catch (e) {
      setState(() {
        _hasActiveVideoSubscription = false;
        _videoSubscriptionEndDate = null;
      });
    } finally {
      setState(() => _isCheckingVideoSubscription = false);
    }
  }

  @override
  void dispose() {
    _videoWorkoutsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  IconData _getIconForCategory(String category) {
    final key = category.toLowerCase();
    // Check default icons first
    if (_defaultIcons.containsKey(key)) {
      return _defaultIcons[key]!;
    }
    // For custom categories, use hash-based icon selection
    final iconIndex = category.hashCode.abs() % _customIcons.length;
    return _customIcons[iconIndex];
  }

  Color _getColorForCategory(String category) {
    final key = category.toLowerCase();
    return _defaultColors[key] ?? Colors.blueAccent;
  }

  void _setupVideoWorkoutsListener() {
    _videoWorkoutsSubscription = _firestore
        .collection('video_workouts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (!mounted) return;
      setState(() {
        _videoWorkouts = snapshot.docs.map((doc) {
          final data = doc.data();
          data['docId'] = doc.id;
          return data;
        }).toList();

        // Extract unique categories from added videos only
        _categories = _videoWorkouts
            .map((v) => (v['category'] ?? 'Other').toString())
            .toSet();

        // Build category icons map
        _categoryIcons = {};
        for (final cat in _categories) {
          _categoryIcons[cat] = _getIconForCategory(cat);
        }

        _filterWorkouts();
        _isLoading = false;
      });
    }, onError: (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    });
  }

  void _filterWorkouts() {
    _filteredWorkouts = _videoWorkouts.where((video) {
      final matchesSearch = (video['name'] ?? '')
              .toString()
              .toLowerCase()
              .contains(_searchController.text.toLowerCase()) ||
          (video['description'] ?? '')
              .toString()
              .toLowerCase()
              .contains(_searchController.text.toLowerCase());

      final matchesCategory = _selectedCategory.isEmpty ||
          (video['category'] ?? '').toString() == _selectedCategory;

      final matchesSaved = _filterType == 'all' ||
          (_filterType == 'saved' && _savedVideoIds.contains(video['docId']));

      return matchesSearch && matchesCategory && matchesSaved;
    }).toList();
  }

  void _showVideoPlayer(Map<String, dynamic> video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => VideoPlayerModal(video: video, allVideos: _videoWorkouts),
      ),
    );
  }

  Future<void> _toggleSaveVideo(Map<String, dynamic> video) async {
    final videoId = video['docId'];
    if (videoId == null) return;

    try {
      // Get current user
      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      if (currentUser == null) return;

      final userId = currentUser.uid;
      final docPath = _firestore
          .collection('users')
          .doc(userId)
          .collection('saved_workouts')
          .doc(videoId);

      if (_savedVideoIds.contains(videoId)) {
        // Remove from saved
        _savedVideoIds.remove(videoId);
        await docPath.delete().catchError((e) {
          print('Error deleting saved workout: $e');
        });
      } else {
        // Add to saved - store complete video data for offline access
        _savedVideoIds.add(videoId);
        await docPath.set({
          'videoId': videoId,
          'videoName': video['name'],
          'description': video['description'] ?? '',
          'category': video['category'] ?? 'Other',
          'difficulty': video['difficulty'] ?? 'Beginner',
          'thumbnailUrl': video['thumbnailUrl'] ?? '',
          'videoUrl': video['videoUrl'] ?? '',
          'duration': video['duration'] ?? '',
          'savedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) setState(() {});
    } catch (e) {
      print('Error toggling save: $e');
    }
  }

  Future<void> _loadSavedVideos() async {
    try {
      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      if (currentUser == null) return;

      final userId = currentUser.uid;
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('saved_workouts')
          .get();

      if (mounted) {
        setState(() {
          _savedVideoIds = Set.from(snapshot.docs.map((doc) => doc.id));
        });
      }
    } catch (e) {
      print('Error loading saved videos: $e');
    }
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'beginner':
        return const Color(0xFF10B981);
      case 'intermediate':
        return const Color(0xFFF59E0B);
      case 'advanced':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  // ---------- Subscription Lock UI ----------
  Widget _buildSubscriptionLockUI() {
    return Container(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Lock Icon in Purple Circle
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE8D4FF),
              ),
              child: const Center(
                child: Icon(
                  Icons.lock,
                  size: 45,
                  color: Color(0xFF7C3AED),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              'Premium Content',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),

            // Subtitle
            Text(
              'Unlock all video workouts and enhance your fitness journey',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // Why Subscribe Section with dividers
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                    thickness: 1.5,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'Why Subscribe?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                    thickness: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Feature Items
            _premiumFeatureItem(
              icon: Icons.play_circle_outline,
              title: 'Unlimited Videos',
              description: 'Access complete workout library',
            ),
            const SizedBox(height: 8),
            _premiumFeatureItem(
              icon: Icons.bookmark,
              title: 'Save Videos',
              description: 'Save your favorite workouts',
            ),
            const SizedBox(height: 8),
            _premiumFeatureItem(
              icon: Icons.hd,
              title: 'Premium Quality',
              description: 'High-definition video content',
            ),
            const SizedBox(height: 16),

            // Subscribe Button - Direct to Checkout
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessingVideoPayment
                    ? null
                    : () => _processVideoSubscriptionPayment(),
                icon: const Icon(Icons.lock, size: 20),
                label: Text(
                  _isProcessingVideoPayment ? 'Processing...' : 'Subscribe Now',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _premiumFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: const Color(0xFFE8D4FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 32,
              color: const Color(0xFF7C3AED),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpirationWarningBanner() {
    if (!_showExpirationWarning) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFE69C),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber,
            color: Color(0xFFF0AD4E),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subscription Expiring Soon',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8B6914),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Renew in $_daysRemainingUntilExpiry day${_daysRemainingUntilExpiry == 1 ? '' : 's'} to keep access',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF8B6914).withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: () => _processVideoSubscriptionPayment(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Renew',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Process Video Subscription Payment ----------
  Future<void> _processVideoSubscriptionPayment() async {
    Navigator.pop(context);

    setState(() => _isProcessingVideoPayment = true);

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not logged in');

      // Get user profile
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userName = userDoc['name'] ?? 'Customer';
      final userEmail = userDoc['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '';

      // Navigate to payment
      if (!mounted) return;
      final plan = {
        'docId': 'video_subscription_monthly',
        'name': 'Video Workouts Monthly Subscription',
        'category': 'Video Access',
        'sessions': 1,
        'price': 1.00,
        'description': 'Unlimited access to all video workouts for 30 days',
        'type': 'video',
        'buyerEmail': userEmail,
        'buyerName': userName,
      };

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SquarePaymentPage(
            plan: plan,
            squareApplicationId: _squareApplicationId,
            squareLocationId: _squareLocationId,
          ),
        ),
      );

      // The backend creates the subscription only after Square confirms payment.
      await _checkVideoSubscriptionStatus();

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isProcessingVideoPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show subscription lock UI if no active subscription
    if (_isCheckingVideoSubscription) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasActiveVideoSubscription) {
      return _buildSubscriptionLockUI();
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      children: [
        // Expiration Warning Banner
        _buildExpirationWarningBanner(),

        // Search Bar and Filter
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() => _filterWorkouts()),
                  decoration: InputDecoration(
                    hintText: 'Search workouts...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2D5E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PopupMenuButton<String>(
                  onSelected: (String value) {
                    setState(() {
                      _filterType = value;
                      _filterWorkouts();
                    });
                  },
                  itemBuilder: (BuildContext context) => [
                    PopupMenuItem<String>(
                      value: 'all',
                      child: Text(
                        'All Videos',
                        style: TextStyle(
                          color: _filterType == 'all' ? const Color(0xFF1C2D5E) : Colors.black,
                          fontWeight: _filterType == 'all' ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'saved',
                      child: Text(
                        'Saved Videos',
                        style: TextStyle(
                          color: _filterType == 'saved' ? const Color(0xFF1C2D5E) : Colors.black,
                          fontWeight: _filterType == 'saved' ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.tune, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Category Filter - Horizontal Scrollable (Only Added Categories)
        // Hide categories when filtering by saved videos
        if (_categories.isNotEmpty && _filterType != 'saved')
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // "All" category
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCategory = '';
                      _filterWorkouts();
                    });
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _selectedCategory.isEmpty
                              ? const Color(0xFF1C2D5E)
                              : Colors.grey[200],
                        ),
                        child: Icon(
                          Icons.apps,
                          color: _selectedCategory.isEmpty
                              ? Colors.white
                              : Colors.grey[600],
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'All',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _selectedCategory.isEmpty
                              ? const Color(0xFF1C2D5E)
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Category buttons (only added ones)
                ...(_categories.toList().map((category) {
                  final isSelected = _selectedCategory == category;
                  final color = _getColorForCategory(category);
                  final icon = _categoryIcons[category] ?? Icons.fitness_center;

                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = isSelected ? '' : category;
                          _filterWorkouts();
                        });
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? color : color.withAlpha(51),
                            ),
                            child: Icon(
                              icon,
                              color: isSelected ? Colors.white : color,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            category,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? color : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList()),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Video List
        Expanded(
          child: _filteredWorkouts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.videocam,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No videos found',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filteredWorkouts.length,
                  itemBuilder: (context, index) {
                    return _buildVideoCard(_filteredWorkouts[index], index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildVideoCard(Map<String, dynamic> video, int index) {
    final name = video['name'] ?? 'Video Workout';
    final difficulty = video['difficulty'] ?? 'Beginner';
    final imageUrl = video['thumbnailUrl'] ?? '';
    final duration = video['duration'] ?? '';

    return GestureDetector(
      onTap: () => _showVideoPlayer(video),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with play button and duration
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Container(
                    width: 180,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[800],
                                child: const Center(
                                  child: Icon(Icons.videocam,
                                      color: Colors.white, size: 40),
                                ),
                              );
                            },
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(Icons.videocam,
                                  color: Colors.white, size: 40),
                            ),
                          ),
                  ),
                  // Play Button
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(220),
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.black,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  // Duration Badge (bottom-right)
                  if (duration.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(200),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          duration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Video Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Difficulty
                  Text(
                    difficulty,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getDifficultyColor(difficulty),
                    ),
                  ),
                  if (duration.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '⏱ $duration',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Save/Bookmark Button
            IconButton(
              onPressed: () => _toggleSaveVideo(video),
              icon: Icon(
                _savedVideoIds.contains(video['docId']) ? Icons.bookmark : Icons.bookmark_border,
                color: _savedVideoIds.contains(video['docId']) ? Colors.green : Colors.grey[400],
                size: 24,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

// In-App Video Player Modal
class VideoPlayerModal extends StatefulWidget {
  final Map<String, dynamic> video;
  final List<Map<String, dynamic>> allVideos;

  const VideoPlayerModal({
    super.key,
    required this.video,
    required this.allVideos,
  });

  @override
  State<VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<VideoPlayerModal> {
  late ScrollController _scrollController;
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initializeVideo();
    _extractThumbnail();
  }

  Future<void> _extractThumbnail() async {
    // Thumbnail extraction no longer needed - Chewie player handles this
  }

  Future<void> _initializeVideo() async {
    try {
      final videoUrl = widget.video['videoUrl'];
      if (videoUrl == null || videoUrl.isEmpty) {
        return;
      }

      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _videoController.initialize();

      final thumbnailUrl = widget.video['thumbnailUrl'] as String?;

      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        playbackSpeeds: const [0.5, 1.0, 1.5, 2.0],
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFF1C2D5E),
          handleColor: const Color(0xFF1C2D5E),
          backgroundColor: Colors.grey[300]!,
          bufferedColor: Colors.grey[400]!,
        ),
      );

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'beginner':
        return const Color(0xFF10B981);
      case 'intermediate':
        return const Color(0xFFF59E0B);
      case 'advanced':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.video['name'] ?? 'Video Workout';
    final description = widget.video['description'] ?? '';
    final difficulty = widget.video['difficulty'] ?? 'Beginner';
    final category = widget.video['category'] ?? 'Workout';
    final imageUrl = widget.video['thumbnailUrl'] ?? '';
    final duration = widget.video['duration'] ?? '';

    // Get related videos (same category)
    final relatedVideos = widget.allVideos
        .where((v) =>
            v['category'] == category &&
            v['docId'] != widget.video['docId'])
        .take(6)
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

                // Video Player with Chewie - Direct video without thumbnail
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      height: 250,
                      color: Colors.black,
                      child: _isInitialized && _chewieController != null
                          ? Chewie(controller: _chewieController!)
                          : const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Video Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Difficulty & Category Tags
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _getDifficultyColor(difficulty).withAlpha(51),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          difficulty,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getDifficultyColor(difficulty),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(51),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // About This Workout
                if (description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'About this workout',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // Related Videos Section - List Style
                if (relatedVideos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'More Workouts',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: relatedVideos.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final relatedVideo = relatedVideos[index];
                            final thumbnailUrl = relatedVideo['thumbnailUrl'] as String?;
                            final difficulty = relatedVideo['difficulty'] ?? 'Beginner';
                            final duration = relatedVideo['duration'] ?? '';

                            return GestureDetector(
                              onTap: () {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    fullscreenDialog: true,
                                    builder: (context) => VideoPlayerModal(
                                      video: relatedVideo,
                                      allVideos: widget.allVideos,
                                    ),
                                  ),
                                );
                              },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Thumbnail on left
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      children: [
                                        Container(
                                          width: 180,
                                          height: 100,
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                                              ? Image.network(
                                                  thumbnailUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return Container(
                                                      color: Colors.grey[800],
                                                      child: const Center(
                                                        child: Icon(Icons.videocam,
                                                            color: Colors.white, size: 32),
                                                      ),
                                                    );
                                                  },
                                                )
                                              : Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[800],
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: const Center(
                                                    child: Icon(Icons.videocam,
                                                        color: Colors.white, size: 32),
                                                  ),
                                                ),
                                        ),
                                        // Play Button
                                        Positioned.fill(
                                          child: Center(
                                            child: Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white.withAlpha(220),
                                              ),
                                              child: const Icon(
                                                Icons.play_arrow,
                                                color: Colors.black,
                                                size: 28,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Duration Badge (bottom-right)
                                        if (duration.isNotEmpty)
                                          Positioned(
                                            bottom: 8,
                                            right: 8,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withAlpha(200),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                duration,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Video Details on right
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          relatedVideo['name'] ?? 'Video Workout',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 6),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _getDifficultyColor(difficulty).withAlpha(51),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                difficulty,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: _getDifficultyColor(difficulty),
                                                ),
                                              ),
                                            ),
                                            if (duration.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                '⏱ $duration',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
  }
}
