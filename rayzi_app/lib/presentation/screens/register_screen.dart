import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/routes.dart';
import '../blocs/auth/auth_bloc.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20.h),
                Text('Create Account', style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.bold)),
                SizedBox(height: 8.h),
                Text('Join the community', style: TextStyle(fontSize: 16.sp, color: Colors.grey)),
                SizedBox(height: 32.h),
                CustomTextField(
                  controller: _displayNameController,
                  hint: 'Display Name',
                  prefixIcon: Icons.person_outline,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                SizedBox(height: 16.h),
                CustomTextField(
                  controller: _usernameController,
                  hint: 'Username',
                  prefixIcon: Icons.alternate_email,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                SizedBox(height: 16.h),
                CustomTextField(
                  controller: _emailController,
                  hint: 'Email',
                  prefixIcon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
                ),
                SizedBox(height: 16.h),
                CustomTextField(
                  controller: _passwordController,
                  hint: 'Password (min 6 characters)',
                  prefixIcon: Icons.lock,
                  obscureText: true,
                  validator: (v) => v != null && v.length >= 6 ? null : 'Password too short',
                ),
                SizedBox(height: 24.h),
                BlocConsumer<AuthBloc, AuthState>(
                  listener: (context, state) {
                    if (state is AuthAuthenticated) {
                      Navigator.pushReplacementNamed(context, AppRoutes.home);
                    } else if (state is AuthError) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(state.message)),
                      );
                    }
                  },
                  builder: (context, state) {
                    return CustomButton(
                      text: state is AuthLoading ? 'Creating account...' : 'Sign Up',
                      onPressed: state is AuthLoading
                        ? null
                        : () {
                            if (_formKey.currentState!.validate()) {
                              context.read<AuthBloc>().add(
                                AuthRegisterRequested(
                                  _emailController.text.trim(),
                                  _passwordController.text,
                                  _usernameController.text.trim(),
                                  _displayNameController.text.trim(),
                                ),
                              );
                            }
                          },
                    );
                  },
                ),
                SizedBox(height: 16.h),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Already have an account? Sign In'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
