import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
              'assets/intro_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),

          // LEFT SIDE AMBIENT DARKNESS (like reference image)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                    stops: const [
                      0.0,
                      0.22,
                      0.42,
                      0.70,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Dark gradient background for features only
          Positioned(
            left: 0,
            top: 420,
            width: 245,
            height: 200,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color.fromARGB(185, 0, 0, 0),
                      Color.fromARGB(120, 0, 0, 0),
                      Color.fromARGB(40, 0, 0, 0),
                      Colors.transparent,
                    ],
                    stops: [
                      0.0,
                      0.55,
                      0.82,
                      1.0,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom fade (matches reference)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.transparent,
                      Color(0x14000000),
                      Color(0x33000000),
                      Color(0x77000000),
                      Color(0xCC000000),
                      Color(0xFF000000),
                    ],
                    stops: [
                      0.00,
                      0.72,
                      0.78,
                      0.83,
                      0.87,
                      0.92,
                      0.96,
                      1.00,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom-right shadow
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.bottomRight,
                    radius: 1.25,
                    colors: [
                      Color(0xCC000000),
                      Color(0x77000000),
                      Color(0x22000000),
                      Colors.transparent,
                    ],
                    stops: [
                      0.0,
                      0.40,
                      0.72,
                      1.0,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom-left shadow
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.bottomLeft,
                    radius: 1.0,
                    colors: [
                      Color(0x88000000),
                      Color(0x33000000),
                      Colors.transparent,
                    ],
                    stops: [
                      0.0,
                      0.55,
                      1.0,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 0, right: 18),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 85),

                          // Logo, Title, Subtitle, and Red line section
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Logo with red border ring
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    width: 105,
                                    height: 105,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFFB80812),
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: ClipOval(
                                      child: Image.asset(
                                        'functions/assets/splash_logo.png',
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 22),

                                // Title - Anton font with italic skew
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Transform(
                                        alignment: Alignment.centerLeft,
                                        transform: Matrix4.skewX(-0.11),
                                        child: RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: 'FLEX\n',
                                                style: GoogleFonts.anton(
                                                  fontSize: 64,
                                                  color: Colors.white,
                                                  height: 0.95,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Transform.translate(
                                      offset: const Offset(8, -58),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Transform(
                                          alignment: Alignment.centerLeft,
                                          transform: Matrix4.skewX(-0.11),
                                          child: RichText(
                                            text: TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: 'FACILITY',
                                                  style: GoogleFonts.anton(
                                                    fontSize: 64,
                                                    color: const Color(0xFFD21A20),
                                                    height: 0.95,
                                                    letterSpacing: 1,
                                                  ),
                                                ),
                                              ],
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

                          // Move subtitle + red line + features upward together
                          Transform.translate(
                            offset: const Offset(0, -70),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Subtitle (aligned with FACILITY)
                                const Padding(
                                  padding: EdgeInsets.only(left: 22, top: 6),
                                  child: Text(
                                    'Your Personal Fitness Hub',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 8),

                                // Red line (aligned with FACILITY and subtitle)
                                Padding(
                                  padding: const EdgeInsets.only(left: 22),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      width: 50,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD1060F),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 10),

                                // Features (move down only)
                                Transform.translate(
                                  offset: const Offset(0, 15),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFeatureRow(
                                          Icons.fitness_center,
                                          'Personalized Workouts',
                                          'Plans tailored for you',
                                        ),
                                        const SizedBox(height: 2),
                                        _buildFeatureRow(
                                          Icons.trending_up,
                                          'Track Progress',
                                          'Monitor. Improve. Succeed.',
                                        ),
                                        const SizedBox(height: 2),
                                        _buildFeatureRow(
                                          Icons.favorite,
                                          'Stay Healthy',
                                          'Better habits, better you',
                                        ),
                                        const SizedBox(height: 2),
                                        _buildFeatureRow(
                                          Icons.calendar_month,
                                          'Book & Manage',
                                          'Classes, PT & more',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
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
                      const SizedBox(height: 18),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Align(
        alignment: Alignment.centerLeft,
        child: Container(
        width: 193,
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Transform.translate(
          offset: const Offset(5, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(
                  color: const Color(0xFFD21A20),
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                color: const Color(0xFFD21A20),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const FeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.55),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFD21A20),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
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