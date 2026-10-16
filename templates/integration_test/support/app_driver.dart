// TEMPLATE: replace `your_app` with the pubspec name; the finders below target a shadcn_flutter
// login screen (two TextFields + PrimaryButton "Login") - adapt them to your UI or add Keys.
// Reusable helpers for integration tests and store screenshots.
//
// Credentials/test config come from --dart-define. fastlane forwards every
// E2E_* environment variable automatically (E2E_EMAIL, E2E_PASSWORD, ...).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:your_app/main.dart' as app;
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

class AppDriver {
  AppDriver(this.tester, this.binding);

  final WidgetTester tester;
  final IntegrationTestWidgetsFlutterBinding binding;

  static const email = String.fromEnvironment('E2E_EMAIL');
  static const password = String.fromEnvironment('E2E_PASSWORD');
  static bool get hasCredentials => email.isNotEmpty && password.isNotEmpty;

  var _surfaceConverted = false;

  /// Starts the real app. Call once per test file - `main()` initialises
  /// global services and cannot be started twice in one process.
  Future<void> launch() async {
    app.main();
    await tester.pump(const Duration(seconds: 2));
  }

  /// Pumps frames until [finder] matches. Prefer this to `pumpAndSettle`,
  /// which never returns while a spinner/animation is running.
  Future<void> waitFor(
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('Timed out waiting for $finder');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitForGone(
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw TestFailure('Timed out waiting for $finder to disappear');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tap(Finder finder) async {
    await waitFor(finder);
    await tester.tap(finder.first);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapText(String text) => tap(find.text(text));

  Future<void> enterText(Finder finder, String text) async {
    await waitFor(finder);
    await tester.enterText(finder.first, text);
    await tester.pump();
  }

  /// Logs in through the login screen. No-op when a session already exists.
  Future<void> login() async {
    if (!hasCredentials) {
      throw TestFailure('Set E2E_EMAIL and E2E_PASSWORD (--dart-define)');
    }
    final fields = find.byType(shadcn.TextField);
    try {
      await waitFor(fields, timeout: const Duration(seconds: 8));
    } on TestFailure {
      return; // no login form -> already signed in
    }
    await enterText(fields.at(0), email);
    await enterText(fields.at(1), password);
    await tap(find.widgetWithText(shadcn.PrimaryButton, 'Login'));
    await waitForGone(find.byType(shadcn.TextField));
    await tester.pump(const Duration(seconds: 2)); // let the first screen load
  }

  /// Scrolls until [finder] is visible (inside the first Scrollable).
  Future<void> scrollTo(Finder finder) async {
    await tester.scrollUntilVisible(finder, 300);
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Takes a screenshot. With `flutter drive` the driver saves it to
  /// $SCREENSHOT_DIR/NAME.png (see test_driver/integration_test.dart).
  Future<void> screenshot(String name) async {
    if (Platform.isAndroid && !_surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      _surfaceConverted = true;
    }
    await tester.pump(const Duration(milliseconds: 500));
    await binding.takeScreenshot(name);
  }
}
