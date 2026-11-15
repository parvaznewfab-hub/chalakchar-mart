import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';

/// Optional features switched in settings/app.features; both off by default.
///
/// - health: doctors, appointments, prescription/medicine features.
///   ChalakChar Mart provides no health features (Play Store Health apps
///   declaration).
/// - listOrder: "Order with List" (photo of a list -> admin builds the
///   order). Built for prescription lists; kept for a future parts
///   bulk-order use. Also shown while health is on.
///
/// Nothing is deleted — turning a flag on brings everything back.
enum Feature { health, listOrder }

bool featureEnabled(AppSettings settings, Feature feature) {
  switch (feature) {
    case Feature.health:
      return settings.healthEnabled;
    case Feature.listOrder:
      return settings.listOrderEnabled || settings.healthEnabled;
  }
}

class HealthFeatures {
  HealthFeatures._();

  /// Current value (false until settings load, and when the flag is absent).
  static bool get enabled => featureEnabled(AppSettingsService.cached, Feature.health);

  static bool get listOrderEnabled => featureEnabled(AppSettingsService.cached, Feature.listOrder);

  /// Named routes that only exist for health features; with the flag off a
  /// direct URL to them lands on the home page instead.
  static const Set<String> routes = {
    '/doctors',
    '/doctor',
    '/doctor-departments',
    '/consult-doctor',
    '/appointments',
    '/my-appointments',
    '/prescription',
    '/prescriptions',
  };

  static bool isHealthRoute(String? name) {
    final path = Uri.tryParse(name ?? '')?.path ?? '';
    return routes.contains(path) || routes.any((r) => path.startsWith('$r/'));
  }

  /// Opens a page of [feature] only while it is enabled; otherwise goes home.
  static void open(BuildContext context, Widget page, {Feature feature = Feature.health}) {
    if (!featureEnabled(AppSettingsService.cached, feature)) {
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/', (route) => false);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

/// Shows [child] only while [feature] is enabled; [fallback] (default:
/// nothing) otherwise. Rebuilds when the setting changes.
class HealthGate extends StatelessWidget {
  const HealthGate({
    super.key,
    required this.child,
    this.fallback,
    this.feature = Feature.health,
  });

  final Widget child;
  final Widget? fallback;
  final Feature feature;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.watch(),
      initialData: AppSettingsService.cached,
      builder: (context, snap) {
        final settings = snap.data ?? AppSettingsService.cached;
        return featureEnabled(settings, feature) ? child : (fallback ?? const SizedBox.shrink());
      },
    );
  }
}

/// [builder] gets the current settings; for places that drop entries from a
/// list (menus, card rows) rather than wrapping one widget.
class FeatureSettingsBuilder extends StatelessWidget {
  const FeatureSettingsBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppSettings settings) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.watch(),
      initialData: AppSettingsService.cached,
      builder: (context, snap) => builder(context, snap.data ?? AppSettingsService.cached),
    );
  }
}
