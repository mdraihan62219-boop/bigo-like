import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/routes.dart';
import '../blocs/auth/auth_bloc.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed, required this.enabled});

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: SizedBox(
        width: 20.r,
        height: 20.r,
        child: const CustomPaint(painter: _GoogleLogoPainter()),
      ),
      label: Text('Continue with Google', style: TextStyle(fontSize: 15.sp)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(color: Colors.grey.shade400),
        padding: EdgeInsets.symmetric(vertical: 12.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      ),
    );
  }
}

/// Draws the four-colour Google "G" so the app needs no bundled logo asset.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const blue = Color(0xFF4285F4);
  static const green = Color(0xFF34A853);
  static const yellow = Color(0xFFFBBC05);
  static const red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final stroke = radius * 0.42;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    Paint seg(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color;

    // Arcs measured clockwise from 3 o'clock.
    canvas.drawArc(rect, _deg(-45), _deg(90), false, seg(blue));   // right
    canvas.drawArc(rect, _deg(45), _deg(90), false, seg(green));   // bottom
    canvas.drawArc(rect, _deg(135), _deg(90), false, seg(yellow)); // left-bottom
    canvas.drawArc(rect, _deg(225), _deg(90), false, seg(red));    // top

    final bar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = blue;
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(center.dx + radius - stroke / 2, center.dy),
      bar,
    );
  }

  static double _deg(double d) => d * 3.141592653589793 / 180;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 40.h),
              Text('Welcome Back', style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              Text('Sign in to continue', style: TextStyle(fontSize: 16.sp, color: Colors.grey)),
              SizedBox(height: 40.h),
              CustomTextField(
                controller: _emailController,
                hint: 'Email',
                prefixIcon: Icons.email,
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 16.h),
              CustomTextField(
                controller: _passwordController,
                hint: 'Password',
                prefixIcon: Icons.lock,
                obscureText: true,
              ),
              SizedBox(height: 24.h),
              BlocConsumer<AuthBloc, AuthState>(
                listener: (context, state) {
                  if (state is AuthAuthenticated || state is AuthGuest) {
                    Navigator.pushReplacementNamed(context, AppRoutes.home);
                  } else if (state is AuthError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(state.message)),
                    );
                  }
                },
                builder: (context, state) {
                  return CustomButton(
                    text: state is AuthLoading ? 'Loading...' : 'Sign In',
                    onPressed: state is AuthLoading ? null : () {
                      context.read<AuthBloc>().add(
                        AuthLoginRequested(_emailController.text.trim(), _passwordController.text),
                      );
                    },
                  );
                },
              ),
              SizedBox(height: 16.h),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade600)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    child: Text('or', style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade600)),
                ],
              ),
              SizedBox(height: 16.h),
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  return _GoogleButton(
                    enabled: state is! AuthLoading,
                    onPressed: () => context.read<AuthBloc>().add(AuthGoogleRequested()),
                  );
                },
              ),
              SizedBox(height: 16.h),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.register),
                  child: const Text("Don't have an account? Sign Up"),
                ),
              ),
              SizedBox(height: 8.h),
              Center(
                child: TextButton(
                  onPressed: () => context.read<AuthBloc>().add(AuthGuestRequested()),
                  child: Text(
                    'Skip for now',
                    style: TextStyle(fontSize: 14.sp, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
