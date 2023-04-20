import 'dart:async';

import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart' as test;

/// Creates a new `riverpod`-specific test case with the given [description].
/// [providerTest] will handle asserting that the `provider` emits the
/// expected states (in order) after [act] is executed.
///
/// [setUp] is optional and should be used to set up
/// any dependencies prior to initializing the [provider] under test.
/// [setUp] should be used to set up state necessary for a particular test case.
/// For common set up code, prefer to use `setUp` from `package:test/test.dart`.
///
/// [overrides] is an object that stores the state of the providers and
/// allows overriding the behavior of a specific [provider].
///
/// [provider] should be the `provider` under test.
///
/// [fireImmediately] (false by default) can be optionally passed to tell
/// Riverpod to immediately call the listener with the current value.
///
/// [act] is an optional callback which will be invoked with the [provider]
/// under test and should be used to interact with the [provider].
///
/// [verify] is an optional callback which is invoked after [act]
/// and can be used for additional verification/assertions.
///
/// [expect] is an optional `Function` that returns a `Matcher` which the
/// [provider] under test is expected to emit after [act] is executed.
///
/// [tearDown] is optional and can be used to execute any code after the test
/// has run.
/// [tearDown] should be used to clean up after a particular test case.
/// For common tear down code, prefer to use `tearDown` from `package:test/test.dart`.
@isTest
Future<void> providerTest<T>(
  String description, {
  required ProviderListenable<T> provider,
  List<Override> overrides = const [],
  FutureOr<void> Function()? setUp,
  int skip = 0,
  bool fireImmediately = false,
  FutureOr<void> Function(ProviderContainer container)? act,
  Object Function()? expect,
  void Function(ProviderContainer container)? verify,
  FutureOr<void> Function()? tearDown,
}) async {
  // ignore: avoid-passing-async-when-sync-expected
  test.test(description, () async {
    await testProvider(
      provider: provider,
      providerOverrides: overrides,
      setUp: setUp,
      skip: skip,
      fireImmediately: fireImmediately,
      act: act,
      expect: expect,
      verify: verify,
      tearDown: tearDown,
    );
  });
}

/// Internal [testProvider] runner which is only visible for testing.
/// This should never be used directly -- please use [testProvider] instead.
@internal
Future<void> testProvider<T>({
  required ProviderListenable<T> provider,
  List<Override> providerOverrides = const [],
  FutureOr<void> Function()? setUp,
  int skip = 0,
  bool fireImmediately = false,
  FutureOr<void> Function(ProviderContainer container)? act,
  Object Function()? expect,
  void Function(ProviderContainer container)? verify,
  FutureOr<void> Function()? tearDown,
}) async {
  await setUp?.call();

  final container = _makeProviderContainer(providerOverrides);
  final states = _listenToProviderStates(
    container,
    provider,
    expect != null,
    fireImmediately,
  );

  await act?.call(container);

  if (skip > 0) states.removeRange(0, skip);
  if (expect != null) _compareStates(states, expect());

  verify?.call(container);
  await tearDown?.call();
}

List<T> _listenToProviderStates<T>(
  ProviderContainer container,
  ProviderListenable<T> provider,
  bool shouldListen,
  bool fireImmediately,
) {
  final states = <T>[];
  if (shouldListen) {
    // ignore: avoid-ignoring-return-values
    container.listen<T>(
      provider,
      (_, current) => states.add(current),
      fireImmediately: fireImmediately,
    );
  }

  return states;
}

void _compareStates<T>(List<T> states, Object expected) {
  try {
    test.expect(states, test.wrapMatcher(expected));
  } on test.TestFailure catch (error) {
    final diff = _diffMatch(expected: expected, actual: states);

    // ignore: avoid-throw-in-catch-block
    throw test.TestFailure('${error.message}\n$diff');
  }
}

ProviderContainer _makeProviderContainer([
  List<Override> overrides = const [],
]) {
  final container = ProviderContainer(overrides: overrides);
  test.addTearDown(container.dispose);

  return container;
}

String _diffMatch({required Object? expected, required Object? actual}) {
  final buffer = StringBuffer();
  final differences = diff(expected.toString(), actual.toString());

  buffer
    ..writeln('${"=" * 4} diff ${"=" * 40}')
    ..writeln()
    ..writeln(differences.toPrettyString())
    ..writeln()
    ..writeln('${"=" * 4} end diff ${"=" * 36}');

  return buffer.toString();
}

extension on List<Diff> {
  String toPrettyString() {
    String identical(String str) => '\u001b[90m$str\u001B[0m';
    String deletion(String str) => '\u001b[31m[-$str-]\u001B[0m';
    String insertion(String str) => '\u001b[32m{+$str+}\u001B[0m';

    final buffer = StringBuffer();
    for (final difference in this) {
      switch (difference.operation) {
        case DIFF_EQUAL:
          buffer.write(identical(difference.text));
          break;
        case DIFF_DELETE:
          buffer.write(deletion(difference.text));
          break;
        case DIFF_INSERT:
          buffer.write(insertion(difference.text));
          break;
      }
    }

    return buffer.toString();
  }
}
