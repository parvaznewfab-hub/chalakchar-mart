import 'package:chalakchar_mart/services/app_settings_service.dart';
import 'package:chalakchar_mart/utils/category_kind.dart';
import 'package:chalakchar_mart/widgets/health_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Health features off (Play Store Health apps declaration): flags default off,
// doctor/appointment/prescription routes go home, gated UI is hidden.
void main() {
  group('settings flags', () {
    test('absent features = everything off', () {
      final s = AppSettings.fromMap(const {});
      expect(s.healthEnabled, isFalse);
      expect(s.listOrderEnabled, isFalse);
      expect(featureEnabled(s, Feature.health), isFalse);
      expect(featureEnabled(s, Feature.listOrder), isFalse);
    });

    test('flags are read from settings/app.features and are reversible', () {
      final on = AppSettings.fromMap(const {'features': {'healthEnabled': true}});
      expect(featureEnabled(on, Feature.health), isTrue);
      // List orders come back with health features too.
      expect(featureEnabled(on, Feature.listOrder), isTrue);

      final listsOnly = AppSettings.fromMap(const {'features': {'listOrderEnabled': true}});
      expect(featureEnabled(listsOnly, Feature.health), isFalse);
      expect(featureEnabled(listsOnly, Feature.listOrder), isTrue);
    });
  });

  group('health routes', () {
    test('doctor / appointment / prescription paths are health routes', () {
      for (final r in [
        '/doctors',
        '/doctor/abc',
        '/appointments',
        '/my-appointments',
        '/consult-doctor?x=1',
        '/prescription',
      ]) {
        expect(HealthFeatures.isHealthRoute(r), isTrue, reason: r);
      }
      for (final r in ['/', '/product/abc', '/category/mobile-parts', '/cart', '/doctorwho']) {
        expect(HealthFeatures.isHealthRoute(r), isFalse, reason: r);
      }
    });

    testWidgets('a health route opens the home page with "/" when the flag is off',
        (tester) async {
      String? shownRoute;
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (settings) {
          // Same rule as main.dart's onGenerateRoute.
          if (!HealthFeatures.enabled && HealthFeatures.isHealthRoute(settings.name)) {
            return MaterialPageRoute(
              settings: const RouteSettings(name: '/'),
              builder: (_) => const Text('HOME'),
            );
          }
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => Text('PAGE ${settings.name}'),
          );
        },
        navigatorObservers: [_NameObserver((n) => shownRoute = n)],
        initialRoute: '/doctors',
      ));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsWidgets);
      expect(find.textContaining('PAGE /doctors'), findsNothing);
      expect(shownRoute, '/');
    });
  });

  testWidgets('HealthGate hides health UI by default and shows the fallback', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(children: [
        HealthGate(child: Text('Consult Doctor')),
        HealthGate(feature: Feature.listOrder, child: Text('Order with List')),
        HealthGate(fallback: Text('Parts FAQ'), child: Text('Medicine FAQ')),
      ]),
    ));
    await tester.pump();
    expect(find.text('Consult Doctor'), findsNothing);
    expect(find.text('Order with List'), findsNothing);
    expect(find.text('Medicine FAQ'), findsNothing);
    expect(find.text('Parts FAQ'), findsOneWidget);
  });

  test('electronics categories hide Generic/Strength/Type in the admin form (E4)', () {
    for (final c in ['Mobile Parts', 'Motherboard', 'Computer Accessories', 'Storage Devices']) {
      expect(isElectronicsCategory(c), isTrue, reason: c);
    }
    for (final c in ['Cooking', 'Grocery', 'Home & Cleaning', '', null]) {
      expect(isElectronicsCategory(c), isFalse, reason: '$c');
    }
  });
}

class _NameObserver extends NavigatorObserver {
  _NameObserver(this.onName);
  final void Function(String?) onName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => onName(route.settings.name);
}
