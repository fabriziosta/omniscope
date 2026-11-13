import 'package:flutter/widgets.dart';

/// Per-tab handlers for in-tab master–detail Back (not a [Navigator] pop).
///
/// [HomeShell] consults the active tab before allowing the app to exit.
class InTabBackRegistry {
  final Map<int, VoidCallback> _byTab = {};

  void setHandler(int tabIndex, VoidCallback? handler) {
    if (handler == null) {
      _byTab.remove(tabIndex);
      return;
    }
    _byTab[tabIndex] = handler;
  }

  bool handle(int tabIndex) {
    final handler = _byTab[tabIndex];
    if (handler == null) return false;
    handler();
    return true;
  }
}

/// Provides [InTabBackRegistry] to tab roots.
class InTabBackScope extends InheritedWidget {
  const InTabBackScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final InTabBackRegistry registry;

  static InTabBackRegistry? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<InTabBackScope>()?.registry;
  }

  static InTabBackRegistry of(BuildContext context) {
    final registry = maybeOf(context);
    assert(registry != null, 'InTabBackScope not found');
    return registry!;
  }

  @override
  bool updateShouldNotify(InTabBackScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}

/// Shell tab index for the enclosing tab navigator slot.
class ShellTabIndex extends InheritedWidget {
  const ShellTabIndex({
    super.key,
    required this.index,
    required super.child,
  });

  final int index;

  static int? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellTabIndex>()?.index;
  }

  static int of(BuildContext context) {
    final index = maybeOf(context);
    assert(index != null, 'ShellTabIndex not found');
    return index!;
  }

  @override
  bool updateShouldNotify(ShellTabIndex oldWidget) => index != oldWidget.index;
}

/// Arms / clears the active tab's system-back handler while [onBack] is set.
class InTabBackEffect extends StatefulWidget {
  const InTabBackEffect({
    super.key,
    required this.onBack,
    required this.child,
  });

  /// When non-null, system back on this tab invokes this callback.
  final VoidCallback? onBack;
  final Widget child;

  @override
  State<InTabBackEffect> createState() => _InTabBackEffectState();
}

class _InTabBackEffectState extends State<InTabBackEffect> {
  InTabBackRegistry? _registry;
  int? _tabIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Optional outside HomeShell (e.g. isolated widget tests).
    _registry = InTabBackScope.maybeOf(context);
    _tabIndex = ShellTabIndex.maybeOf(context);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(InTabBackEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onBack, widget.onBack)) {
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    final registry = _registry;
    final tabIndex = _tabIndex;
    if (registry != null && tabIndex != null) {
      registry.setHandler(tabIndex, null);
    }
    super.dispose();
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final registry = _registry;
      final tabIndex = _tabIndex;
      if (registry == null || tabIndex == null) return;
      registry.setHandler(tabIndex, widget.onBack);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
