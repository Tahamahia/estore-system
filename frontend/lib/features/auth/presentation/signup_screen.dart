import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/api_client.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Plain Dio — no auth headers, public endpoint
  final _dio = Dio(BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _submitted = false;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    _dio.close();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'يرجى ملء جميع الحقول');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _dio.post('/auth/signup', data: {
        'full_name': name,
        'email': email,
        'password': password,
      });
      if (mounted) setState(() => _submitted = true);
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map
          ? (data['message'] as String? ?? 'فشل إرسال الطلب')
          : 'فشل إرسال الطلب';
      setState(() => _errorMessage = msg);
    } catch (e) {
      setState(() => _errorMessage = 'فشل إرسال الطلب');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.darkBg, Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B1A2A),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: const Color(0xFF6B1A2A).withValues(alpha: 0.5),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        )],
                      ),
                      child: ClipOval(child: Image.asset(
                        'assets/images/mukhmal-logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text('م', style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
                        ),
                      )),
                    ),
                    const SizedBox(height: 32),
                    Text('مخمل',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('طلب الانضمام',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54),
                    ),
                    const SizedBox(height: 40),

                    if (_submitted)
                      _buildSuccessCard()
                    else
                      _buildForm(),

                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text(
                        'لديك حساب بالفعل؟ تسجيل الدخول',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 48),
        const SizedBox(height: 16),
        const Text(
          '✅ تم إرسال طلبك. انتظر موافقة المدير قبل تسجيل الدخول.',
          style: TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () => context.go('/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('العودة لتسجيل الدخول', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.darkBorder.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_errorMessage!, style: const TextStyle(color: AppTheme.error, fontSize: 13))),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'الاسم الكامل',
            prefixIcon: Icon(Icons.person_outline),
          ),
          onSubmitted: (_) => _handleSignup(),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'الإيميل',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          onSubmitted: (_) => _handleSignup(),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'كلمة المرور',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onSubmitted: (_) => _handleSignup(),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleSignup,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isLoading
                ? const SizedBox(width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('طلب الانضمام', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}
