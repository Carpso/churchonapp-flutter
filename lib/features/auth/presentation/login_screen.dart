import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/widgets/google_g_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _rememberMe = true;
  bool _isGoogleLoading = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('remembered_email') ?? '';
      if (email.isNotEmpty && mounted) {
        setState(() {
          _emailController.text = email;
          _rememberMe = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading remembered email: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final email = _emailController.text.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', _rememberMe);
      if (_rememberMe) {
        await prefs.setString('remembered_email', email);
      } else {
        await prefs.remove('remembered_email');
      }

      await ref
          .read(authProvider.notifier)
          .signIn(email, _passwordController.text.trim());

      final authState = ref.read(authProvider);
      if (authState.errorMessage != null && mounted) {
        showAppSnackBar(
          context,
          authState.errorMessage ?? 'Authentication failed',
          status: AppStatus.error,
        );
      } else if (mounted && authState.user != null) {
        showAppSnackBar(
          context,
          "Signed in successfully!",
          status: AppStatus.success,
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      await ref.read(authProvider.notifier).signInWithGoogle();
      if (mounted && ref.read(authProvider).user != null) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          AppErrorView.friendlyMessage(e),
          status: AppStatus.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _handleForgotPassword() {
    context.push('/forgot-password');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Theme(
      data: AppTheme.getTheme(null),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.all(30.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Welcome Back",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Sign in to continue your spiritual journey.",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.neutral,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildTextField(
                      controller: _emailController,
                      label: "Email Address",
                      icon: LucideIcons.mail,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final emailRegex = RegExp(
                          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                        );
                        final phoneClean = v.replaceAll(RegExp(r'\D'), '');
                        final isPhone =
                            phoneClean.length >= 9 && phoneClean.length <= 12;
                        if (!emailRegex.hasMatch(v) && !isPhone) {
                          return 'Enter a valid email or phone';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _passwordController,
                      label: "Password",
                      icon: LucideIcons.lock,
                      isPassword: true,
                      autofillHints: const [AutofillHints.password],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (v.length < 6) return 'Min 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _rememberMe,
                            onChanged: (v) =>
                                setState(() => _rememberMe = v ?? true),
                            activeColor: Theme.of(context).primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Remember me",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.neutral,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _handleForgotPassword,
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    authState.isLoading
                        ? Center(
                            child: CircularProgressIndicator(
                              color: Theme.of(context).primaryColor,
                            ),
                          )
                        : ElevatedButton(
                            onPressed: _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              minimumSize: const Size(double.infinity, 60),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: const Text(
                              "SIGN IN",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: Text(
                            "OR",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.neutral,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 30),
                    _buildSocialButton(
                      "Continue with Google",
                      _isGoogleLoading,
                      _handleGoogleSignIn,
                    ),
                    const SizedBox(height: 30),
                    Center(
                      child: TextButton(
                        onPressed: () => context.push(
                          '/signup',
                        ), // Assuming /signup will be added to router
                        child: RichText(
                          text: TextSpan(
                            text: "New here? ",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.neutral,
                            ),
                            children: [
                              TextSpan(
                                text: "Create an account",
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(80)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 100,
            left: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Icon(
                    LucideIcons.church,
                    color: Theme.of(context).primaryColor,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Church On App",
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<String>? autofillHints,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.onSurface.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword && !_isPasswordVisible,
        validator: validator,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        decoration: InputDecoration(
          icon: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          labelText: label,
          labelStyle: TextStyle(color: scheme.neutral, fontSize: 14),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _isPasswordVisible ? LucideIcons.eye : LucideIcons.eyeOff,
                    color: scheme.neutral,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _isPasswordVisible = !_isPasswordVisible),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildSocialButton(
    String label,
    bool isLoading,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return ElevatedButton(
      onPressed: isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(double.infinity, 60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        elevation: 0.5,
      ),
      child: isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.neutral,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const GoogleGLogo(size: 22),
                const SizedBox(width: 15),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 0.2,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
    );
  }
}
