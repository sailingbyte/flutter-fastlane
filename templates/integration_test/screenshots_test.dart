// Store screenshot flow, run by `fastlane <platform> screenshots|release`
// (when SCREENSHOTS_ENABLED=true) via `flutter drive`. Each takeScreenshot
// name becomes a file; keep them numbered so store ordering is stable.
// Needs E2E_EMAIL / E2E_PASSWORD of a demo account with good-looking data.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/app_driver.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    final d = AppDriver(tester, binding);
    await d.launch();
    await d.login();

    await d.screenshot('01_dashboard');

    await d.tapText('Calendar');
    await d.screenshot('02_calendar');

    await d.tapText('Documents');
    await d.screenshot('03_documents');

    await d.tapText('Knowledge Base');
    await d.screenshot('04_knowledge_base');
  });
}
