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
              'assets/intro_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
          ),

          // Dark gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 0, right: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  const SizedBox(height: 70),

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
                            width: 100,
                            height: 100,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color.fromARGB(255, 151, 4, 4),
                            ),
                            padding: const EdgeInsets.all(3),
                            child: ClipOval(
                              child: Image.asset(
                                'functions/assets/splash_logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Title - Proportioned
                        Align(
                          alignment: Alignment.centerLeft,
                          child: RichText(
                            text: const TextSpan(
                              children: [
                                TextSpan(
                                  text: 'FLEX\n',
                                  style: TextStyle(
                                    fontSize: 68,
                                    fontWeight: FontWeight.w900,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.white,
                                    height: 0.85,
                                    letterSpacing: -3.5,
                                  ),
                                ),
                                TextSpan(
                                  text: 'FACILITY',
                                  style: TextStyle(
                                    fontSize: 68,
                                    fontWeight: FontWeight.w900,
                                    fontStyle: FontStyle.italic,
                                    color: Color(0xffE31C23),
                                    height: 0.85,
                                    letterSpacing: -5.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Subtitle
                        Align(
                          alignment: Alignment.centerLeft,
                          child: const Text(
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

                        // Red line
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 50,
                            height: 3,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD41C1C),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Features - Tight spacing with max width to match 2nd feature
                  SizedBox(
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

                  const Spacer(),

                      ],
                    ),
                  ),
                ),
                // Full width dark background at bottom
                Container(
                  height: 215,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                        Colors.black.withValues(alpha: 0.75),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.35, 0.75, 1.0],
                    ),
                  ),
                  child: Column(
                    children: [
                      MainButton(
                        text: 'Create Account',
                        icon: Icons.person_add_alt_1,
                        color: const Color(0xFFD41C1C),
                        borderColor: const Color(0xFFD41C1C),
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
                      const SizedBox(height: 16),
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, '/login');
                          },
                          child: RichText(
                            text: TextSpan(
                              children: const [
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
    return Transform.translate(
      offset: const Offset(-9, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
                border: Border.all(
                  color: const Color(0xFFD41C1C),
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                color: const Color(0xFFD41C1C),
                size: 20,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
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
              color: const Color(0xFFD41C1C),
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
      height: 60,
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: color == Colors.transparent ? 0 : 12,
          shadowColor: const Color(0xFFD41C1C),
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
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
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