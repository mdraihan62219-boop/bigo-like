import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/routes.dart';
import '../blocs/auth/auth_bloc.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';

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
