// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../utils.dart';

void main() {
  compileFormatter();

  test('no options search if experiment is off', () async {
    await d.dir('foo', [
      analysisOptionsFile(pageWidth: 20),
      d.file('main.dart', _unformatted),
    ]).create();

    var process = await runFormatterOnDir();
    await process.shouldExit(0);

    // Should format the file at the default width.
    await d.dir('foo', [d.file('main.dart', _formatted80)]).validate();
  });

  test('no options search if page width is specified on the CLI', () async {
    await d.dir('foo', [
      analysisOptionsFile(pageWidth: 20),
      d.file('main.dart', _unformatted),
    ]).create();

    var process = await runFormatterOnDir([
      '--language-version=latest', // Error to not have language version.
      '--line-length=30',
      '--enable-experiment=tall-style'
    ]);
    await process.shouldExit(0);

    // Should format the file at 30, not 20 or 80.
    await d.dir('foo', [d.file('main.dart', _formatted30)]).validate();
  });

  test('default to page width of surrounding options', () async {
    await _testWithOptions(
      {
        'formatter': {'page_width': 20}
      },
      expectedWidth: 20,
    );
  });

  test('use default page width on invalid analysis options', () async {
    await _testWithOptions({'unrelated': 'stuff'}, expectedWidth: 80);
    await _testWithOptions({'formatter': 'not a map'}, expectedWidth: 80);
    await _testWithOptions({
      'formatter': {'no': 'page_width'}
    }, expectedWidth: 80);
    await _testWithOptions(
      {
        'formatter': {'page_width': 'not an int'}
      },
      expectedWidth: 80,
    );
  });

  test('get page width from included options file', () async {
    await d.dir('foo', [
      analysisOptionsFile(include: 'other.yaml'),
      analysisOptionsFile(name: 'other.yaml', include: 'sub/third.yaml'),
      d.dir('sub', [
        analysisOptionsFile(name: 'third.yaml', pageWidth: 30),
      ]),
      d.file('main.dart', _unformatted),
    ]).create();

    var process = await runFormatterOnDir([
      '--language-version=latest', // Error to not have language version.
      '--enable-experiment=tall-style'
    ]);
    await process.shouldExit(0);

    // Should format the file at 30.
    await d.dir('foo', [d.file('main.dart', _formatted30)]).validate();
  });

  test('resolve "package:" includes', () async {
    await d.dir('dir', [
      d.dir('foo', [
        packageConfig('foo', packages: {
          'bar': '../../bar',
          'baz': '../../baz',
        }),
        analysisOptionsFile(include: 'package:bar/analysis_options.yaml'),
        d.file('main.dart', _unformatted),
      ]),
      d.dir('bar', [
        d.dir('lib', [
          analysisOptionsFile(include: 'package:baz/analysis_options.yaml'),
        ]),
      ]),
      d.dir('baz', [
        d.dir('lib', [
          analysisOptionsFile(pageWidth: 30),
        ]),
      ]),
    ]).create();

    var process = await runFormatterOnDir([
      '--language-version=latest', // Error to not have language version.
      '--enable-experiment=tall-style'
    ]);
    await process.shouldExit(0);

    // Should format the file at 30.
    await d.dir('dir', [
      d.dir('foo', [d.file('main.dart', _formatted30)])
    ]).validate();
  });

  test('ignore "package:" resolution errors', () async {
    await d.dir('dir', [
      d.dir('foo', [
        packageConfig('foo', packages: {
          'bar': '../../bar',
        }),
        analysisOptionsFile(include: 'package:not_bar/analysis_options.yaml'),
        d.file('main.dart', _unformatted),
      ]),
    ]).create();

    var process = await runFormatterOnDir([
      '--language-version=latest', // Error to not have language version.
      '--enable-experiment=tall-style'
    ]);
    await process.shouldExit(0);

    // Should format the file at 80.
    await d.dir('dir', [
      d.dir('foo', [d.file('main.dart', _formatted80)])
    ]).validate();
  });

  group('stdin', () {
    test('use page width from surrounding package', () async {
      await d.dir('foo', [
        analysisOptionsFile(pageWidth: 30),
      ]).create();

      var process = await runFormatter([
        '--language-version=latest', // Error to not have language version.
        '--enable-experiment=tall-style',
        '--stdin-name=foo/main.dart',
      ]);

      process.stdin.writeln(_unformatted);
      await process.stdin.close();

      // Formats at page width 30.
      expect(await process.stdout.next, 'var x =');
      expect(await process.stdout.next, '    operand +');
      expect(await process.stdout.next, '    another * andAnother;');
      await process.shouldExit(0);
    });

    test('no options search if page width is specified', () async {
      await d.dir('foo', [
        analysisOptionsFile(pageWidth: 20),
        d.file('main.dart', _unformatted),
      ]).create();

      var process = await runFormatter([
        '--language-version=latest',
        '--enable-experiment=tall-style',
        '--line-length=30',
        '--stdin-name=foo/main.dart'
      ]);

      process.stdin.writeln(_unformatted);
      await process.stdin.close();

      // Formats at page width 30, not 20.
      expect(await process.stdout.next, 'var x =');
      expect(await process.stdout.next, '    operand +');
      expect(await process.stdout.next, '    another * andAnother;');
      await process.shouldExit(0);
    });
  });
}

const _unformatted = '''
var x=operand+another*andAnother;
''';

const _formatted20 = '''
var x =
    operand +
    another *
        andAnother;
''';

const _formatted30 = '''
var x =
    operand +
    another * andAnother;
''';

const _formatted80 = '''
var x = operand + another * andAnother;
''';

/// Test that formatting a file with surrounding analysis_options.yaml
/// containing [options] formats the input with a page width of [expectedWidth].
Future<void> _testWithOptions(Object? options,
    {required int expectedWidth}) async {
  var expected = switch (expectedWidth) {
    20 => _formatted20,
    30 => _formatted30,
    80 => _formatted80,
    _ => throw ArgumentError('Expected width must be 20, 30, or 80.'),
  };

  await d.dir('foo', [
    d.FileDescriptor('analysis_options.yaml', jsonEncode(options)),
    d.file('main.dart', _unformatted),
  ]).create();

  var process = await runFormatterOnDir([
    '--language-version=latest', // Error to not have language version.
    '--enable-experiment=tall-style'
  ]);
  await process.shouldExit(0);

  // Should format the file at the expected width.
  await d.dir('foo', [d.file('main.dart', expected)]).validate();
}