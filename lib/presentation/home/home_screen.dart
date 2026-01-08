import 'package:flutter/material.dart';
import '../../config/routes/app_routes.dart';
import '../../core/widgets/back_button_widget.dart';
import 'proctor_dashboard.dart';
import 'security_dashboard.dart';
import 'controllers/alert_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize real-time listener for alerts and notifications
    AlertController.instance.initializeRealtimeListener();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleArg = ModalRoute.of(context)?.settings.arguments;
    final role = (roleArg is String) ? roleArg.toLowerCase() : 'student';
    
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
                    _HomeCard(icon: Icons.warning, label: 'Raise SOS', color: Colors.red, onTap: () => Navigator.pushNamed(context, '/sos')),
                    _HomeCard(icon: Icons.history, label: 'Alert History', color: theme.primaryColor, onTap: () {}),
                    _HomeCard(icon: Icons.map, label: 'Campus Map', color: Colors.teal, onTap: () {}),
                    _HomeCard(icon: Icons.person, label: 'Profile', color: Colors.deepPurple, onTap: () => Navigator.pushNamed(context, AppRoutes.login)),
                  ],
                ),
              ),
            ] else if (role == 'proctorial body') ...[
              // Use the dedicated Proctor dashboard layout
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 8.0), child: const ProctorDashboard()))
            ] else ...[
              // Use the dedicated Security dashboard layout
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 8.0), child: const SecurityDashboard()))
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

  const _HomeCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircleAvatar(backgroundColor: color.withAlpha((0.1 * 255).round()), child: Icon(icon, color: color)),
              const SizedBox(height: 12),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
    }
