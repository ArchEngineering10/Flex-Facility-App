import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

// Upload state tracking for multiple concurrent uploads
class VideoUploadState {
  final String uploadId;
  String workoutName;
  double progress = 0.0;
  String message = '';
  bool isUploading = false;
  bool isComplete = false;
  bool hasError = false;
  String? errorMessage;

  VideoUploadState({
    required this.uploadId,
    required this.workoutName,
  });
}

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  _PlansScreenState createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _sessionsController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  
  // PDF Workouts controllers
  final _pdfNameController = TextEditingController();
  final _pdfDescriptionController = TextEditingController();

  // Video Workouts controllers
  final _videoNameController = TextEditingController();
  final _videoDescriptionController = TextEditingController();
  final _videoCategoryController = TextEditingController();

  String _selectedVideoCategory = 'Strength';
  String _selectedVideoDifficulty = 'Beginner';
  PlatformFile? _selectedVideoThumbnail;
  PlatformFile? _selectedVideoFile;
  bool _existingVideoFile = false;
  bool _existingVideoThumbnail = false;

  // Multi-upload support
  Map<String, VideoUploadState> _uploadStates = {};

  List<String> _videoCategories = ['Strength', 'Cardio', 'Yoga', 'HIIT', 'Mobility'];
  final List<String> _videoDifficulties = ['Beginner', 'Intermediate', 'Advanced'];

  final Map<String, IconData> _categoryIcons = {
    'Strength': Icons.fitness_center,
    'Cardio': Icons.favorite,
    'Yoga': Icons.self_improvement,
    'HIIT': Icons.local_fire_department,
    'Mobility': Icons.sports_gymnastics,
  };

  final Map<String, IconData> _customCategoryIcons = {};

  String _selectedCategory = 'Semi Private Monthly Plans';
  String _selectedStatus = 'Active';
  int _editingIndex = -1;
  String? _editingDocId;
  List<Map<String, dynamic>> _plans = [];
  
  // PDF Workouts variables
  List<Map<String, dynamic>> _pdfWorkouts = [];
  int _editingPdfIndex = -1;
  String? _editingPdfDocId;
  PlatformFile? _selectedPdfFile;
  bool _isUploading = false;

  // Video Workouts variables
  List<Map<String, dynamic>> _videoWorkouts = [];
  int _editingVideoIndex = -1;
  String? _editingVideoDocId;
  int? _expandedVideoIndex;
  bool _isProcessingVideo = false;

  final List<String> _categories = [
    'Semi Private Monthly Plans',
    'Semi Private Bi Weekly Plans',
    'Semi Private Day Pass',
    'Group Training or Class',
    'Strength & Agility Session (High School Athlete)',
    'Strength & Agility Session (Kids)',
    'Athletic Performance (Adult)',
  ];

  final List<String> _statusOptions = ['Active', 'Inactive'];
  int? _expandedPlanIndex;
  int? _expandedPdfIndex;

  IconData _getRandomIconForCategory(String category) {
    final icons = [
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
    final hashCode = category.hashCode % icons.length;
    return icons[hashCode.abs()];
  }

  Future<void> _saveCustomCategory(String category) async {
    try {
      if (!_videoCategories.contains(category)) {
        _videoCategories.add(category);
        _customCategoryIcons[category] = _getRandomIconForCategory(category);

        // Save to Firestore
        await _firestore.collection('custom_video_categories').doc(category).set({
          'name': category,
          'iconIndex': category.hashCode.abs() % 12,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error saving custom category: $e');
    }
  }

  Future<void> _loadCustomCategories() async {
    try {
      final snapshot = await _firestore.collection('custom_video_categories').get();
      for (var doc in snapshot.docs) {
        final category = doc['name'] as String;
        if (!_videoCategories.contains(category)) {
          _videoCategories.add(category);
        }
        _customCategoryIcons[category] = _getRandomIconForCategory(category);
      }
    } catch (e) {
      print('Error loading custom categories: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialPlans();
    _loadCustomCategories();
  }

  Future<void> _loadInitialPlans() async {
    try {
      List<Map<String, dynamic>> initialPlans = [
        {
          'name': '4 Sessions Monthly',
          'category': 'Semi Private Monthly Plans',
          'sessions': 4,
          'price': 185.0,
          'status': 'Active',
          'description': '4 sessions per month for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '8 Sessions Monthly',
          'category': 'Semi Private Monthly Plans',
          'sessions': 8,
          'price': 375.0,
          'status': 'Active',
          'description': '8 sessions per month for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '12 Sessions Monthly',
          'category': 'Semi Private Monthly Plans',
          'sessions': 12,
          'price': 500.0,
          'status': 'Active',
          'description': '12 sessions per month for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '16 Sessions Monthly',
          'category': 'Semi Private Monthly Plans',
          'sessions': 16,
          'price': 600.0,
          'status': 'Active',
          'description': '16 sessions per month for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '4 Sessions Bi-Weekly',
          'category': 'Semi Private Bi Weekly Plans',
          'sessions': 4,
          'price': 94.0,
          'status': 'Active',
          'description': '4 sessions per month for semi-private bi-weekly training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '8 Sessions Bi-Weekly',
          'category': 'Semi Private Bi Weekly Plans',
          'sessions': 8,
          'price': 187.0,
          'status': 'Active',
          'description': '8 sessions per month for semi-private bi-weekly training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '12 Sessions Bi-Weekly',
          'category': 'Semi Private Bi Weekly Plans',
          'sessions': 12,
          'price': 260.0,
          'status': 'Active',
          'description': '12 sessions per month for semi-private bi-weekly training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': '16 Sessions Bi-Weekly',
          'category': 'Semi Private Bi Weekly Plans',
          'sessions': 16,
          'price': 310.0,
          'status': 'Active',
          'description': '16 sessions per month for semi-private bi-weekly training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Day Pass',
          'category': 'Semi Private Day Pass',
          'sessions': 1,
          'price': 40.0,
          'status': 'Active',
          'description': 'Single day pass for semi-private training',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Group Training',
          'category': 'Group Training or Class',
          'sessions': 1,
          'price': 25.0,
          'status': 'Active',
          'description': 'Single session for group training or class',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'High School Athlete',
          'category': 'Strength & Agility Session (High School Athlete)',
          'sessions': 1,
          'price': 25.0,
          'status': 'Active',
          'description': 'Strength and agility session for high school athletes',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Kids Session',
          'category': 'Strength & Agility Session (Kids)',
          'sessions': 1,
          'price': 25.0,
          'status': 'Active',
          'description': 'Strength and agility session for kids',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Athletic Performance Adult',
          'category': 'Athletic Performance (Adult)',
          'sessions': 1,
          'price': 25.0,
          'status': 'Active',
          'description': 'Athletic performance training for adults',
          'createdAt': FieldValue.serverTimestamp(),
        },
      ];

      final colRef = _firestore.collection('plans');
      final existing = await colRef.get();
      if (existing.docs.isNotEmpty) {
        print('Plans already exist, skipping initial load');
        return;
      }

      WriteBatch batch = _firestore.batch();
      for (var plan in initialPlans) {
        batch.set(colRef.doc(), plan);
      }
      await batch.commit();
      print('Initial plans loaded to Firestore');
    } catch (e) {
      print('Error loading initial plans: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _sessionsController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _pdfNameController.dispose();
    _pdfDescriptionController.dispose();
    _videoNameController.dispose();
    _videoDescriptionController.dispose();
    _videoCategoryController.dispose();
    super.dispose();
  }

  void _clearForm() {
    _nameController.clear();
    _priceController.clear();
    _sessionsController.clear();
    _descriptionController.clear();
    _categoryController.clear();
    _selectedCategory = 'Semi Private Monthly Plans';
    _selectedStatus = 'Active';
    _editingIndex = -1;
    _editingDocId = null;
  }

  void _clearPdfForm() {
    _pdfNameController.clear();
    _pdfDescriptionController.clear();
    // Only clear the selected PDF file when not in editing mode
    if (_editingPdfIndex == -1) {
      _selectedPdfFile = null;
    }
    _editingPdfIndex = -1;
    _editingPdfDocId = null;
    _isUploading = false;
  }

  void _clearVideoForm() {
    _videoNameController.clear();
    _videoDescriptionController.clear();
    _videoCategoryController.clear();
    _selectedVideoCategory = 'Strength';
    _selectedVideoDifficulty = 'Beginner';
    _selectedVideoThumbnail = null;
    _selectedVideoFile = null;
    _existingVideoFile = false;
    _existingVideoThumbnail = false;
    _editingVideoIndex = -1;
    _editingVideoDocId = null;
  }
  Future<void> _showAddCategoryDialog(StateSetter? parentSetState) async {
    _categoryController.clear();
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Add New Category',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF00BCD4),
            ),
          ),
          content: TextFormField(
            controller: _categoryController,
            decoration: const InputDecoration(
              labelText: 'Category Name *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category),
              hintText: 'Enter new category name',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _categoryController.clear();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                String newCategory = _categoryController.text.trim();
                if (newCategory.isNotEmpty && !_categories.contains(newCategory)) {
                  Navigator.of(context).pop(newCategory);
                } else if (newCategory.isEmpty) {
                  _showSnackBar('Please enter a category name');
                } else {
                  _showSnackBar('Category already exists');
                }
              },
              child: const Text('Add Category'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      setState(() {
        _categories.add(result);
        _selectedCategory = result;
      });
      if (parentSetState != null) {
        parentSetState(() {
          _selectedCategory = result;
        });
      }
      _showSnackBar('New category "$result" added successfully!');
    }
    _categoryController.clear();
  }

  void _showAddEditDialog({int? index}) {
    if (index != null) {
      _editingIndex = index;
      final plan = _plans[index];
      _editingDocId = plan['docId'];
      _nameController.text = plan['name'];
      _priceController.text = plan['price'].toString();
      _sessionsController.text = plan['sessions'].toString();
      _descriptionController.text = plan['description'];
      _selectedCategory = plan['category'];
      _selectedStatus = plan['status'];
    } else {
      _clearForm();
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return Align(
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: 0.9,
                child: AlertDialog(
                  insetPadding: EdgeInsets.zero,
                  scrollable: true,
                  title: Text(
                    _editingIndex == -1 ? 'Add New Plan' : 'Edit Plan',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00BCD4),
                    ),
                  ),
                  content: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Plan Name *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.fitness_center),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter plan name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                value: _selectedCategory,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Category *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.category),
                                ),
                                items: [
                                  ..._categories.map((String category) {
                                    return DropdownMenuItem<String>(
                                      value: category,
                                      child: Text(category, overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(),
                                  const DropdownMenuItem<String>(
                                    value: 'ADD_NEW_CATEGORY',
                                    child: Row(
                                      children: [
                                        Icon(Icons.add, size: 18, color: Colors.blue),
                                        SizedBox(width: 8),
                                        Text(
                                          'Add New Category',
                                          style: TextStyle(
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (String? newValue) async {
                                  if (newValue == 'ADD_NEW_CATEGORY') {
                                    await _showAddCategoryDialog(setDialogState);
                                  } else if (newValue != null) {
                                    setDialogState(() {
                                      _selectedCategory = newValue;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _sessionsController,
                            decoration: const InputDecoration(
                              labelText: 'Number of Sessions *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.numbers),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter number of sessions';
                              }
                              int? sessions = int.tryParse(value);
                              if (sessions == null || sessions <= 0) {
                                return 'Please enter a valid number of sessions';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _priceController,
                            decoration: const InputDecoration(
                              labelText: 'Price (\$) *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.attach_money),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                            ],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter price';
                              }
                              double? price = double.tryParse(value);
                              if (price == null || price <= 0) {
                                return 'Please enter a valid price';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Status *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.toggle_on),
                            ),
                            items: _statusOptions.map((String status) {
                              return DropdownMenuItem<String>(
                                value: status,
                                child: Text(status),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setDialogState(() {
                                _selectedStatus = newValue!;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.description),
                            ),
                            maxLines: 3,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter description';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _clearForm();
                      },
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          _savePlan();
                          Navigator.of(context).pop();
                          _clearForm();
                        }
                      },
                      child: Text(_editingIndex == -1 ? 'Add Plan' : 'Update Plan'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _savePlan() async {
    try {
      final planData = {
        'name': _nameController.text.trim(),
        'category': _selectedCategory,
        'sessions': int.parse(_sessionsController.text),
        'price': double.parse(_priceController.text),
        'status': _selectedStatus,
        'description': _descriptionController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_editingIndex == -1) {
        planData['createdAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('plans').add(planData);
        _showSnackBar('Plan added successfully!');
      } else {
        if (_editingDocId != null) {
          await _firestore.collection('plans').doc(_editingDocId).update(planData);
          _showSnackBar('Plan updated successfully!');
        }
      }
    } catch (e) {
      _showSnackBar('Error saving plan: $e');
      print('Error saving plan: $e');
    }
  }

  Future<void> _deletePlan(int index) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Plan'),
          content: Text('Are you sure you want to delete "${_plans[index]['name']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  String? docId = _plans[index]['docId'];
                  if (docId != null) {
                    await _firestore.collection('plans').doc(docId).delete();
                    _showSnackBar('Plan deleted successfully!');
                  }
                } catch (e) {
                  _showSnackBar('Error deleting plan: $e');
                  print('Error deleting plan: $e');
                }
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  // PDF Workouts Methods
  Future<void> _pickPdfFile(StateSetter setDialogState) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        setDialogState(() {
          _selectedPdfFile = result.files.first;
        });
      }
    } catch (e) {
      _showSnackBar('Error picking PDF file');
    }
  }

  void _showAddEditPdfDialog({int? index}) {
    // Store the original PDF information when editing
    PlatformFile? originalPdfFile;
    String? originalPdfUrl;
    String? originalPdfName;

    if (index != null) {
      _editingPdfIndex = index;
      final pdf = _pdfWorkouts[index];
      _editingPdfDocId = pdf['docId'];
      _pdfNameController.text = pdf['name'];
      _pdfDescriptionController.text = pdf['description'] ?? '';
      originalPdfUrl = pdf['pdfUrl'];
      originalPdfName = pdf['name'];
      
      // Store original PDF info for cancellation
      originalPdfFile = _selectedPdfFile;
    } else {
      _clearPdfForm();
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return Align(
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: 0.9,
                child: AlertDialog(
                  insetPadding: EdgeInsets.zero,
                  scrollable: true,
                  title: Text(
                    _editingPdfIndex == -1 ? 'Add PDF Workout' : 'Edit PDF Workout',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00BCD4),
                    ),
                  ),
                  content: SingleChildScrollView(
                    child: Form(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: _pdfNameController,
                            decoration: const InputDecoration(
                              labelText: 'Workout Name *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.fitness_center),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter workout name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _pdfDescriptionController,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.description),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.picture_as_pdf, size: 48, color: Colors.red),
                                const SizedBox(height: 8),
                                Text(
                                  _selectedPdfFile?.name ?? 'No PDF selected',
                                  style: TextStyle(
                                    color: _selectedPdfFile != null ? Colors.green : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_editingPdfIndex != -1 && originalPdfUrl != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Current PDF: $originalPdfName.pdf',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await _pickPdfFile(setDialogState);
                                  },
                                  icon: const Icon(Icons.attach_file),
                                  label: Text(_editingPdfIndex == -1 ? 'Select PDF File' : 'Change PDF File'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1C2D5E),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isUploading) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 8),
                            const Text('Uploading PDF...', textAlign: TextAlign.center),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: _isUploading ? null : () {
                        // On cancel, restore the original PDF file if editing
                        if (_editingPdfIndex != -1) {
                          _selectedPdfFile = originalPdfFile;
                        } else {
                          _selectedPdfFile = null;
                        }
                        Navigator.of(context).pop();
                        _clearPdfForm();
                      },
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: _isUploading ? null : () async {
                        if (_pdfNameController.text.trim().isEmpty) {
                          _showSnackBar('Please enter workout name');
                          return;
                        }
                        if (_editingPdfIndex == -1 && _selectedPdfFile == null) {
                          _showSnackBar('Please select a PDF file');
                          return;
                        }

                        setDialogState(() {
                          _isUploading = true;
                        });

                        await _savePdfWorkout();

                        setDialogState(() {
                          _isUploading = false;
                        });

                        if (!mounted) return;
                        Navigator.of(context).pop();
                        _clearPdfForm();
                      },
                      child: Text(_editingPdfIndex == -1 ? 'Add Workout' : 'Update Workout'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _savePdfWorkout() async {
    try {
      String? pdfUrl;
      
      // Upload new PDF file only if a new file is selected
      if (_selectedPdfFile != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('pdf_workouts')
            .child('${DateTime.now().millisecondsSinceEpoch}_${_selectedPdfFile!.name}');
        
        final uploadTask = storageRef.putFile(File(_selectedPdfFile!.path!));
        final snapshot = await uploadTask;
        pdfUrl = await snapshot.ref.getDownloadURL();
      }
      // If editing and no new file selected, keep the existing PDF URL
      else if (_editingPdfIndex != -1) {
        // Keep the existing PDF URL from the original document
        final originalPdf = _pdfWorkouts[_editingPdfIndex];
        pdfUrl = originalPdf['pdfUrl'];
      }

      final pdfData = {
        'name': _pdfNameController.text.trim(),
        'description': _pdfDescriptionController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (pdfUrl != null) 'pdfUrl': pdfUrl,
        if (_editingPdfIndex == -1) 'createdAt': FieldValue.serverTimestamp(),
      };

      if (_editingPdfIndex == -1) {
        await _firestore.collection('pdf_workouts').add(pdfData);
        _showSnackBar('PDF Workout added successfully!');
      } else {
        if (_editingPdfDocId != null) {
          await _firestore.collection('pdf_workouts').doc(_editingPdfDocId).update(pdfData);
          _showSnackBar('PDF Workout updated successfully!');
        }
      }
    } catch (e) {
      _showSnackBar('Error saving PDF workout');
      print('Error saving PDF workout');
    }
  }

  Future<void> _deletePdfWorkout(int index) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete PDF Workout'),
          content: Text('Are you sure you want to delete "${_pdfWorkouts[index]['name']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  String? docId = _pdfWorkouts[index]['docId'];
                  if (docId != null) {
                    // Delete from Firestore
                    await _firestore.collection('pdf_workouts').doc(docId).delete();

                    // Optionally delete from storage
                    final pdfUrl = _pdfWorkouts[index]['pdfUrl'];
                    if (pdfUrl != null) {
                      try {
                        await FirebaseStorage.instance.refFromURL(pdfUrl).delete();
                      } catch (e) {
                        print('Error deleting PDF file');
                      }
                    }

                    _showSnackBar('PDF Workout deleted successfully!');
                  }
                } catch (e) {
                  _showSnackBar('Error deleting PDF workout');
                  print('Error deleting PDF workout');
                }
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickVideoThumbnail(StateSetter setDialogState) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (image != null) {
        final file = File(image.path);
        setDialogState(() {
          _selectedVideoThumbnail = PlatformFile(
            name: image.name,
            size: file.lengthSync(),
            path: image.path,
          );
        });
      }
    } catch (e) {
      _showSnackBar('Error picking image: $e');
    }
  }

  Future<void> _pickVideoFile(StateSetter setDialogState) async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10),
      );

      if (video != null) {
        final file = File(video.path);
        final double sizeMB = (await file.length()) / (1024 * 1024);

        if (sizeMB > 500) {
          if (!mounted) return;
          _showSnackBar('Video size exceeds 500MB limit');
          return;
        }

        setDialogState(() {
          _selectedVideoFile = PlatformFile(
            name: video.name,
            size: file.lengthSync(),
            path: video.path,
          );
        });
      }
    } catch (e) {
      _showSnackBar('Error picking video: $e');
    }
  }

  void _showAddEditVideoDialog({int? index}) {
    if (index != null) {
      // EDITING MODE: Load workout data
      _editingVideoIndex = index;
      final video = _videoWorkouts[index];
      _editingVideoDocId = video['docId'];
      _videoNameController.text = video['name'];
      _videoDescriptionController.text = video['description'] ?? '';
      _selectedVideoCategory = video['category'] ?? 'Strength';
      _selectedVideoDifficulty = video['difficulty'] ?? 'Beginner';
      _existingVideoFile = (video['videoUrl'] ?? '').isNotEmpty;
      _existingVideoThumbnail = (video['thumbnailUrl'] ?? '').isNotEmpty;
      _selectedVideoFile = null;
      _selectedVideoThumbnail = null;
    } else {
      // ADD MODE: Clear form for new entry
      _clearVideoForm();
      _selectedVideoCategory = 'Strength';
      _selectedVideoDifficulty = 'Beginner';
      _existingVideoFile = false;
      _existingVideoThumbnail = false;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return Align(
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: 0.93,
                child: AlertDialog(
                  insetPadding: EdgeInsets.zero,
                  scrollable: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  titlePadding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
                  title: Text(
                    _editingVideoIndex == -1 ? 'Add Video Workout' : 'Edit Video Workout',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  content: SingleChildScrollView(
                    child: Form(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Workout Name
                          TextFormField(
                            controller: _videoNameController,
                            decoration: InputDecoration(
                              labelText: 'Workout Name',
                              hintText: 'Enter workout name',
                              prefixIcon: const Icon(Icons.title),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                  color: Color(0xFF1C2D5E),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter workout name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // Description
                          TextFormField(
                            controller: _videoDescriptionController,
                            decoration: InputDecoration(
                              labelText: 'Description',
                              hintText: 'Add workout description',
                              prefixIcon: const Icon(Icons.description),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                  color: Color(0xFF1C2D5E),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),

                          // Category
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Category *',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                value: _selectedVideoCategory,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.fitness_center, size: 18),
                                  contentPadding: const EdgeInsets.fromLTRB(12, 8, 40, 8),
                                  isDense: true,
                                ),
                                items: [
                                  ..._videoCategories
                                      .map((cat) => DropdownMenuItem(
                                            value: cat,
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(maxWidth: 120),
                                              child: Text(cat,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                  const DropdownMenuItem<String>(
                                    value: 'ADD_NEW_CATEGORY',
                                    child: Row(
                                      children: [
                                        Icon(Icons.add, size: 16, color: Colors.blue),
                                        SizedBox(width: 6),
                                        Text('Add New'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (value) async {
                                  if (value == 'ADD_NEW_CATEGORY') {
                                    final newCategory = await showDialog<String>(
                                      context: context,
                                      builder: (context) {
                                        final controller = TextEditingController();
                                        return AlertDialog(
                                          title: const Text('Add New Category'),
                                          content: TextField(
                                            controller: controller,
                                            decoration: const InputDecoration(
                                              hintText: 'Category name',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(context, controller.text.trim()),
                                              child: const Text('Add'),
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    if (newCategory != null && newCategory.isNotEmpty) {
                                      await _saveCustomCategory(newCategory);
                                      setDialogState(() {
                                        _selectedVideoCategory = newCategory;
                                      });
                                    }
                                  } else if (value != null) {
                                    setDialogState(() {
                                      _selectedVideoCategory = value;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Difficulty Level
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Difficulty Level *',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                value: _selectedVideoDifficulty,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  prefixIcon: const Icon(Icons.trending_up, size: 18),
                                  contentPadding: const EdgeInsets.fromLTRB(12, 8, 40, 8),
                                  isDense: true,
                                ),
                                items: _videoDifficulties
                                    .map((diff) => DropdownMenuItem(
                                          value: diff,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 100),
                                            child: Text(diff,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                        ))
                                    .toList(),
                                onChanged: (value) {
                                  setDialogState(() {
                                    _selectedVideoDifficulty = value!;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Media Upload Section - PROFESSIONAL UI
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Media Files',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Selected Media Display - Clean pill badges (shown if media selected)
                              if (_selectedVideoThumbnail != null || _existingVideoThumbnail || _selectedVideoFile != null || _existingVideoFile)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (_selectedVideoThumbnail != null || _existingVideoThumbnail)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.green[50],
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.green[200]!),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.image, size: 16, color: Colors.green),
                                                const SizedBox(width: 6),
                                                const Text(
                                                  'Thumbnail',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    onTap: () {
                                                      setDialogState(() {
                                                        _selectedVideoThumbnail = null;
                                                        _existingVideoThumbnail = false;
                                                      });
                                                    },
                                                    borderRadius: BorderRadius.circular(10),
                                                    child: const Icon(Icons.close, size: 16, color: Colors.green),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (_selectedVideoFile != null || _existingVideoFile)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.blue[50],
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.blue[200]!),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.video_library, size: 16, color: Colors.blue),
                                                const SizedBox(width: 6),
                                                const Text(
                                                  'Video',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.blue,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    onTap: () {
                                                      setDialogState(() {
                                                        _selectedVideoFile = null;
                                                        _existingVideoFile = false;
                                                      });
                                                    },
                                                    borderRadius: BorderRadius.circular(10),
                                                    child: const Icon(Icons.close, size: 16, color: Colors.blue),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Re-add buttons below badges
                                    Row(
                                      children: [
                                        if (_selectedVideoThumbnail == null && !_existingVideoThumbnail)
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () => _pickVideoThumbnail(setDialogState),
                                              icon: const Icon(Icons.image, size: 14),
                                              label: const Text('Add Thumbnail IMG', style: TextStyle(fontSize: 11)),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.green,
                                                side: const BorderSide(color: Colors.green),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                              ),
                                            ),
                                          ),
                                        if (_selectedVideoFile == null && !_existingVideoFile) ...[
                                          if (_selectedVideoThumbnail != null || _existingVideoThumbnail)
                                            const SizedBox(width: 12),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: () => _pickVideoFile(setDialogState),
                                              icon: const Icon(Icons.videocam, size: 14),
                                              label: const Text('Add Video', style: TextStyle(fontSize: 11)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF1C2D5E),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                )
                              else ...[
                                // Upload Buttons (shown when no media selected)
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _pickVideoThumbnail(setDialogState),
                                        icon: const Icon(Icons.image, size: 14),
                                        label: const Text('Add Thumbnail IMG', style: TextStyle(fontSize: 11)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.green,
                                          side: const BorderSide(color: Colors.green),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _pickVideoFile(setDialogState),
                                        icon: const Icon(Icons.videocam, size: 14),
                                        label: const Text('Add Video', style: TextStyle(fontSize: 11)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1C2D5E),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // File Size & Length Info
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue[200]!),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.info_outline, size: 14, color: Colors.blue[700]),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Thumbnail: JPG, PNG • Max 5MB',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Icon(Icons.info_outline, size: 14, color: Colors.blue[700]),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Video: MP4, MOV, AVI • Max 500MB',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue[700],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _clearVideoForm();
                      },
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _uploadStates.values.any((state) => state.isUploading) ? null : () async {
                        final workoutName = _videoNameController.text.trim();

                        if (workoutName.isEmpty) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter workout name'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        // Check if video is required (when adding new or when removed during edit)
                        if (_selectedVideoFile == null && !_existingVideoFile) {
                          if (!mounted) return;
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Video Required'),
                              content: const Text('Please select a video file to add/update this workout.'),
                              actions: [
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1C2D5E),
                                  ),
                                  child: const Text(
                                    'OK',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );
                          return;
                        }

                        if (!mounted) return;

                        final isEditing = _editingVideoIndex != -1;
                        final uploadId = DateTime.now().millisecondsSinceEpoch.toString();

                        setState(() {
                          _isProcessingVideo = true;
                          _uploadStates[uploadId] = VideoUploadState(
                            uploadId: uploadId,
                            workoutName: workoutName,
                          )..isUploading = true
                            ..message = isEditing ? 'Updating $workoutName' : 'Adding $workoutName';
                        });

                        // Close add video dialog immediately
                        // ignore: use_build_context_synchronously
                        Navigator.of(context).pop();

                        // Capture ScaffoldMessenger before async gap
                        final scaffoldMessenger = ScaffoldMessenger.of(context);

                        try {
                          await _saveVideoWorkout(
                            uploadId: uploadId,
                            onProgress: (progress) {
                              final safeProgress = progress.clamp(0.0, 1.0);

                              if (mounted) {
                                setState(() {
                                  if (_uploadStates.containsKey(uploadId)) {
                                    _uploadStates[uploadId]!.progress = safeProgress;
                                  }
                                });
                              }
                            },
                          );

                          if (mounted) {
                            setState(() {
                              _isProcessingVideo = false;
                              if (_uploadStates.containsKey(uploadId)) {
                                _uploadStates[uploadId]!
                                  ..isUploading = false
                                  ..isComplete = true
                                  ..message = isEditing ? 'Updated $workoutName' : 'Added $workoutName';
                              }
                            });
                            _clearVideoForm();
                            _uploadStates.remove(uploadId);

                            scaffoldMessenger.hideCurrentSnackBar();
                            _showSnackBar(isEditing ? 'Workout updated successfully! ✅' : 'Workout added successfully! ✅');
                          }
                        } catch (e) {
                          print('Error: $e');
                          if (mounted) {
                            setState(() {
                              _isProcessingVideo = false;
                              if (_uploadStates.containsKey(uploadId)) {
                                _uploadStates[uploadId]!
                                  ..isUploading = false
                                  ..hasError = true
                                  ..errorMessage = e.toString();
                              }
                            });
                            _uploadStates.remove(uploadId);

                            scaffoldMessenger.hideCurrentSnackBar();
                            _showSnackBar('Error: ${e.toString()}');
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1C2D5E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        _editingVideoIndex == -1 ? 'Add Workout' : 'Update Workout',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<String> _getVideoDuration(String videoUrl) async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await controller.initialize();
      final duration = controller.value.duration;
      controller.dispose();
      return _formatDuration(duration);
    } catch (e) {
      print('Error calculating duration: $e');
      return '';
    }
  }

  Future<void> _saveVideoWorkout({
    required String uploadId,
    Function(double)? onProgress,
  }) async {
    try {
      String? thumbnailUrl;
      String? videoUrl;
      double totalBytes = 0;
      double thumbnailBytes = 0;
      double videoBytes = 0;

      // Calculate total bytes to upload
      if (_selectedVideoThumbnail != null) {
        final file = File(_selectedVideoThumbnail!.path!);
        if (await file.exists()) {
          thumbnailBytes = (await file.length()).toDouble();
          totalBytes += thumbnailBytes;
        }
      }
      if (_selectedVideoFile != null) {
        final file = File(_selectedVideoFile!.path!);
        if (await file.exists()) {
          videoBytes = (await file.length()).toDouble();
          totalBytes += videoBytes;
        }
      }

      // Upload thumbnail if selected
      if (_selectedVideoThumbnail != null) {
        try {
          final thumbnailFile = File(_selectedVideoThumbnail!.path!);
          if (!await thumbnailFile.exists()) {
            _showSnackBar('Thumbnail file not found');
            return;
          }

          final storageRef = FirebaseStorage.instance
              .ref()
              .child('video_thumbnails')
              .child('${DateTime.now().millisecondsSinceEpoch}_${_selectedVideoThumbnail!.name}');

          final uploadTask = storageRef.putFile(thumbnailFile);

          uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
            if (totalBytes > 0 && onProgress != null) {
              onProgress(snapshot.bytesTransferred / totalBytes);
            }
          });

          final snapshot = await uploadTask;
          thumbnailUrl = await snapshot.ref.getDownloadURL();
        } catch (e) {
          _showSnackBar('Error uploading thumbnail: $e');
          return;
        }
      } else if (_editingVideoIndex != -1 && _existingVideoThumbnail) {
        // Keep existing thumbnail only if user didn't remove it
        thumbnailUrl = _videoWorkouts[_editingVideoIndex]['thumbnailUrl'];
      }

      // Upload video file if selected
      if (_selectedVideoFile != null) {
        try {
          final videoFile = File(_selectedVideoFile!.path!);
          if (!await videoFile.exists()) {
            _showSnackBar('Video file not found');
            return;
          }

          final storageRef = FirebaseStorage.instance
              .ref()
              .child('video_workouts')
              .child('${DateTime.now().millisecondsSinceEpoch}_${_selectedVideoFile!.name}');

          final uploadTask = storageRef.putFile(videoFile);

          uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
            if (totalBytes > 0 && onProgress != null) {
              onProgress((thumbnailBytes + snapshot.bytesTransferred) / totalBytes);
            }
          });

          final snapshot = await uploadTask;
          videoUrl = await snapshot.ref.getDownloadURL();
        } catch (e) {
          _showSnackBar('Error uploading video: $e');
          return;
        }
      } else if (_editingVideoIndex != -1 && _existingVideoFile) {
        // Keep existing video URL only if user didn't remove it
        videoUrl = _videoWorkouts[_editingVideoIndex]['videoUrl'];
      }

      // Handle deletion of removed media when editing
      if (_editingVideoIndex != -1) {
        final originalVideo = _videoWorkouts[_editingVideoIndex];

        // If thumbnail was removed (user clicked X), delete old file from storage
        if (!_existingVideoThumbnail && (originalVideo['thumbnailUrl'] ?? '').isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(originalVideo['thumbnailUrl']).delete();
          } catch (e) {
            print('Warning: Could not delete old thumbnail: $e');
          }
        }

        // If video was removed (user clicked X), delete old file from storage
        if (!_existingVideoFile && (originalVideo['videoUrl'] ?? '').isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(originalVideo['videoUrl']).delete();
          } catch (e) {
            print('Warning: Could not delete old video: $e');
          }
        }
      }

      // Calculate duration if new video is uploaded
      String? duration;
      if (_selectedVideoFile != null && videoUrl != null) {
        duration = await _getVideoDuration(videoUrl);
      } else if (_editingVideoIndex != -1) {
        // Keep existing duration if editing
        duration = _videoWorkouts[_editingVideoIndex]['duration'];
      }

      final videoData = <String, dynamic>{
        'name': _videoNameController.text.trim(),
        'description': _videoDescriptionController.text.trim(),
        'category': _selectedVideoCategory,
        'difficulty': _selectedVideoDifficulty,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Handle thumbnail URL
      if (thumbnailUrl != null) {
        // New thumbnail uploaded
        videoData['thumbnailUrl'] = thumbnailUrl;
      } else if (_editingVideoIndex != -1 && !_existingVideoThumbnail) {
        // User removed thumbnail during edit
        videoData['thumbnailUrl'] = FieldValue.delete();
      } else if (_editingVideoIndex != -1 && _existingVideoThumbnail) {
        // Keep existing thumbnail if user didn't change it
        videoData['thumbnailUrl'] = _videoWorkouts[_editingVideoIndex]['thumbnailUrl'];
      }

      // Handle video URL
      if (videoUrl != null) {
        // New video uploaded
        videoData['videoUrl'] = videoUrl;
      } else if (_editingVideoIndex != -1 && !_existingVideoFile) {
        // User removed video during edit
        videoData['videoUrl'] = FieldValue.delete();
      } else if (_editingVideoIndex != -1 && _existingVideoFile) {
        // Keep existing video if user didn't change it
        videoData['videoUrl'] = _videoWorkouts[_editingVideoIndex]['videoUrl'];
      }

      // Handle duration - always include in update
      if (duration != null) {
        videoData['duration'] = duration;
      } else if (_editingVideoIndex != -1) {
        // Keep existing duration when editing if no new video
        final existingDuration = _videoWorkouts[_editingVideoIndex]['duration'];
        if (existingDuration != null) {
          videoData['duration'] = existingDuration;
        }
      }

      // Handle creation timestamp
      if (_editingVideoIndex == -1) {
        videoData['createdAt'] = FieldValue.serverTimestamp();
      }

      if (_editingVideoIndex == -1) {
        await _firestore.collection('video_workouts').add(videoData);
        _showSnackBar('Workout added successfully!');
      } else {
        if (_editingVideoDocId != null) {
          await _firestore.collection('video_workouts').doc(_editingVideoDocId).update(videoData);
          _showSnackBar('Workout updated successfully!');
        }
      }
    } catch (e) {
      _showSnackBar('Error saving video workout: $e');
    }
  }

  Future<void> _deleteVideoWorkout(int index) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Video Workout'),
          content: Text('Are you sure you want to delete "${_videoWorkouts[index]['name']}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  String? docId = _videoWorkouts[index]['docId'];
                  if (docId != null) {
                    await _firestore.collection('video_workouts').doc(docId).delete();
                    _showSnackBar('Workout deleted successfully!');
                  }
                } catch (e) {
                  _showSnackBar('Error deleting video workout');
                }
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildPlansTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add New Plan'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('plans').orderBy('createdAt', descending: false).snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs;
              _plans = docs.map((d) {
                final m = d.data()! as Map<String, dynamic>;
                m['docId'] = d.id;
                return m;
              }).toList();

              if (_plans.isEmpty) {
                return const Center(child: Text('No plans available'));
              }

              // Sort by category index first, then by sessions, then by createdAt
              _plans.sort((a, b) {
                // First priority: category index comparison
                int catIndexA = _categories.indexOf(a['category']);
                if (catIndexA == -1) catIndexA = _categories.length;
                int catIndexB = _categories.indexOf(b['category']);
                if (catIndexB == -1) catIndexB = _categories.length;
                int catCompare = catIndexA.compareTo(catIndexB);
                if (catCompare != 0) return catCompare;
                
                // Second priority: sessions comparison within same category
                int sessionsCompare = (a['sessions'] as int).compareTo(b['sessions'] as int);
                if (sessionsCompare != 0) return sessionsCompare;
                
                // Third priority: creation time (newly added plans at bottom)
                var aCreated = a['createdAt'];
                var bCreated = b['createdAt'];
                
                if (aCreated != null && bCreated != null) {
                  if (aCreated is Timestamp && bCreated is Timestamp) {
                    return aCreated.compareTo(bCreated);
                  }
                }
                return 0;
              });

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _plans.length,
                itemBuilder: (c, i) {
                  final plan = _plans[i];
                  final expanded = _expandedPlanIndex == i;
                  final isActive = plan['status'] == 'Active';

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: InkWell(
                        onTap: () => setState(
                            () => _expandedPlanIndex = expanded ? null : i),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      plan['category'],
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? Colors.green[100]
                                          : Colors.orange[100],
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isActive 
                                            ? Icons.check_circle_outline 
                                            : Icons.pause_circle_outline,
                                          size: 16,
                                          color: isActive
                                            ? Colors.green[800]
                                            : Colors.orange[800],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          plan['status'],
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isActive
                                                ? Colors.green[800]
                                                : Colors.orange[800],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${plan['name']} - ${plan['sessions']} session(s)',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '\$${(plan['price'] as num).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isActive ? Colors.green : Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    expanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 20,
                                    color: Colors.black,
                                  ),
                                ],
                              ),
                              if (expanded) ...[
                                const SizedBox(height: 8),
                                Text(
                                  plan['description'] ?? '',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        final idx = _plans.indexWhere(
                                            (p) => p['docId'] == plan['docId']);
                                        _showAddEditDialog(index: idx);
                                      },
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Text('Edit'),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      onPressed: () {
                                        final idx = _plans.indexWhere(
                                            (p) => p['docId'] == plan['docId']);
                                        _deletePlan(idx);
                                      },
                                      icon: const Icon(Icons.delete, size: 18),
                                      label: const Text('Delete'),
                                      style: TextButton.styleFrom(
                                          foregroundColor: Colors.red),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPdfWorkoutsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAddEditPdfDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add PDF Workout'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: const Color(0xFF1C2D5E),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('pdf_workouts').orderBy('createdAt', descending: true).snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs;
              _pdfWorkouts = docs.map((d) {
                final m = d.data()! as Map<String, dynamic>;
                m['docId'] = d.id;
                return m;
              }).toList();

              if (_pdfWorkouts.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No PDF Workouts Available',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Click the button above to add your first PDF workout',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _pdfWorkouts.length,
                itemBuilder: (c, i) {
                  final pdf = _pdfWorkouts[i];
                  final expanded = _expandedPdfIndex == i;

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      child: InkWell(
                        onTap: () => setState(
                          () => _expandedPdfIndex = expanded ? null : i,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.picture_as_pdf,
                                      size: 24,
                                      color: Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pdf['name'],
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        if (pdf['description'] != null && pdf['description'].isNotEmpty)
                                          Text(
                                            pdf['description'],
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    expanded ? Icons.expand_less : Icons.expand_more,
                                    size: 20,
                                    color: Colors.black,
                                  ),
                                ],
                              ),
                              if (expanded) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        final idx = _pdfWorkouts.indexWhere(
                                            (p) => p['docId'] == pdf['docId']);
                                        _showAddEditPdfDialog(index: idx);
                                      },
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Text('Edit'),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      onPressed: () {
                                        final idx = _pdfWorkouts.indexWhere(
                                            (p) => p['docId'] == pdf['docId']);
                                        _deletePdfWorkout(idx);
                                      },
                                      icon: const Icon(Icons.delete, size: 18),
                                      label: const Text('Delete'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVideoWorkoutsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAddEditVideoDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Video Workout'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: const Color(0xFF1C2D5E),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('video_workouts').orderBy('createdAt', descending: true).snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data!.docs;
              _videoWorkouts = docs.map((d) {
                final m = d.data()! as Map<String, dynamic>;
                m['docId'] = d.id;
                return m;
              }).toList();

              if (_videoWorkouts.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No Video Workouts Available',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Click the button above to add your first video workout',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _videoWorkouts.length,
                itemBuilder: (c, i) {
                  final video = _videoWorkouts[i];
                  final expanded = _expandedVideoIndex == i;

                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      child: InkWell(
                        onTap: () => setState(
                          () => _expandedVideoIndex = expanded ? null : i,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.videocam,
                                      size: 24,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          video['name'],
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        if (video['duration'] != null && (video['duration'] as String).isNotEmpty)
                                          Text(
                                            'Duration: ${video['duration']}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    expanded ? Icons.expand_less : Icons.expand_more,
                                    size: 20,
                                    color: Colors.black,
                                  ),
                                ],
                              ),
                              if (expanded) ...[
                                const SizedBox(height: 8),
                                if (video['description'] != null && (video['description'] as String).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      video['description'],
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        final idx = _videoWorkouts.indexWhere(
                                            (v) => v['docId'] == video['docId']);
                                        _showAddEditVideoDialog(index: idx);
                                      },
                                      icon: const Icon(Icons.edit, size: 18),
                                      label: const Text('Edit'),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      onPressed: () {
                                        final idx = _videoWorkouts.indexWhere(
                                            (v) => v['docId'] == video['docId']);
                                        _deleteVideoWorkout(idx);
                                      },
                                      icon: const Icon(Icons.delete, size: 18),
                                      label: const Text('Delete'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Plans'),
        backgroundColor: const Color(0xFF1C2D5E),
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
              text: 'Plans',
              iconMargin: EdgeInsets.only(bottom: 6),
            ),
            Tab(
              icon: Icon(Icons.videocam, size: 28),
              text: 'Video Workouts',
              iconMargin: EdgeInsets.only(bottom: 6),
            ),
            Tab(
              icon: Icon(Icons.picture_as_pdf, size: 28),
              text: 'PDF Workouts',
              iconMargin: EdgeInsets.only(bottom: 6),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPlansTab(),
                      _buildVideoWorkoutsTab(),
                      _buildPdfWorkoutsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Video Loading Overlay
          if (_isProcessingVideo)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  width: 320,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._uploadStates.entries.map((entry) {
                        final uploadState = entry.value;
                        final progressPercent = (uploadState.progress * 100).toInt();
                        final isUpdating = uploadState.message.contains('Updating');

                        return Column(
                          children: [
                            Text(
                              isUpdating ? 'Updating Workout' : 'Adding Workout',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1C2D5E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              uploadState.workoutName,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: uploadState.progress,
                                minHeight: 8,
                                backgroundColor: Colors.grey[300],
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF1C2D5E),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Progress Text
                            Text(
                              '$progressPercent%',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1C2D5E),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

}
