import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/shimmer_loading.dart';
import '../widgets/rating_dialog.dart';
import 'chat_screen.dart';
import 'client_book_slot.dart';
import 'client_plans_screen.dart';
import 'schedule_screen.dart';
import 'post_announcement_client.dart';
import 'profileScreen.dart';

// ---------------------------------------------------------------------------
// DashboardItem model
// ---------------------------------------------------------------------------

class DashboardItem {
  final IconData icon;
  final String label;
  final Color color;
  final Widget? targetScreen;
  final VoidCallback? action;
  final bool showBadge;
  final bool enabled;

  DashboardItem({
    required this.icon,
    required this.label,
    required this.color,
    this.targetScreen,
    this.action,
    this.showBadge = false,
    this.enabled = true,
  });
}

// ---------------------------------------------------------------------------
// ClientDashboard
// ---------------------------------------------------------------------------

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  // ── profile / session data ────────────────────────────────────────────────
  String firstName = '';
  String? firestorePhotoUrl;
  File? localImageFile;
  bool isLoading = true;
  String? errorMessage;
  int completedSessions = 0;
  String? nextUpcomingSessionTime;
  Map<String, bool> _tabDisabledStatus = {};

  // ── subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<QuerySnapshot>? _sessionsSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _profileListener;
  Timer? _timer;

  static const Color _navy = Color(0xFF1C2D5E);

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        final ok = await _enforceVerifiedAccess(user);
        if (!ok) return;
        _fetchUserProfile();
        _setupSessionsListener();
        _setupProfileListener();
      }
    });

    final initial = FirebaseAuth.instance.currentUser;
    if (initial != null) {
      _enforceVerifiedAccess(initial).then((ok) {
        if (!ok) return;
        _fetchUserProfile();
        _setupSessionsListener();
        _setupProfileListener();
      });
    }

    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    FirebaseMessaging.onMessage.listen((msg) {
      if (msg.notification != null && mounted) _showFcmSnackbar(msg);
    });

    _saveFcmToken();
    FirebaseMessaging.instance.onTokenRefresh.listen(_updateFcmToken);
  }

  @override
  void dispose() {
    _sessionsSubscription?.cancel();
    _authSubscription?.cancel();
    _profileListener?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  // ── access guard ──────────────────────────────────────────────────────────

  Future<bool> _enforceVerifiedAccess(User? user) async {
    if (user == null) return false;
    await user.reload();
    final refreshed = FirebaseAuth.instance.currentUser;
    if (refreshed == null || !refreshed.emailVerified) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please verify your email before accessing the app.'),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return false;
    }
    return true;
  }

  // ── FCM ───────────────────────────────────────────────────────────────────

  Future<void> _saveFcmToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'fcm_token': token}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _updateFcmToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'fcm_token': token}, SetOptions(merge: true));
    } catch (_) {}
  }

  void _showFcmSnackbar(RemoteMessage msg) {
    final msgType = msg.data['type'] ?? '';

    // Session rating prompt — show the rating bottom sheet directly
    if (msgType == 'session_rating_prompt') {
      final slotId   = msg.data['slotId'] ?? '';
      final slotTime = msg.data['slotTime'] ?? '';
      final slotDate = msg.data['slotDate'] ?? '';
      if (slotId.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            SessionRatingSheet.show(
              context,
              slotId: slotId,
              slotTime: slotTime,
              slotDate: slotDate,
            );
          }
        });
      }
      return;
    }

    final isReminder = msgType == 'session_reminder';
    final title = msg.notification!.title ?? '';
    final body = msg.notification!.body ?? '';
    final slotTime = msg.data['slotTime'] ?? '';
    final slotDate = msg.data['slotDate'] ?? '';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      backgroundColor:
          isReminder ? const Color(0xFF1e3c72) : Colors.blueAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(
        children: [
          Icon(isReminder ? Icons.alarm : Icons.notifications,
              color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text(
                  isReminder && slotTime.isNotEmpty
                      ? '$slotTime${slotDate.isNotEmpty ? ' · $slotDate' : ''}'
                      : body,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (isReminder)
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MySchedulePage()));
              },
              child: const Text('VIEW',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
        ],
      ),
    ));
  }

  // ── data loading ──────────────────────────────────────────────────────────

  Future<void> _fetchUserProfile() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Not authenticated';
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        firstName = (data['name'] as String? ?? '').split(' ').first;
        firestorePhotoUrl = data['profileImage'] as String?;
        localImageFile = null;
        _tabDisabledStatus = _parseDisabledTabs(data);
      });
    } catch (e) {
      if (mounted) setState(() => errorMessage = 'Error loading profile: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _setupProfileListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _profileListener?.cancel();
    _profileListener = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      setState(() {
        firestorePhotoUrl = data['profileImage'] as String?;
        _tabDisabledStatus = _parseDisabledTabs(data);
      });
    });
  }

  Map<String, bool> _parseDisabledTabs(Map<String, dynamic> data) {
    final disabled = List<String>.from(data['disabledTabs'] ?? []);
    return {
      'schedule': disabled.contains('schedule'),
      'booking': disabled.contains('booking'),
      'plans': disabled.contains('plans'),
      'workouts': disabled.contains('workouts'),
      'profile': disabled.contains('profile'),
      'announcements': disabled.contains('announcements'),
    };
  }

  void _setupSessionsListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _sessionsSubscription?.cancel();
    _sessionsSubscription = FirebaseFirestore.instance
        .collection('trainer_slots')
        .where('booked_by', arrayContains: uid)
        .snapshots()
        .listen((snap) {
      final now = DateTime.now();
      int completed = 0;
      final upcoming = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['date'] is! Timestamp) continue;
        final date = (d['date'] as Timestamp).toDate().toLocal();
        if (date.isBefore(now)) {
          completed++;
        } else {
          upcoming
              .add({'date': date, 'time': d['time'] as String? ?? ''});
        }
      }
      String? nextInfo;
      if (upcoming.isNotEmpty) {
        upcoming.sort((a, b) =>
            (a['date'] as DateTime).compareTo(b['date'] as DateTime));
        final next = upcoming.first;
        nextInfo =
            '${_fmtDate(next['date'] as DateTime)} – ${next['time']}';
      }
      if (mounted) {
        setState(() {
          completedSessions = completed;
          nextUpcomingSessionTime =
              nextInfo ?? 'No upcoming sessions';
        });
      }
    });
  }

  String _fmtDate(DateTime dt) {
    const m = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // ── profile image ─────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final file = File(picked.path);
    setState(() => localImageFile = file);
    await _uploadProfileImage(file);
    await _fetchUserProfile();
  }

  Future<void> _uploadProfileImage(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images/${user.uid}.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'profileImage': url});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload image')),
        );
      }
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    ImageProvider avatarImage;
    if (localImageFile != null) {
      avatarImage = FileImage(localImageFile!);
    } else if (firestorePhotoUrl != null &&
        firestorePhotoUrl!.isNotEmpty) {
      avatarImage = NetworkImage(firestorePhotoUrl!);
    } else {
      avatarImage =
          const AssetImage('assets/images/flex_login/logo.png');
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      // ── Chat FAB with unread badge ───────────────────────────────────────
      floatingActionButton: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('conversations')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) {
          final unread = snap.hasData && snap.data!.exists
              ? ((snap.data!.data()
                          as Map<String, dynamic>?)?['unreadClient']
                      as int? ??
                  0)
              : 0;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              FloatingActionButton(
                heroTag: 'chat_fab',
                backgroundColor: _navy,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      clientId: uid,
                      clientName: firstName,
                      isAdmin: false,
                    ),
                  ),
                ),
                child: const Icon(Icons.chat_bubble_outline,
                    color: Colors.white),
              ),
              if (unread > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Text('$unread',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          );
        },
      ),
      body: RefreshIndicator(
        onRefresh: _fetchUserProfile,
        child: CustomScrollView(
          slivers: [
            // ── App bar ────────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              stretch: true,
              backgroundColor: _navy,
              expandedHeight: 240,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Padding(
                  padding: const EdgeInsets.only(
                      top: 80, left: 16, right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dashboard',
                        style:
                            theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 32,
                        ),
                      ),
                      const SizedBox(height: 32),
                      isLoading
                          ? Row(children: const [
                              ShimmerBox(
                                  width: 72,
                                  height: 72,
                                  borderRadius: BorderRadius.all(
                                      Radius.circular(36))),
                              SizedBox(width: 16),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  ShimmerBox(width: 100, height: 14),
                                  SizedBox(height: 8),
                                  ShimmerBox(width: 140, height: 24),
                                ],
                              ),
                            ])
                          : Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.center,
                              children: [
                                Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 36,
                                      backgroundColor: Colors.white24,
                                      backgroundImage: avatarImage,
                                      onBackgroundImageError:
                                          (_, __) => setState(() =>
                                              firestorePhotoUrl = null),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: _pickImage,
                                        child: Container(
                                          decoration:
                                              const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          padding:
                                              const EdgeInsets.all(4),
                                          child: const Icon(Icons.edit,
                                              size: 20,
                                              color: Colors.black54),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Welcome back,',
                                        style: theme
                                            .textTheme.titleMedium
                                            ?.copyWith(
                                          color: Colors.white70,
                                          fontSize: 16,
                                        )),
                                    Text(
                                      firstName.isEmpty
                                          ? '...'
                                          : firstName,
                                      style: theme
                                          .textTheme.headlineMedium
                                          ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 28,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Stats + upcoming ───────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              sliver: SliverToBoxAdapter(
                child: isLoading
                    ? const Column(children: [
                        DashboardStatShimmer(),
                        SizedBox(height: 12),
                        UpcomingSessionShimmer(),
                      ])
                    : errorMessage != null
                        ? _buildErrorCard()
                        : Column(children: [
                            _buildStatsRow(),
                            const SizedBox(height: 12),
                            _buildUpcomingBar(),
                          ]),
              ),
            ),

            // ── 6-item action grid ─────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser?.uid)
                    .snapshots(),
                builder: (context, snap) {
                  final hasNew = snap.hasData &&
                      snap.data!.data()?['hasNewWorkout'] == true;

                  final items = [
                    DashboardItem(
                      icon: Icons.schedule,
                      label: 'My Schedule',
                      color: Colors.blue,
                      targetScreen: const MySchedulePage(),
                      enabled:
                          !(_tabDisabledStatus['schedule'] ?? false),
                    ),
                    DashboardItem(
                      icon: Icons.date_range,
                      label: 'Book Session',
                      color: Colors.purple,
                      targetScreen: const ClientBookSlot(),
                      enabled:
                          !(_tabDisabledStatus['booking'] ?? false),
                    ),
                    DashboardItem(
                      icon: FontAwesomeIcons.dollarSign,
                      label: 'Plans',
                      color: Colors.green,
                      targetScreen: const ClientPlansScreen(),
                      enabled:
                          !(_tabDisabledStatus['plans'] ?? false),
                    ),
                    DashboardItem(
                      icon: FontAwesomeIcons.dumbbell,
                      label: 'Workouts',
                      color: Colors.orange,
                      showBadge: hasNew,
                      enabled:
                          !(_tabDisabledStatus['workouts'] ?? false),
                      action: () async {
                        Navigator.pushNamed(context, '/clientWorkout');
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(FirebaseAuth
                                .instance.currentUser!.uid)
                            .update({'hasNewWorkout': false});
                      },
                    ),
                    DashboardItem(
                      icon: Icons.person,
                      label: 'Profile',
                      color: Colors.red,
                      targetScreen: const ProfileScreen(),
                      enabled:
                          !(_tabDisabledStatus['profile'] ?? false),
                    ),
                    DashboardItem(
                      icon: Icons.announcement,
                      label: 'Announcements',
                      color: Colors.teal,
                      targetScreen: const PostAnnouncementScreen(),
                      enabled: !(_tabDisabledStatus['announcements'] ??
                          false),
                    ),
                  ];

                  return SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.2,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _actionCard(items[i]),
                      childCount: items.length,
                    ),
                  );
                },
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  // ── error card ─────────────────────────────────────────────────────────────

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
              child: Text(errorMessage!,
                  style: const TextStyle(color: Colors.red))),
          TextButton(
              onPressed: _fetchUserProfile,
              child: const Text('Retry')),
        ],
      ),
    );
  }

  // ── stats row ──────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.fitness_center,
            gradient: const LinearGradient(
              colors: [Color(0xFF2E8B57), Color(0xFF228B22)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('client_purchases')
                  .where('userId',
                      isEqualTo:
                          FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return _statContent('—', 'ACTIVE PLANS',
                      textColor: Colors.white);
                }
                int count = 0;
                for (final doc in snap.data!.docs) {
                  final d = doc.data() as Map<String, dynamic>;
                  if ((d['isActive'] as bool? ?? false) &&
                      (d['remainingSessions'] as int? ?? 0) > 0 &&
                      (d['status'] as String? ?? '') != 'cancelled') {
                    count++;
                  }
                }
                return _statContent('$count', 'ACTIVE PLANS',
                    textColor: Colors.white);
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            icon: Icons.star,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: _statContent('$completedSessions', 'COMPLETED',
                textColor: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Gradient gradient,
    required Widget child,
  }) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            right: 4,
            child: Icon(icon,
                size: 32, color: Colors.white.withOpacity(0.2)),
          ),
          Center(child: child),
        ],
      ),
    );
  }

  Widget _statContent(String value, String label,
      {required Color textColor}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: textColor)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
      ],
    );
  }

  // ── upcoming session bar ───────────────────────────────────────────────────

  Widget _buildUpcomingBar() {
    return Container(
      width: double.infinity,
      height: 110,
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1e3c72), Color(0xFF2a5298)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('UPCOMING SESSION',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    nextUpcomingSessionTime ?? 'No upcoming session',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.calendar_today,
              size: 32, color: Colors.white.withOpacity(0.3)),
        ],
      ),
    );
  }

  // ── action card ────────────────────────────────────────────────────────────

  Widget _actionCard(DashboardItem item) {
    return Card(
      elevation: item.enabled ? 4 : 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: item.enabled ? null : Colors.grey[200],
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.enabled
            ? () {
                HapticFeedback.mediumImpact();
                if (item.targetScreen != null) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => item.targetScreen!));
                } else {
                  item.action?.call();
                }
              }
            : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: item.enabled
                ? LinearGradient(
                    colors: [
                      item.color.withOpacity(0.15),
                      item.color.withOpacity(0.05),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : null,
          ),
          child: Opacity(
            opacity: item.enabled ? 1.0 : 0.5,
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(item.icon,
                      size: 40,
                      color: item.color.withOpacity(
                          item.enabled ? 0.15 : 0.05)),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon,
                        color: item.enabled
                            ? item.color
                            : Colors.grey,
                        size: 28),
                    const SizedBox(height: 12),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: item.enabled ? null : Colors.grey[600],
                      ),
                    ),
                    if (!item.enabled)
                      const Text('Disabled by admin',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold)),
                  ],
                ),
                if (item.showBadge && item.enabled)
                  const Positioned(
                    top: 8,
                    left: 8,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.red,
                      child: Text('!',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
