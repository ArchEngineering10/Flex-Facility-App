import 'package:flutter/material.dart';

void main() {
  runApp(const FlexFacilityApp());
}

class FlexFacilityApp extends StatelessWidget {
  const FlexFacilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FlexWelcomeScreen(),
    );
  }
}


class FlexWelcomeScreen extends StatelessWidget {
  const FlexWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/intro.png',
              fit: BoxFit.cover,
            ),
          ),


          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MainButton(
                        text: 'Create Account',
                        icon: Icons.person_add_alt_1,
                        color: const Color(0xFFD1060F),
                        borderColor: const Color(0xFFD1060F),
                        onTap: () {
                          Navigator.pushNamed(context, '/signup');
                        },
                      ),
                      const SizedBox(height: 12),
                      MainButton(
                        text: 'Log In',
                        icon: Icons.login,
                        color: Colors.transparent,
                        borderColor: Colors.white,
                        onTap: () {
                          Navigator.pushNamed(context, '/login');
                        },
                      ),
                      const SizedBox(height: 25),
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, '/login');
                          },
                          child: RichText(
                            text: const TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Already a member? ',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Log in',
                                  style: TextStyle(
                                    color: Color(0xFFD41C1C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: ' to continue',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
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
      );
    }
  }

class MainButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Color borderColor;
  final VoidCallback onTap;

  const MainButton({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: color == Colors.transparent ? 0 : 12,
          shadowColor: const Color(0xFFD1060F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(40),
            side: BorderSide(
              color: borderColor,
              width: 1.5,
            ),
          ),
        ),
        onPressed: onTap,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(icon, color: Colors.white, size: 24),
            const Spacer(),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFFF7F7F7),
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}