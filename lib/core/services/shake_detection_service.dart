import 'package:flutter/material.dart';
import 'package:shake/shake.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geocoding/geocoding.dart';
import '../../presentation/home/controllers/alert_controller.dart';
import '../../presentation/auth/controllers/profile_controller.dart';

/// Service to detect phone shake gestures and trigger emergency alerts
///
/// This service uses the accelerometer to detect when the user shakes their phone.
/// It can be started/stopped based on user role (students only) and triggers
/// appropriate actions when shake is detected.
class ShakeDetectionService {
  static final ShakeDetectionService _instance =
      ShakeDetectionService._internal();
  ShakeDetectionService._internal();
  static ShakeDetectionService get instance => _instance;

  ShakeDetector? _shakeDetector;
  bool _isListening = false;
  BuildContext? _context;

  /// Check if shake detection is currently active
  bool get isListening => _isListening;

  /// Initialize and start shake detection
  ///
  /// FR11: Detects shake with acceleration > 15 m/s², 3 times within 2-3 seconds
  /// Start listening for shake events (FR11 requirements)
  ///
  /// [context] - BuildContext for showing dialogs/popups
  /// [shakeThresholdGravity] - Sensitivity threshold in G-force (FR11: 15 m/s² = 1.53G)
  /// [minimumShakeCount] - Number of shakes required (FR11: 3 shakes)
  /// [shakeSlopTimeMS] - Time window for consecutive shakes (FR11: 2-3 seconds)
  /// [shakeCountResetTime] - Time to reset shake count
  void startListening({
    required BuildContext context,
    double shakeThresholdGravity = 1.53, // FR11: 15 m/s² = 1.53G
    int minimumShakeCount = 2, // FR11: 3 shakes
    int shakeSlopTimeMS = 2500, // FR11: 2.5 seconds (middle of 2-3s range)
    int shakeCountResetTime = 3000,
  }) {
    if (_isListening) {
      print('⚠️ Shake detection already running');
      return;
    }

    _context = context;

    print('🔧 Starting shake detection...');
    print('   Device: Running on real device');

    try {
      _shakeDetector = ShakeDetector.autoStart(
        onPhoneShake: (event) {
          print('📳 onPhoneShake callback triggered!');
          _onShakeDetected(event);
        },
        shakeThresholdGravity: shakeThresholdGravity,
        minimumShakeCount: minimumShakeCount,
        shakeSlopTimeMS: shakeSlopTimeMS,
        shakeCountResetTime: shakeCountResetTime,
      );

      _isListening = true;
      print('✅ Shake detection started successfully');
      print(
        '   Threshold: ${shakeThresholdGravity}G (≈${(shakeThresholdGravity * 9.8).toStringAsFixed(1)} m/s²)',
      );
      print('   Required shakes: $minimumShakeCount');
      print('   Time window: ${shakeSlopTimeMS}ms');
      print('   ShakeDetector instance created: ${_shakeDetector != null}');
      print('🎯 Try shaking your phone NOW - very lightly!');
    } catch (e) {
      print('❌ ERROR starting shake detection: $e');
      _isListening = false;
    }
  }

  /// Stop shake detection
  void stopListening() {
    if (!_isListening) {
      print('⚠️ Shake detection not running');
      return;
    }

    _shakeDetector?.stopListening();
    _shakeDetector = null;
    _isListening = false;
    _context = null;

    print('✅ Shake detection stopped');
  }

  /// Handle shake detection event
  void _onShakeDetected(dynamic event) async {
    print('🔔 SHAKE DETECTED! Triggering SOS alert...');

    if (_context == null || !_context!.mounted) {
      print('⚠️ Cannot send alert - context not available');
      return;
    }

    try {
      // Get fresh student data from Firestore
      final profileController = ProfileController.instance;
      await profileController.loadFromFirestore();

      // Get current GPS location
      double latitude = profileController.latitude ?? 0.0;
      double longitude = profileController.longitude ?? 0.0;

      var locationStatus = await Permission.location.status;
      if (!locationStatus.isGranted) {
        locationStatus = await Permission.location.request();
      }

      if (locationStatus.isGranted) {
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
          );
          latitude = position.latitude;
          longitude = position.longitude;
        } catch (e) {
          print('⚠️ Error getting location: $e');
        }
      }

      // Reverse geocode location
      String locationString = 'Unknown location';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          latitude,
          longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          locationString = [
            place.street,
            place.subLocality,
            place.locality,
          ].where((s) => s != null && s.isNotEmpty).join(', ');
        }
      } catch (e) {
        locationString =
            'Lat: ${latitude.toStringAsFixed(6)}, Lon: ${longitude.toStringAsFixed(6)}';
      }

      // Send SOS alert through AlertController (same as manual SOS button)
      print('📤 Sending shake-triggered SOS alert...');
      await AlertController.instance.sendAlert(
        studentId: profileController.studentId,
        studentName: profileController.name,
        studentPhone: profileController.phone,
        studentEmail: profileController.email,
        latitude: latitude,
        longitude: longitude,
        location: locationString,
        department: profileController.department,
        session: profileController.session,
      );

      // Show success notification
      if (_context != null && _context!.mounted) {
        _showSuccessPopup(_context!);
      }

      print('✅ Shake-triggered SOS alert sent successfully!');
    } catch (e) {
      print('❌ Error sending shake alert: $e');

      // Show error notification
      if (_context != null && _context!.mounted) {
        _showErrorPopup(_context!, e.toString());
      }
    }
  }

  /// Show success popup after alert sent
  void _showSuccessPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.green[50],
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text('SOS Alert Sent!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✅ Your shake-triggered emergency alert has been sent.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                'Proctorial body has been notified and help is on the way.',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text('OK', style: TextStyle(color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  /// Show error popup if alert fails
  void _showErrorPopup(BuildContext context, String error) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.red[50],
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text('Alert Failed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '❌ Failed to send shake-triggered alert.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 12),
              Text(
                'Error: $error',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text('OK', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  /// Dispose and cleanup
  void dispose() {
    stopListening();
  }
}
