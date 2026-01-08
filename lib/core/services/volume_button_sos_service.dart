import 'dart:async';
import 'package:volume_controller/volume_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geocoding/geocoding.dart';
import '../../presentation/home/controllers/alert_controller.dart';
import '../../presentation/auth/controllers/profile_controller.dart';

/// Service to detect volume button presses for emergency SOS (FR12)
///
/// Listens for rapid volume button presses (3 times within 3 seconds)
/// to trigger emergency alert. Works even when screen is locked or app
/// is in background.
class VolumeButtonSosService {
  static final VolumeButtonSosService _instance =
      VolumeButtonSosService._internal();
  VolumeButtonSosService._internal();
  static VolumeButtonSosService get instance => _instance;

  VolumeController? _volumeController;
  bool _isListening = false;
  bool _isPaused = false; // Pause during calls to prevent false triggers
  double? _previousVolume;
  DateTime? _lastAlertTime; // Track last alert time for cooldown

  // Track button presses for pattern detection
  List<DateTime> _pressTimes = [];
  final int _requiredPresses = 3; // FR12: 3 presses
  final Duration _timeWindow = Duration(seconds: 3); // FR12: within 3 seconds
  final Duration _cooldownPeriod = Duration(
    seconds: 10,
  ); // Cooldown after alert

  /// Check if volume button SOS is currently active
  bool get isListening => _isListening;

  /// Pause volume button detection (e.g., during phone calls)
  void pause() {
    if (!_isListening) return;
    _isPaused = true;
    _pressTimes.clear(); // Clear any pending presses
    print('⏸️ Volume button SOS paused (e.g., during call)');
  }

  /// Resume volume button detection
  void resume() {
    if (!_isListening) return;
    _isPaused = false;
    print('▶️ Volume button SOS resumed');
  }

  /// Start listening for volume button presses
  Future<void> startListening() async {
    if (_isListening) {
      print('⚠️ Volume button SOS already listening');
      return;
    }

    print('🔧 Starting volume button SOS detection...');

    try {
      _volumeController = VolumeController();

      // Get initial volume
      _previousVolume = await _volumeController!.getVolume();
      print('📊 Initial volume: $_previousVolume');

      // Add listener for volume changes (v2.0.8 API)
      _volumeController!.listener((volume) {
        print('🔊 Volume changed: $_previousVolume → $volume');
        _onVolumeChanged(volume);
      });

      _isListening = true;
      print('✅ Volume button SOS started successfully');
      print('   Pattern: $_requiredPresses presses within $_timeWindow');

      // Give user guidance based on current volume
      if (_previousVolume == 1.0) {
        print('🎯 Volume at MAX - press VOLUME DOWN 3 times quickly');
      } else if (_previousVolume == 0.0) {
        print('🎯 Volume at MIN - press VOLUME UP 3 times quickly');
      } else {
        print('🎯 Press volume UP or DOWN 3 times quickly to trigger SOS');
      }
    } catch (e) {
      print('❌ ERROR starting volume button SOS: $e');
      _isListening = false;
    }
  }

  /// Stop listening for volume button presses
  void stopListening() {
    if (!_isListening) {
      print('⚠️ Volume button SOS not running');
      return;
    }

    _volumeController?.removeListener();
    _volumeController = null;
    _isListening = false;
    _pressTimes.clear();
    _previousVolume = null;
    // DON'T clear _lastAlertTime - cooldown should persist across restarts

    print('✅ Volume button SOS stopped');
  }

  /// Handle volume change (button press detected)
  void _onVolumeChanged(double newVolume) {
    // Volume button was pressed - listener callback fired
    // No need to check if value changed (may be at max/min)
    _previousVolume = newVolume;
    _onButtonPressed();
  }

  /// Handle volume button press
  void _onButtonPressed() {
    // Ignore if paused (e.g., during phone call)
    if (_isPaused) {
      return;
    }

    final now = DateTime.now();

    // Check if still in cooldown period
    if (_lastAlertTime != null) {
      final timeSinceLastAlert = now.difference(_lastAlertTime!);
      if (timeSinceLastAlert < _cooldownPeriod) {
        final remainingSeconds =
            (_cooldownPeriod - timeSinceLastAlert).inSeconds;
        print('⏳ Cooldown active: ${remainingSeconds}s remaining');
        return;
      }
    }

    // Add current press
    _pressTimes.add(now);

    // Remove presses outside time window
    _pressTimes.removeWhere((time) => now.difference(time) > _timeWindow);

    print(
      '🔘 Volume button pressed (${_pressTimes.length}/$_requiredPresses in ${_timeWindow.inSeconds}s)',
    );

    // Check if pattern matched
    if (_pressTimes.length >= _requiredPresses) {
      print('🚨 VOLUME BUTTON SOS PATTERN DETECTED!');
      _lastAlertTime = DateTime.now(); // Start cooldown
      _pressTimes.clear(); // Reset to prevent duplicate alerts
      print(
        '⏱️ Cooldown started: No new alerts for ${_cooldownPeriod.inSeconds}s',
      );
      _sendSosAlert();
    }
  }

  /// Send SOS alert (same logic as shake detection and manual SOS)
  Future<void> _sendSosAlert() async {
    print('📤 Sending volume button SOS alert...');

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

      // Send SOS alert through AlertController
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

      print('✅ Volume button SOS alert sent successfully!');
    } catch (e) {
      print('❌ Error sending volume button SOS alert: $e');
    }
  }

  /// Dispose and cleanup
  void dispose() {
    stopListening();
  }
}
