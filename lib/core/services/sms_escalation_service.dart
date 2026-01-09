import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:safelink_n/core/constants/app_constants.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../presentation/home/controllers/alert_controller.dart';
import '../utils/native_sms.dart';
import 'call_escalation_service.dart';

/// Service to schedule SMS escalation after 1 minute for each alert
class SmsEscalationService {
  static final SmsEscalationService _instance =
      SmsEscalationService._internal();
  SmsEscalationService._internal();
  static SmsEscalationService get instance => _instance;

  final Map<String, Timer> _activeTimers = {}; // One timer per alert
  BuildContext? _context; // For showing countdown dialog

  /// Set context for showing countdown dialogs
  void setContext(BuildContext context) {
    _context = context;
    print('✅ SMS Escalation service context set');
  }

  /// Clear context when screen disposed
  void clearContext() {
    _context = null;
    print('✅ SMS Escalation service context cleared');
  }

  /// Schedule SMS escalation for a specific alert
  Future<void> scheduleEscalation(String alertId) async {
    // Check if SMS has already been escalated
    try {
      final alertDoc = await FirebaseFirestore.instance
          .collection('proctorial_alerts')
          .doc(alertId)
          .get();

      if (alertDoc.exists) {
        final alertData = alertDoc.data()!;
        final bool smsEscalated = alertData['smsEscalated'] ?? false;

        if (smsEscalated) {
          print('⏭️ SMS already escalated for alert $alertId - skipping');
          return;
        }
      }
    } catch (e) {
      print('⚠️ Error checking SMS escalation status: $e');
      // Continue with scheduling if check fails
    }

    // Cancel existing timer if any (shouldn't happen, but just in case)
    _activeTimers[alertId]?.cancel();

    // DEVELOPMENT: Change seconds value here (60 for production, 10 for testing)
    const int escalationDelaySeconds =
        AppConstants.smsDelaySeconds; // TODO: Change back to 60 for production

    print(
      '⏰ Scheduled SMS escalation for alert $alertId (in $escalationDelaySeconds seconds)',
    );
    print('   Context available: ${_context != null}');
    print('   Context mounted: ${_context?.mounted}');

    // Start timer for this specific alert
    _activeTimers[alertId] = Timer(
      Duration(seconds: escalationDelaySeconds),
      () async {
        print(
          '⏰ $escalationDelaySeconds seconds elapsed for alert $alertId - triggering SMS escalation',
        );
        print('   Context still available: ${_context != null}');
        print('   Context still mounted: ${_context?.mounted}');
        await _triggerSmsEscalation(alertId);
        _activeTimers.remove(alertId);
      },
    );
  }

  /// Cancel escalation for a specific alert (when accepted/resolved)
  void cancelEscalation(String alertId) {
    final timer = _activeTimers[alertId];
    if (timer != null) {
      timer.cancel();
      _activeTimers.remove(alertId);
      print('🚫 SMS escalation cancelled for alert $alertId');
    }
  }

  /// Cancel all active timers (when service stops)
  void cancelAllEscalations() {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    print('🚫 All SMS escalations cancelled');
  }

  /// Validate Bangladesh phone number format
  bool _isValidBDPhone(String phone) {
    // Bangladesh phone format: +880XXXXXXXXXX
    if (!phone.startsWith('+880')) return false;

    // Check if remaining digits are numeric (after +880)
    final digits = phone.substring(4);
    return int.tryParse(digits) != null && digits.length >= 10;
  }

  /// Trigger SMS escalation with 5-second countdown
  Future<void> _triggerSmsEscalation(String alertId) async {
    print('🎯 _triggerSmsEscalation called for alert $alertId');
    print('   _context is null: ${_context == null}');
    print('   _context.mounted: ${_context?.mounted}');

    if (_context == null || !_context!.mounted) {
      print(
        '⚠️ No context available for countdown dialog - sending SMS directly',
      );
      await _sendSmsToProctors(alertId);
      return;
    }

    print('✅ Showing countdown dialog...');
    // Show countdown dialog
    await showDialog(
      context: _context!,
      barrierDismissible: false,
      builder: (dialogContext) => _CountdownDialog(
        alertId: alertId,
        onComplete: () async {
          print('📤 Send Now button pressed or countdown completed');
          // Don't pop here - caller handles it
          await _sendSmsToProctors(alertId);
        },
        onCancel: () {
          print('🚫 SMS escalation cancelled by user');
          // onCancel is only called after pop, so don't pop again
        },
      ),
    );
    print('✅ Dialog closed');
  }

  /// Send SMS to all proctors
  Future<void> _sendSmsToProctors(String alertId) async {
    try {
      print('📤 Sending SMS to proctors for alert $alertId');

      // Fallback phone numbers (hardcoded)
      final List<String> testPhones = ['+8801714721112', '+8801835498205'];

      List<String> proctorPhones = [];

      try {
        // Fetch all proctor and assistant proctor phone numbers from Firestore
        print('📱 Querying Firestore for proctors...');
        final proctorsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('designation', whereIn: ['Proctor', 'Assistant Proctor'])
            .get();

        // Extract phone numbers with detailed logging
        print('📋 Found ${proctorsSnapshot.docs.length} proctor documents');
        for (final doc in proctorsSnapshot.docs) {
          final data = doc.data();
          final name = data['name'] ?? 'Unknown';
          final designation = data['designation'] ?? 'Unknown';
          final phone = data['phone'] as String?;

          print('   👤 $name ($designation): ${phone ?? "NO PHONE"}');

          if (phone != null && phone.isNotEmpty) {
            proctorPhones.add(phone);
          }
        }

        if (proctorPhones.isNotEmpty) {
          print(
            '📱 Found ${proctorPhones.length} proctor phone numbers from database',
          );
          print('📱 Raw phones: $proctorPhones');
        } else {
          print('⚠️ No proctors found in database - using fallback phones');
          proctorPhones = testPhones;
        }
      } catch (e) {
        print('❌ Firestore query failed: $e - using fallback phones');
        proctorPhones = testPhones;
      }

      // Validate phone numbers with detailed logging
      print('🔍 Validating ${proctorPhones.length} phone numbers...');
      final validPhones = <String>[];
      final invalidPhones = <String>[];

      for (final phone in proctorPhones) {
        if (_isValidBDPhone(phone)) {
          validPhones.add(phone);
          print('   ✅ Valid: $phone');
        } else {
          invalidPhones.add(phone);
          print('   ❌ Invalid: $phone (missing +880 or wrong format)');
        }
      }

      if (validPhones.isEmpty) {
        print('❌ No valid phone numbers found - using emergency fallback');
        validPhones.add('+8801714721112'); // Emergency contact
      }

      print('✅ ${validPhones.length} valid, ${invalidPhones.length} invalid');
      print('📋 Final SMS recipients: $validPhones');

      // Get alert details
      final alertDoc = await FirebaseFirestore.instance
          .collection('proctorial_alerts')
          .doc(alertId)
          .get();

      if (!alertDoc.exists) {
        print('⚠️ Alert $alertId not found');
        return;
      }

      final alertData = alertDoc.data()!;
      final studentName = alertData['studentName'] ?? 'Unknown';
      final studentId = alertData['studentId'] ?? 'Unknown';
      final department = alertData['department'] ?? 'Unknown';
      final location = alertData['location'] ?? 'Unknown location';

      // Compose SMS message (plain text for native SMS)
      final smsBody =
          'EMERGENCY ALERT\n'
          'Student: $studentName\n'
          'Dept: $department\n'
          'Location: $location\n'
          'Time: ${DateTime.now().toString().substring(0, 16)}\n'
          'Open SafeLink app immediately!';

      int smsSent = 0;
      int smsFailed = 0;

      // Send SMS to all valid proctor phones
      for (final phone in validPhones) {
        try {
          // Hide last 3 digits for privacy in logs
          final maskedPhone = '${phone.substring(0, phone.length - 3)}***';
          print('📤 Sending SMS to $maskedPhone...');

          // Try native Android SMS first (silent, no user interaction)
          final success = await NativeSms.sendSMS(
            phone: phone,
            message: smsBody,
          );

          if (success) {
            smsSent++;
            print('✅ SMS sent to $maskedPhone');
          } else {
            smsFailed++;
            print('❌ SMS failed for $maskedPhone');
          }

          // Rate limiting: 500ms delay between messages
          await Future.delayed(Duration(milliseconds: 500));
        } catch (e) {
          smsFailed++;
          print('❌ Error sending SMS to phone: $e');
        }
      }

      print('📊 SMS Report: $smsSent sent, $smsFailed failed');

      // Mark alert as SMS escalated with detailed tracking
      await FirebaseFirestore.instance
          .collection('proctorial_alerts')
          .doc(alertId)
          .update({
            'smsEscalated': true,
            'smsEscalatedAt': FieldValue.serverTimestamp(),
            'smsCount': smsSent,
            'smsFailedCount': smsFailed,
            'smsRecipients': validPhones,
          });

      print('✅ SMS escalation completed: $smsSent SMS sent');
      print('📞 About to schedule call escalation...');

      // Schedule call escalation after SMS is sent
      print('📞 Scheduling call escalation for alert $alertId');
      await CallEscalationService.instance.scheduleEscalation(alertId);
      print('📞 Call escalation scheduled successfully');
    } catch (e) {
      print('❌ Error in SMS escalation: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
  }
}

/// Countdown dialog widget
class _CountdownDialog extends StatefulWidget {
  final String alertId;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  const _CountdownDialog({
    required this.alertId,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  int _countdown = AppConstants.countdown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    print('⏱️ Countdown dialog: Starting 5-second countdown');
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
        print('⏱️ Countdown: $_countdown seconds remaining');
      } else {
        print('⏱️ Countdown finished - closing dialog and sending SMS');
        timer.cancel();
        Navigator.of(context).pop(); // Pop dialog first
        widget.onComplete(); // Then send SMS
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: const [
          Icon(Icons.sms, color: Colors.orange, size: 28),
          SizedBox(width: 10),
          Text('SMS Escalation'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Alert not accepted by proctors.',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 20),
          Text(
            'Sending SMS in $_countdown seconds...',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Cancel if this is a false alarm.',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _timer?.cancel();
            Navigator.of(context).pop();
            widget.onCancel();
          },
          child: Text('Cancel', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: () {
            _timer?.cancel();
            Navigator.of(context).pop(); // Pop dialog first
            widget.onComplete(); // Then send SMS (async)
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text('Send Now'),
        ),
      ],
    );
  }
}
