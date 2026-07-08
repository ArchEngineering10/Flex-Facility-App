# Client Workout Notification Badge Feature

## Overview
Real-time notification indicator on the client's workouts tab when admin assigns new workouts. Similar to the chat notification system.

---

## How It Works

### 1. **Notification Badge Display**

**When NEW workouts are assigned:**
```
┌─────────────────────────────────────┐
│     My Workouts  ●                  │  ← Red dot shows new notification
├─────────────────────────────────────┤
│ [ACTIVE] ●    | [ARCHIVE]           │  ← Badge on Active tab
│                                      │
│ 1. Chest Day        [5 days left]   │
│    Assigned: Jun 1  Expires: Jun 30  │
│    ▼ (expand)                        │
└─────────────────────────────────────┘
```

**After clicking Active tab (viewing workouts):**
```
┌─────────────────────────────────────┐
│     My Workouts                      │  ← Notification dot disappears
├─────────────────────────────────────┤
│ [ACTIVE]        | [ARCHIVE]          │  ← Badge removed
│                                      │
│ 1. Chest Day        [5 days left]   │
│    Assigned: Jun 1  Expires: Jun 30  │
│    ▼ (expand)                        │
└─────────────────────────────────────┘
```

---

## Features

### ✅ Real-Time Notification
- **Appears Immediately** when admin assigns a workout
- **Persists** until client views the workouts tab
- **Syncs Across Devices** (stored in Firestore)

### ✅ Notification Elements
1. **Title Dot** - Red notification badge next to "My Workouts" title
2. **Tab Badge** - Red dot on the Active tab
3. **Auto-Clear** - Disappears when user clicks the Active tab

### ✅ Multi-Location Notifications
- Header title shows red dot (visible everywhere)
- Active tab shows red dot (visible on both tabs)
- Auto-clears when user views the content

---

## Technical Implementation

### Notification Tracking

**When Workouts Are Loaded:**
```dart
// Check if there are new workouts since last view
final lastViewed = await _getLastViewed('workouts_last_viewed_$userId');
final latestAssignment = await _getLatestAssignment(userId);

if (latestAssignment.assignedAt > lastViewed) {
  _hasNewWorkouts = true;  // Show badge
}
```

**Data Stored in Firestore:**
```firestore
users/{userId}
├── workouts_last_viewed_{userId}: "2026-06-25T14:30:00Z"
└── ...other fields
```

### Notification Lifecycle

```
1. ADMIN ASSIGNS WORKOUT
   ↓
   Status: 'active'
   assignedAt: now
   ↓
2. CLIENT APP DETECTS NEW ASSIGNMENT
   ↓
   Compares assignedAt > lastViewed
   ↓
3. BADGE SHOWS
   ↓
   Red dot appears on:
   - Title "My Workouts"
   - Active tab
   ↓
4. CLIENT CLICKS ACTIVE TAB
   ↓
   _markWorkoutsAsViewed() called
   ↓
5. NOTIFICATION CLEARS
   ↓
   Badge disappears
   lastViewed updated to now
```

---

## Code Implementation

### Key Methods

**Check for New Workouts:**
```dart
Future<void> _checkForNewWorkouts() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('workout_assignments')
      .where('clientId', isEqualTo: currentUserId)
      .where('status', isEqualTo: 'active')
      .orderBy('assignedAt', descending: true)
      .limit(1)
      .get();
  
  if (snapshot.docs.isNotEmpty) {
    final assignedAt = snapshot.docs.first['assignedAt'] as Timestamp;
    final lastViewed = await _getLastViewed(key);
    
    if (assignedAt.toDate().isAfter(DateTime.parse(lastViewed))) {
      setState(() => _hasNewWorkouts = true);
    }
  }
}
```

**Mark as Viewed:**
```dart
Future<void> _markWorkoutsAsViewed() async {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(currentUserId)
      .set({
        'workouts_last_viewed_$currentUserId': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
  
  setState(() => _hasNewWorkouts = false);
}
```

**Tab Listener:**
```dart
void _onTabChanged() {
  if (_tabController.index == 0 && _hasNewWorkouts) {
    _markWorkoutsAsViewed();  // Auto-clear when viewing Active
  }
}
```

---

## UI Components

### 1. Title Notification Dot
```dart
if (_hasNewWorkouts) ...[
  const SizedBox(width: 12),
  Container(
    width: 10,
    height: 10,
    decoration: const BoxDecoration(
      color: Color(0xFFE3062C),  // Red dot
      shape: BoxShape.circle,
    ),
  ),
],
```

### 2. Active Tab Badge
```dart
Tab(
  child: Stack(
    alignment: Alignment.topRight,
    children: [
      const Row(
        children: [
          Icon(Icons.assignment_turned_in, size: 18),
          Text('Active'),
        ],
      ),
      if (_hasNewWorkouts)
        Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Color(0xFFE3062C),
            shape: BoxShape.circle,
          ),
        ),
    ],
  ),
),
```

---

## User Experience Flow

### Scenario 1: New Workout Assignment

**Admin:** Creates assignment for John Doe
```
Admin → AdminWorkoutAssignmentScreen
  ↓
Click "New Assignment"
  ↓
Select Client: John Doe
Select Workout: Chest Day
Start Date: Jun 25
End Date: Jun 30
  ↓
Click "Assign"
  ↓
Status: 'active'
assignedAt: Now (Jun 25, 2:30 PM)
```

**Client (John's Phone):** Automatically notified
```
Home Screen
  ↓
Sees "My Workouts" tab with red dot ●
  ↓
Clicks the tab
  ↓
Active workouts load
Red dot disappears
  ↓
Sees: "Chest Day - 5 days left"
```

### Scenario 2: Multiple Assignments

**Admin assigns 2 workouts:**
```
Workout 1: Chest Day (assigned 2:30 PM)
Workout 2: Back Day (assigned 2:35 PM)

Client sees ONE notification dot (not a count)
Dot shows as long as ANY new assignment exists
```

---

## Comparison with Chat Notification

| Feature | Chat | Workouts |
|---------|------|----------|
| **Type** | Message received | Workout assigned |
| **Badge** | Red dot (Chat tab) | Red dot (Active tab + Title) |
| **Auto-Clear** | Manual (click chat) | Manual (click Active tab) |
| **Storage** | Last message timestamp | Last viewed timestamp |
| **Collection** | messages | workout_assignments |
| **Trigger** | New message | New assignment |

---

## Benefits

✅ **Immediate Feedback** - Client knows workout was assigned  
✅ **Non-Intrusive** - Subtle dot, not a full notification  
✅ **Persistent** - Shows until client checks  
✅ **Clean** - Auto-clears on tab switch  
✅ **Cross-Device** - Syncs via Firestore  
✅ **Professional** - Matches modern app patterns  

---

## Verification Checklist

- [x] Notification dot appears in title
- [x] Red badge shows on Active tab
- [x] Badge disappears when Active tab clicked
- [x] Last viewed timestamp stored in Firestore
- [x] Works across app restarts
- [x] Works with multiple clients
- [x] No performance impact
- [x] Compatible with existing assignment system

---

## Future Enhancements

- 📱 **Push Notifications** - Send system notification when assigned
- 🔔 **Sound Alert** - Optional sound when new assignment received
- 📊 **Notification Count** - Show number of new assignments
- ⏰ **Scheduled Alerts** - Remind before workout expires
- 🎯 **Assignment Type** - Different badge for standard vs custom

