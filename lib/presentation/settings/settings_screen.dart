import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/widgets/back_button_widget.dart';
import '../../config/routes/app_routes.dart';
import '../auth/controllers/profile_controller.dart';
import '../auth/controllers/auth_controller.dart';
import '../../config/theme/theme_controller.dart';
import '../home/controllers/alert_controller.dart';
import '../../core/services/auth_state_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure latest saved profile values are available in the header
    try {
      Future.microtask(() async {
        await ProfileController.instance.loadFromPrefs();
        await ProfileController.instance.loadFromFirestore();
      });
      Future.microtask(() => ThemeController.instance.loadFromPrefs());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final role = args != null && args['role'] is String
        ? (args['role'] as String).toLowerCase()
        : 'student';
    final isProctor = role == 'proctor';
    final isSecurity = role == 'security';
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: 86,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
        ),
        leading: AppBarBackButton(
          onTap: () {
            // If user came from proctor/security roles, go back to the appropriate dashboard
            if (isProctor) {
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.home,
                arguments: 'proctorial body',
              );
              return;
            }
            if (isSecurity) {
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.home,
                arguments: 'security body',
              );
              return;
            }
            // Default behavior: pop if possible or go home
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
              return;
            }
            Navigator.pushReplacementNamed(context, AppRoutes.home);
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/splash_logo.png',
                width: 36,
                height: 36,
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Icon(
                  Icons.shield,
                  color: Color(0xFF0A73FF),
                  size: 32,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'SafeLink NSTU',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6CC6FF), Color(0xFF2D7BF2), Color(0xFF4E46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F1115) : const Color(0xFFF7F7F7),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Manage your account and preferences',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                _profileCard(
                  context,
                  isProctor: isProctor,
                  isSecurity: isSecurity,
                ),
                const SizedBox(height: 24),
                _sectionTitle('Account settings'),
                const SizedBox(height: 10),
                _settingsGroup([
                  _tile(
                    Icons.person,
                    'Profile details',
                    onTap: () {
                      if (isProctor || isSecurity) {
                        Navigator.pushNamed(context, '/staff-profile');
                      } else {
                        Navigator.pushNamed(
                          context,
                          '/edit-profile',
                          arguments: {'role': role},
                        );
                      }
                    },
                  ),
                  _tile(
                    Icons.lock,
                    'Password',
                    onTap: () => _showChangePasswordSheet(context),
                  ),
                  if (!isProctor && !isSecurity)
                    _tile(
                      Icons.notifications_active,
                      'Notifications',
                      onTap: () {},
                    ),
                  _switchTile(
                    Icons.dark_mode,
                    'Dark mode',
                    isDark,
                    (v) => ThemeController.instance.setDarkMode(v),
                  ),
                ]),
                const SizedBox(height: 18),
                _settingsGroup([
                  _tile(
                    Icons.info_outline,
                    'About application',
                    onTap: () => Navigator.pushNamed(context, '/about-app'),
                  ),
                  _tile(
                    Icons.help_outline,
                    'Help/FAQ',
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/help',
                      arguments: {'role': role},
                    ),
                  ),
                  _tile(
                    Icons.logout,
                    'Log out',
                    onTap: () => _confirmLogout(context),
                    textColor: Colors.redAccent,
                    iconColor: Colors.redAccent,
                  ),
                  _tile(
                    Icons.delete_forever,
                    'Deactivate my account',
                    onTap: () {},
                    textColor: Colors.redAccent,
                    iconColor: Colors.redAccent,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileCard(
    BuildContext context, {
    bool isProctor = false,
    bool isSecurity = false,
  }) {
    final p = ProfileController.instance;
    return Container(
      decoration: BoxDecoration(
        gradient: Theme.of(context).brightness == Brightness.dark
            ? const LinearGradient(
                colors: [Color(0xFF1E1E1E), Color(0xFF2A2A2A)],
              )
            : const LinearGradient(colors: [Colors.white, Color(0xFFF8FBFF)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF2D7BF2).withOpacity(0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D7BF2).withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: AnimatedBuilder(
        animation: p,
        builder: (context, _) {
          return Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6EB9F9), Color(0xFF2D7BF2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Icon(
                    isProctor || isSecurity ? Icons.shield : Icons.person,
                    color: const Color(0xFF2D7BF2),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: () {
                    final info = <Widget>[];
                    if (isProctor || isSecurity) {
                      // Display staff info from Firestore
                      String displayName = p.name.isNotEmpty
                          ? p.name
                          : (isProctor ? 'Proctor' : 'Security Officer');
                      String displayDesignation = p.designation.isNotEmpty
                          ? p.designation
                          : (isProctor ? 'Proctorial Body' : 'Security Body');

                      info.addAll([
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$displayDesignation • Noakhali Science & Technology University',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ]);
                    } else {
                      info.addAll([
                        Text(
                          p.name.isNotEmpty ? p.name : 'Student',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (p.studentId.trim().isNotEmpty)
                              'ID: ' + p.studentId.trim(),
                            if (p.department.trim().isNotEmpty)
                              p.department.trim(),
                          ].take(2).join(' • '),
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ]);
                    }
                    return info;
                  }(),
                ),
              ),
              if (!isProctor && !isSecurity)
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/edit-profile'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6EB9F9), Color(0xFF2D7BF2)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2D7BF2).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.edit, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'Edit',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12),
    child: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 17,
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : const Color(0xFF1A1A1A),
        letterSpacing: 0.3,
      ),
    ),
  );

  Widget _settingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.08)
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.04,
            ),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i != 0)
              Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context).dividerColor,
              ),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String title, {
    VoidCallback? onTap,
    Color? textColor,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? const Color(0xFF2D7BF2)).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: iconColor ?? const Color(0xFF2D7BF2),
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? Theme.of(context).listTileTheme.textColor,
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: 0.1,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white38
            : const Color(0xFFD1D5DB),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _switchTile(
    IconData icon,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2D7BF2).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF2D7BF2), size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).listTileTheme.textColor,
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: 0.1,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF2D7BF2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: () => onChanged(!value),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Log out'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D7BF2),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      if (!mounted) return;

      // Clear login state from SharedPreferences
      await AuthStateService.instance.clearLoginState();

      // Clear AlertController before logout
      AlertController.instance.logout();

      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logged out')));
      Navigator.pushNamedAndRemoveUntil(context, '/splash', (route) => false);
    }
  }

  Future<void> _showChangePasswordSheet(BuildContext context) async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    bool currentObscure = true;
    bool newObscure = true;
    bool confirmObscure = true;
    bool isLoading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 24,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 24,
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with icon and title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6EB9F9), Color(0xFF2D7BF2)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF2D7BF2,
                                  ).withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.lock_reset,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Change Password',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1A1A),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Keep your account secure',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white60
                                        : const Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            icon: Icon(
                              Icons.close_rounded,
                              color: isDark
                                  ? Colors.white60
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Current Password Field
                      _buildPasswordField(
                        controller: currentController,
                        label: 'Current Password',
                        hint: 'Enter your current password',
                        icon: Icons.lock_outline_rounded,
                        obscure: currentObscure,
                        onToggle: () => setModalState(
                          () => currentObscure = !currentObscure,
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Please enter your current password'
                            : null,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 18),

                      // New Password Field
                      _buildPasswordField(
                        controller: newController,
                        label: 'New Password',
                        hint: 'Minimum 6 characters',
                        icon: Icons.lock_reset_rounded,
                        obscure: newObscure,
                        onToggle: () =>
                            setModalState(() => newObscure = !newObscure),
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'Please enter a new password';
                          if (v.length < 6)
                            return 'Password must be at least 6 characters';
                          if (v == currentController.text)
                            return 'New password must be different';
                          return null;
                        },
                        isDark: isDark,
                      ),
                      const SizedBox(height: 18),

                      // Confirm Password Field
                      _buildPasswordField(
                        controller: confirmController,
                        label: 'Confirm New Password',
                        hint: 'Re-enter your new password',
                        icon: Icons.verified_user_rounded,
                        obscure: confirmObscure,
                        onToggle: () => setModalState(
                          () => confirmObscure = !confirmObscure,
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'Please confirm your new password';
                          if (v != newController.text)
                            return 'Passwords do not match';
                          return null;
                        },
                        isDark: isDark,
                      ),

                      // Password Requirements
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D7BF2).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF2D7BF2).withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: const Color(0xFF2D7BF2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Password must be at least 6 characters long',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white.withOpacity(0.8)
                                      : const Color(0xFF374151),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark
                                    ? Colors.white70
                                    : const Color(0xFF6B7280),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white24
                                      : const Color(0xFFD1D5DB),
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: isLoading
                                  ? null
                                  : () => Navigator.pop(sheetCtx),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF6EB9F9),
                                    Color(0xFF2D7BF2),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF2D7BF2,
                                    ).withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: isLoading
                                    ? null
                                    : () async {
                                        if (!(formKey.currentState
                                                ?.validate() ??
                                            false))
                                          return;

                                        setModalState(() => isLoading = true);

                                        final auth = AuthController();
                                        final current = currentController.text
                                            .trim();
                                        final nw = newController.text.trim();

                                        final ok = await auth.changePassword(
                                          current,
                                          nw,
                                        );

                                        if (!mounted) return;
                                        Navigator.pop(sheetCtx);

                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(
                                                  ok
                                                      ? Icons
                                                            .check_circle_rounded
                                                      : Icons.error_rounded,
                                                  color: Colors.white,
                                                  size: 22,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    ok
                                                        ? 'Password updated successfully!'
                                                        : 'Failed to update password. Check your current password.',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: ok
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFEF4444),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            margin: const EdgeInsets.all(16),
                                            duration: const Duration(
                                              seconds: 4,
                                            ),
                                          ),
                                        );
                                      },
                                child: isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Text(
                                        'Update Password',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool obscure,
    required VoidCallback onToggle,
    required FormFieldValidator<String> validator,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white.withOpacity(0.9)
                : const Color(0xFF374151),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : const Color(0xFF9CA3AF),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Container(
              margin: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(icon, color: const Color(0xFF2D7BF2), size: 22),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: isDark ? Colors.white38 : const Color(0xFF9CA3AF),
                size: 20,
              ),
              onPressed: onToggle,
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withOpacity(0.05)
                : const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF2D7BF2), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFEF4444),
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            errorStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}
