import 'package:flutter/material.dart';

/// Pulsation discrète (échelle + opacité) tant que [active] est vrai.
/// Désactivée si l'utilisateur a demandé à réduire les animations.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child, this.active = true});

  final Widget child;
  final bool active;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.active && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: 1 - 0.25 * _curve.value,
        child: Transform.scale(scale: 1 + 0.06 * _curve.value, child: child),
      ),
      child: widget.child,
    );
  }
}
