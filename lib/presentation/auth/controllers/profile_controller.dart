import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileController extends ChangeNotifier {
  static final ProfileController instance = ProfileController._internal();
  ProfileController._internal();

  String name = 'Student';
  String studentId = 'CSE-2019-0001';
  String department = 'Computer Science & Engineering';
  String session = '2019-20';
  String phone = '01819129553';
  String email = 'student@nstu.edu.bd';
  String? savedLocation;
  double? latitude;
  double? longitude;
  String? building;
  String? floor;
  
  // Staff-specific fields
  String designation = '';
  String role = 'student';

  void setSignupEmail(String value) {
    email = value;
    notifyListeners();
  }

  void setProfileSetup({
    required String name,
    required String studentId,
    required String department,
    required String session,
    required String phone,
  }) {
    this.name = name;
    this.studentId = studentId;
    this.department = department;
    this.session = session;
    this.phone = phone;
    notifyListeners();
  }

  void setLocation({
    required String location,
    required double lat,
    required double lon,
    String? building,
    String? floor,
  }) {
    savedLocation = location;
    latitude = lat;
    longitude = lon;
    this.building = building;
    this.floor = floor;
    notifyListeners();
    _saveToPrefs();
  }

  void updateAll({
    String? name,
    String? studentId,
    String? department,
    String? session,
    String? phone,
    String? email,
  }) {
    if (name != null) this.name = name;
    if (studentId != null) this.studentId = studentId;
    if (department != null) this.department = department;
    if (session != null) this.session = session;
    if (phone != null) this.phone = phone;
    if (email != null) this.email = email;
    notifyListeners();
    _saveToPrefs();
  }

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('profile.name') ?? name;
    studentId = prefs.getString('profile.studentId') ?? studentId;
    department = prefs.getString('profile.department') ?? department;
    session = prefs.getString('profile.session') ?? session;
    phone = prefs.getString('profile.phone') ?? phone;
    email = prefs.getString('profile.email') ?? email;
    designation = prefs.getString('profile.designation') ?? designation;
    role = prefs.getString('profile.role') ?? role;
    savedLocation = prefs.getString('profile.savedLocation');
    latitude = prefs.getDouble('profile.latitude');
    longitude = prefs.getDouble('profile.longitude');
    notifyListeners();
  }

  /// Load user profile from Firestore (works for all roles including staff)
  Future<void> loadFromFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (!doc.exists) return;
      
      final data = doc.data()!;
      
      // Common fields
      name = data['name'] ?? name;
      email = data['email'] ?? email;
      phone = data['phone'] ?? phone;
      role = data['role'] ?? role;
      
      // Staff-specific fields
      if (role == 'proctorial' || role == 'security') {
        designation = data['designation'] ?? '';
        // Clear student-specific fields for staff
        studentId = '';
        session = '';
        if (role == 'proctorial') {
          department = 'Proctorial Body';
        } else {
          department = 'Security Body';
        }
      } else {
        // Student-specific fields
        studentId = data['studentId'] ?? studentId;
        department = data['department'] ?? department;
        session = data['session'] ?? session;
      }
      
      notifyListeners();
      await _saveToPrefs();
    } catch (e) {
      debugPrint('Error loading profile from Firestore: $e');
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile.name', name);
    await prefs.setString('profile.studentId', studentId);
    await prefs.setString('profile.department', department);
    await prefs.setString('profile.session', session);
    await prefs.setString('profile.phone', phone);
    await prefs.setString('profile.email', email);
    await prefs.setString('profile.designation', designation);
    await prefs.setString('profile.role', role);
    if (savedLocation != null) await prefs.setString('profile.savedLocation', savedLocation!);
    if (latitude != null) await prefs.setDouble('profile.latitude', latitude!);
    if (longitude != null) await prefs.setDouble('profile.longitude', longitude!);
  }
}
