import 'package:flutter/material.dart';
import '../../config/routes/app_routes.dart';
import '../../core/widgets/back_button_widget.dart';
import '../../core/services/shake_detection_service.dart';
import 'proctor_dashboard.dart';
import 'security_dashboard.dart';
import 'controllers/alert_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _userRole;

  @override
  void initState() {
    super.initState();
    // Initialize real-time listener for alerts and notifications
    AlertController.instance.initializeRealtimeListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Get user role from route arguments
    final roleArg = ModalRoute.of(context)?.settings.arguments;
    _userRole = (roleArg is String) ? roleArg.toLowerCase() : 'student';

    print('🔍 HomeScreen didChangeDependencies called');
    print('   Role argument: $roleArg');
    print('   Detected role: $_userRole');
    print('   Is student: ${_userRole == 'student'}');
    print(
      '   Shake service already listening: ${ShakeDetectionService.instance.isListening}',
    );

    // Initialize shake detection ONLY for students (FR11, FR25)
    if (_userRole == 'student' && !ShakeDetectionService.instance.isListening) {
      print('✅ Student role confirmed - initializing shake detection');
      // Use addPostFrameCallback to ensure context is fully built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ShakeDetectionService.instance.startListening(context: context);
          print('✅ Shake detection initialized for student');
        } else {
          print('⚠️ Widget not mounted, cannot start shake detection');
        }
      });
    } else {
      print(
        '⚠️ Shake detection NOT initialized - role: $_userRole, already listening: ${ShakeDetectionService.instance.isListening}',
      );
    }
  }

  @override
  void dispose() {
    // Stop shake detection when leaving home screen
    if (_userRole == 'student') {
      ShakeDetectionService.instance.stopListening();
      print('✅ Shake detection stopped on dispose');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = _userRole ?? 'student';

    return Scaffold(
      appBar: (role == 'proctorial body' || role == 'security body')
          ? null
          : AppBar(
              title: const Text('SafeLink NSTU'),
              elevation: 0,
              leading: const BackButtonWidget(),
            ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (role == 'student') ...[
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _HomeCard(
                      icon: Icons.warning,
                      label: 'Raise SOS',
                      color: Colors.red,
                      onTap: () => Navigator.pushNamed(context, '/sos'),
                    ),
                    _HomeCard(
                      icon: Icons.history,
                      label: 'Alert History',
                      color: theme.primaryColor,
                      onTap: () {},
                    ),
                    _HomeCard(
                      icon: Icons.map,
                      label: 'Campus Map',
                      color: Colors.teal,
                      onTap: () {},
                    ),
                    _HomeCard(
                      icon: Icons.person,
                      label: 'Profile',
                      color: Colors.deepPurple,
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.login),
                    ),
                  ],
                ),
              ),
            ] else if (role == 'proctorial body') ...[
              // Use the dedicated Proctor dashboard layout
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: const ProctorDashboard(),
                ),
              ),
            ] else ...[
              // Use the dedicated Security dashboard layout
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: const SecurityDashboard(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _HomeCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withAlpha((0.1 * 255).round()),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}
