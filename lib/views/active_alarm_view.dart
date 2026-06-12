import 'package:flutter/material.dart';
import '../models/alarm_event.dart';
import '../theme/cce_tokens.dart';

class ActiveAlarmView extends StatefulWidget {
  final AlarmEvent event;
  final VoidCallback onDismiss;

  const ActiveAlarmView({
    super.key,
    required this.event,
    required this.onDismiss,
  });

  @override
  State<ActiveAlarmView> createState() => _ActiveAlarmViewState();
}

class _ActiveAlarmViewState extends State<ActiveAlarmView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
        return Scaffold(
          backgroundColor:
              Color.lerp(const Color(0xFF8B0000), const Color(0xFFFF0000), _pulseAnimation.value),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: EdgeInsets.all(isTablet ? 48 : 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: isTablet ? 150 : 100,
                        color: Colors.white.withValues(alpha: _pulseAnimation.value),
                      ),
                      SizedBox(height: isTablet ? 32 : 24),
                      Text(
                        widget.event.automationName,
                        style: CceText.display.copyWith(
                          fontSize: isTablet ? 40 : 28,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isTablet ? 20 : 16),
                      Text(
                        widget.event.message,
                        style: CceText.body.copyWith(
                          color: CceColors.textSecondary,
                          fontSize: isTablet ? 24 : 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isTablet ? 64 : 48),
                      SizedBox(
                        width: double.infinity,
                        height: isTablet ? 80 : 64,
                        child: ElevatedButton(
                          onPressed: widget.onDismiss,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF8B0000),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(CceRadii.control),
                            ),
                          ),
                          child: Text(
                            'DESACTIVAR ALARMA',
                            style: TextStyle(
                              fontSize: isTablet ? 24 : 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
