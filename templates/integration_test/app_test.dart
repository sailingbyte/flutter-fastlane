// End-to-end smoke test. Run on a device/simulator:
//   flutter test integration_test/app_test.dart \
//     --dart-define=E2E_EMAIL=... --dart-define=E2E_PASSWORD=...
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

import 'support/app_driver.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // One testWidgets per file: the app can only be launched once per process.
  testWidgets('login and browse main tabs', (tester) async {
    final d = AppDriver(tester, binding);
    await d.launch();

    await d.waitFor(find.byType(shadcn.TextField));

    if (!AppDriver.hasCredentials) {
      return; // login screen rendered; the rest needs a test account
    }

    await d.login();
    for (final tab in ['Calendar', 'Documents', 'Knowledge Base', 'Dashboard']) {
      await d.tapText(tab);
      expect(find.text(tab), findsWidgets);
    }
  });
}
