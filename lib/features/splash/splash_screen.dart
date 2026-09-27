import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "WhatsPlaying" inside a slowly turning dotted ring, as sketched. Doubles as the error screen
/// when there are no listings at all (first run, offline).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.error, this.onRetry});

  final String? error;
  final VoidCallback? onRetry;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.error == null)
                    RotationTransition(
                      turns: _spin,
                      child: CustomPaint(size: const Size.square(260), painter: _DottedRing(scheme.primary)),
                    ),
                  Text(
                    'WhatsPlaying',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.error != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                child: Text(
                  "Couldn't get the listings. Check your connection and try again.\n\n${widget.error}",
                  textAlign: TextAlign.center,
                ),
              ),
              FilledButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DottedRing extends CustomPainter {
  _DottedRing(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dots = 28;
    final r = size.width / 2 - 6;
    final c = size.center(Offset.zero);
    for (var i = 0; i < dots; i++) {
      final a = 2 * math.pi * i / dots;
      final paint = Paint()..color = color.withValues(alpha: 0.25 + 0.75 * i / dots);
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, 3, paint);
    }
  }

  @override
  bool shouldRepaint(_DottedRing old) => old.color != color;
}
