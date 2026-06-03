import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// WorkoutRatingDialog — shown when client taps "Rate this" on a workout card
// ---------------------------------------------------------------------------

class WorkoutRatingDialog extends StatefulWidget {
  final String workoutId;
  final String workoutType; // 'pdf' | 'video'
  final String workoutName;

  const WorkoutRatingDialog({
    super.key,
    required this.workoutId,
    required this.workoutType,
    required this.workoutName,
  });

  static Future<void> show(
    BuildContext context, {
    required String workoutId,
    required String workoutType,
    required String workoutName,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkoutRatingDialog(
        workoutId: workoutId,
        workoutType: workoutType,
        workoutName: workoutName,
      ),
    );
  }

  @override
  State<WorkoutRatingDialog> createState() => _WorkoutRatingDialogState();
}

class _WorkoutRatingDialogState extends State<WorkoutRatingDialog> {
  int _stars = 0;
  final _noteCtrl = TextEditingController();
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _alreadyRated = false;

  static const Color _navy = Color(0xFF1C2D5E);

  String get _docId =>
      '${widget.workoutType}_${widget.workoutId}_${FirebaseAuth.instance.currentUser?.uid}';

  @override
  void initState() {
    super.initState();
    _loadExistingRating();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingRating() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workout_ratings')
          .doc(_docId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _stars = (data['stars'] as int? ?? 0);
          _noteCtrl.text = data['note'] as String? ?? '';
          _alreadyRated = true;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a star rating first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userName =
          userDoc.data()?['name'] as String? ?? user.email ?? 'Client';

      final ratingData = {
        'workoutId': widget.workoutId,
        'workoutType': widget.workoutType,
        'workoutName': widget.workoutName,
        'userId': user.uid,
        'userName': userName,
        'stars': _stars,
        'note': _noteCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!_alreadyRated) {
        ratingData['createdAt'] = FieldValue.serverTimestamp();
      }

      // Save individual rating
      await FirebaseFirestore.instance
          .collection('workout_ratings')
          .doc(_docId)
          .set(ratingData, SetOptions(merge: true));

      // Recalculate and update average on the workout document
      await _updateWorkoutAverage();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_alreadyRated
              ? 'Rating updated! Thank you.'
              : 'Thanks for your feedback!'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save rating: $e'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _updateWorkoutAverage() async {
    final allRatings = await FirebaseFirestore.instance
        .collection('workout_ratings')
        .where('workoutId', isEqualTo: widget.workoutId)
        .where('workoutType', isEqualTo: widget.workoutType)
        .get();

    if (allRatings.docs.isEmpty) return;

    final total = allRatings.docs.fold<int>(
        0, (sum, d) => sum + ((d.data()['stars'] as int?) ?? 0));
    final avg = total / allRatings.docs.length;
    final count = allRatings.docs.length;

    final collection = widget.workoutType == 'pdf'
        ? 'pdf_workouts'
        : 'video_workouts';

    await FirebaseFirestore.instance
        .collection(collection)
        .doc(widget.workoutId)
        .set(
          {'averageRating': avg, 'ratingCount': count},
          SetOptions(merge: true),
        );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _alreadyRated ? 'Update Your Rating' : 'Rate This Workout',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: _navy),
          ),
          const SizedBox(height: 4),
          Text(
            widget.workoutName,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                // Star row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = i < _stars;
                    return GestureDetector(
                      onTap: () => setState(() => _stars = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          filled ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 38,
                          color: filled ? Colors.amber : Colors.grey[400],
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  _starLabel(_stars),
                  style: TextStyle(
                      color: _stars > 0 ? Colors.amber[700] : Colors.grey,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  maxLength: 120,
                  decoration: InputDecoration(
                    hintText: 'Add a note (optional)',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _navy, width: 2),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    counterStyle: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
        ),
        ElevatedButton(
          onPressed: _isSubmitting || _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _navy,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(
                  _alreadyRated ? 'Update' : 'Submit',
                  style: const TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }

  String _starLabel(int stars) {
    switch (stars) {
      case 1: return 'Not helpful';
      case 2: return 'Could be better';
      case 3: return 'It\'s okay';
      case 4: return 'Really good!';
      case 5: return 'Excellent! 🔥';
      default: return 'Tap a star to rate';
    }
  }
}

// ---------------------------------------------------------------------------
// WorkoutRatingBadge — small inline widget showing average rating on a card
// ---------------------------------------------------------------------------

class WorkoutRatingBadge extends StatelessWidget {
  final String workoutId;
  final String workoutType;
  final double? cachedAverage;
  final int? cachedCount;

  const WorkoutRatingBadge({
    super.key,
    required this.workoutId,
    required this.workoutType,
    this.cachedAverage,
    this.cachedCount,
  });

  @override
  Widget build(BuildContext context) {
    // Use cached values from the workout document if available
    if (cachedAverage != null && cachedCount != null && cachedCount! > 0) {
      return _badge(cachedAverage!, cachedCount!);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('workout_ratings')
          .where('workoutId', isEqualTo: workoutId)
          .where('workoutType', isEqualTo: workoutType)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final docs = snap.data!.docs;
        final total = docs.fold<int>(
            0, (s, d) => s + ((d.data() as Map)['stars'] as int? ?? 0));
        final avg = total / docs.length;
        return _badge(avg, docs.length);
      },
    );
  }

  Widget _badge(double avg, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
        const SizedBox(width: 2),
        Text(
          '${avg.toStringAsFixed(1)} ($count)',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SessionRatingSheet — bottom sheet triggered by FCM after session ends
// ---------------------------------------------------------------------------

class SessionRatingSheet extends StatefulWidget {
  final String slotId;
  final String slotTime;
  final String slotDate;

  const SessionRatingSheet({
    super.key,
    required this.slotId,
    required this.slotTime,
    required this.slotDate,
  });

  static Future<void> show(
    BuildContext context, {
    required String slotId,
    required String slotTime,
    required String slotDate,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SessionRatingSheet(
        slotId: slotId,
        slotTime: slotTime,
        slotDate: slotDate,
      ),
    );
  }

  @override
  State<SessionRatingSheet> createState() => _SessionRatingSheetState();
}

class _SessionRatingSheetState extends State<SessionRatingSheet> {
  int _stars = 0;
  final _noteCtrl = TextEditingController();
  bool _isSubmitting = false;

  static const Color _navy = Color(0xFF1C2D5E);

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a star rating.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userName =
          userDoc.data()?['name'] as String? ?? user.email ?? 'Client';

      // Save to session_ratings collection
      await FirebaseFirestore.instance.collection('session_ratings').add({
        'slotId': widget.slotId,
        'userId': user.uid,
        'userName': userName,
        'stars': _stars,
        'note': _noteCtrl.text.trim(),
        'slotTime': widget.slotTime,
        'slotDate': widget.slotDate,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update slot doc with this user's rating
      await FirebaseFirestore.instance
          .collection('trainer_slots')
          .doc(widget.slotId)
          .set({
        'ratings': {user.uid: _stars},
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Thanks for your feedback! 🙌'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'How was your session?',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: _navy),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.slotDate} · ${widget.slotTime}',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _stars;
              return GestureDetector(
                onTap: () => setState(() => _stars = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 44,
                    color: filled ? Colors.amber : Colors.grey[400],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _starLabel(_stars),
            style: TextStyle(
                color: _stars > 0 ? Colors.amber[700] : Colors.grey,
                fontWeight: FontWeight.w600,
                fontSize: 14),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            maxLength: 120,
            decoration: InputDecoration(
              hintText: 'Any feedback for Kenny? (optional)',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _navy, width: 2),
              ),
              contentPadding: const EdgeInsets.all(14),
              counterStyle: const TextStyle(fontSize: 10),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Rating',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Skip', style: TextStyle(color: Colors.grey[500])),
          ),
        ],
      ),
    );
  }

  String _starLabel(int stars) {
    switch (stars) {
      case 1: return 'Needs improvement';
      case 2: return 'Below expectations';
      case 3: return 'Good session';
      case 4: return 'Great session!';
      case 5: return 'Amazing! Best session yet 🔥';
      default: return 'Tap a star to rate';
    }
  }
}
