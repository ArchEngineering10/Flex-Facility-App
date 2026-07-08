# Hybrid Workout Lifecycle Implementation Guide

## Overview
This document describes the new hybrid workout lifecycle management system that combines **date-based automatic expiration** with **admin-controlled manual management**.

---

## Architecture

### Three Key Components

#### 1. **WorkoutAssignment Model** (`lib/models/workout_assignment.dart`)
Represents a single workout assignment to a client with lifecycle information.

**Key Fields:**
- `clientId` & `clientName` - Who the workout is assigned to
- `workoutId` & `workoutName` - Which workout (standard or custom)
- `workoutType` - 'standard' or 'custom'
- `startDate` - When workout becomes available
- `endDate` - When workout automatically expires
- `status` - AssignmentStatus (active/expired/archived/deassigned)
- `daysRemaining` - Computed property for countdown
- `isExpired` - Computed property checking if past end date
- `isActive` - Computed property (status is active AND not expired)

**Database Structure:**
```firestore
workout_assignments/
├── {assignmentId}
│   ├── clientId: string
│   ├── clientName: string
│   ├── workoutId: string
│   ├── workoutName: string
│   ├── workoutType: 'standard' | 'custom'
│   ├── startDate: timestamp
│   ├── endDate: timestamp
│   ├── assignedAt: timestamp
│   ├── status: 'active' | 'expired' | 'archived' | 'deassigned'
│   └── adminId: string
```

#### 2. **AdminWorkoutAssignmentScreen** (`lib/screens/admin_workout_assignment_screen.dart`)
Full admin interface for managing workout assignments.

**Features:**
- ✅ **View All Assignments** - See all assignments with filtering
- ✅ **Filter by Status** - Active, Expired, Archived
- ✅ **Create New Assignment** - Assign workout to client with date range
- ✅ **Extend End Date** - Modify end date for active workouts
- ✅ **Archive Manually** - Move workout to archive (keeps history)
- ✅ **Deassign Completely** - Remove workout from client (no longer visible)

**UI Components:**
- Filter chips (All, Active, Expired, Archived)
- Assignment cards with:
  - Status badge (color-coded)
  - Days remaining countdown
  - Start/End dates
  - Action buttons (Extend, Archive, Deassign)
- New Assignment dialog with:
  - Client dropdown
  - Workout dropdown
  - Start date picker
  - End date picker

#### 3. **ClientWorkoutScreenV2** (`lib/screens/client_workout_screen_v2.dart`)
Updated client screen showing active and archived workouts.

**Features:**
- 📱 **Two Tab View:**
  - **Active Tab** - Shows all active workouts with countdown
  - **Archive Tab** - Shows archived/expired workouts (view-only)
- ✅ **Countdown Badge** - Shows "X days left" for active workouts
- ✅ **Expiration Date Display** - Shows when workout expires
- ✅ **Exercise Details** - Full exercise list with media
- ✅ **Status Indicators** - Visual badges for status

**UI Features:**
- Color-coded status badges
- Day countdown for active workouts
- Expiration date warnings
- Expandable workout cards
- Exercise guide/demo video buttons

---

## Workflow

### Admin Flow

**1. Assign New Workout**
```
Admin clicks "New Assignment"
  ↓
Selects Client, Workout, Start Date, End Date
  ↓
Workout saved with status="active"
  ↓
Client sees workout immediately (if start date is today)
```

**2. Extend Workout (While Active)**
```
Admin clicks "Extend" on assignment
  ↓
Admin selects new end date
  ↓
End date updated in database
  ↓
Client countdown updates automatically
```

**3. Archive Workout (Manual)**
```
Admin clicks "Archive"
  ↓
Status changes to "archived"
  ↓
Workout moves to client's Archive tab
  ↓
Client can view history but can't complete
```

**4. Deassign Workout (Complete Removal)**
```
Admin clicks "Deassign"
  ↓
Status changes to "deassigned"
  ↓
Workout completely hidden from client
  ↓
No trace in client app
```

### Client Flow

**Active Workouts Tab:**
```
View → Read details → Expand → See exercises → View guides/videos
```

**Archived Workouts Tab:**
```
View past workouts → Expand to see details → View for reference only
```

**Automatic Expiration:**
```
Workout on Active tab
  ↓
End date reached
  ↓
Moves to Archived tab automatically
  ↓
Client notified via status change
```

---

## Integration Steps

### Step 1: Create Firestore Collection
The `workout_assignments` collection is automatically created on first write.

### Step 2: Update Navigation
Add `AdminWorkoutAssignmentScreen` to admin navigation:

```dart
// In admin dashboard or navigation
GestureDetector(
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const AdminWorkoutAssignmentScreen(),
    ),
  ),
  child: Card(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.assignment, size: 48, color: Color(0xFF1C2D5E)),
        SizedBox(height: 8),
        Text('Manage Assignments'),
      ],
    ),
  ),
)
```

### Step 3: Replace Client Workout Screen
Update client navigation to use `ClientWorkoutScreenV2`:

```dart
// In client navigation
ClientWorkoutScreenV2()  // Instead of ClientWorkoutScreen
```

### Step 4: Keep Legacy Support (Optional)
If you need to keep existing workouts visible during transition:

```dart
// In a service class
Future<void> migrateExistingWorkouts() async {
  // Query old workouts from users/{uid}/workouts
  // Create assignments with:
  // - startDate = now
  // - endDate = now + 90 days
  // - status = 'active'
}
```

---

## Database Queries

### Get Active Workouts for Client
```dart
FirebaseFirestore.instance
    .collection('workout_assignments')
    .where('clientId', isEqualTo: userId)
    .where('status', isEqualTo: 'active')
    .orderBy('assignedAt', descending: true)
    .snapshots();
```

### Get Archived Workouts for Client
```dart
FirebaseFirestore.instance
    .collection('workout_assignments')
    .where('clientId', isEqualTo: userId)
    .where('status', whereIn: ['archived', 'expired'])
    .orderBy('assignedAt', descending: true)
    .snapshots();
```

### Get All Assignments (Admin)
```dart
FirebaseFirestore.instance
    .collection('workout_assignments')
    .orderBy('assignedAt', descending: true)
    .snapshots();
```

### Get Assignments by Status
```dart
FirebaseFirestore.instance
    .collection('workout_assignments')
    .where('status', isEqualTo: 'active')  // or 'expired', 'archived', 'deassigned'
    .orderBy('assignedAt', descending: true)
    .snapshots();
```

---

## Status Lifecycle

### Status Transitions

```
        ┌─────────────┐
        │   ACTIVE    │ ← Initial state
        └──────┬──────┘
               │
        ┌──────┴──────────┐
        │                 │
        ↓                 ↓
   [End Date]       [Admin Action]
        │                 │
        ↓                 ↓
    EXPIRED      ┌────────┴─────────┐
        │        │                  │
        │        ↓                  ↓
        │     ARCHIVED          DEASSIGNED
        │        │                  │
        └────────┴──────────────────┘
                  ↓
          [Hidden from client]
```

### Status Meanings

| Status | Visibility | Editable | Auto-Trigger | Notes |
|--------|-----------|----------|-------------|-------|
| **active** | Active tab | Yes | Start date reached | Normal workout |
| **expired** | Archive tab | No | End date reached | Auto-moved from active |
| **archived** | Archive tab | No | Admin action | Manual archival by admin |
| **deassigned** | Hidden | No | Admin action | Completely removed |

---

## UI/UX Details

### Admin Assignment Card

**Active Assignment:**
```
┌─────────────────────────────────────┐
│ ✓ ACTIVE                             │
│ John Doe | Chest Day                 │
│ Start: Jun 1, 2026 | End: Jun 30, 26 │
│ 5 days left                           │
│ [Extend] [Archive] [Deassign]        │
└─────────────────────────────────────┘
```

**Expired Assignment:**
```
┌─────────────────────────────────────┐
│ ⏱ EXPIRED                            │
│ John Doe | Chest Day                 │
│ Start: Jun 1, 2026 | End: Jun 30, 26 │
│ [Archive] [Deassign]                 │
└─────────────────────────────────────┘
```

### Client Workout Card

**Active:**
```
┌────────────────────────────────────┐
│ 1  Chest Day      [5 days left]    │
│    Assigned: Jun 1  Expires: Jun 30 │
│    ▼ (expand icon)                  │
└────────────────────────────────────┘
```

**Archived:**
```
┌────────────────────────────────────┐
│ 2  Chest Day      [Archived]       │
│    Assigned: Jun 1  Expired: Jun 30 │
│    ▼ (expand icon)                  │
└────────────────────────────────────┘
```

---

## Key Features

### ✅ Automatic Expiration
- No admin work needed
- Clients see clear end date
- Auto-moves to archive on end date

### ✅ Admin Control
- Extend dates anytime
- Manually archive for cleanup
- Deassign for complete removal

### ✅ History Preservation
- Archive keeps workout history
- Clients can review past workouts
- Admin can extend if needed

### ✅ Professional UI
- Color-coded status badges
- Day countdown for active workouts
- Clear tab separation (Active/Archive)
- Responsive design

### ✅ Scalability
- Efficient Firestore queries
- Indexed by status and clientId
- No manual cleanup needed
- Automatic state management

---

## Firestore Indexing

Create a composite index for optimal performance:

**Collection:** `workout_assignments`

**Index Fields:**
1. `clientId` (Ascending)
2. `status` (Ascending)
3. `assignedAt` (Descending)

Firestore will prompt you to create this index on first query.

---

## Future Enhancements

### Potential Features
- ✨ Bulk assignment (assign workout to multiple clients)
- ✨ Recurring workouts (weekly/monthly)
- ✨ Workout templates
- ✨ Admin notifications for expiring workouts
- ✨ Client notifications before expiration
- ✨ Workout completion tracking
- ✨ Analytics (who completed workouts)

---

## Migration Checklist

- [ ] Create models (workout_assignment.dart)
- [ ] Create admin screen (admin_workout_assignment_screen.dart)
- [ ] Create client screen (client_workout_screen_v2.dart)
- [ ] Add to navigation
- [ ] Test assignment creation
- [ ] Test date filters
- [ ] Test archive/deassign actions
- [ ] Test client view (active/archived)
- [ ] Create Firestore index
- [ ] Test with multiple users
- [ ] Verify expiration auto-transition

---

## Support

For issues or questions, refer to:
- **Model Logic:** `lib/models/workout_assignment.dart`
- **Admin UI:** `lib/screens/admin_workout_assignment_screen.dart`
- **Client UI:** `lib/screens/client_workout_screen_v2.dart`

