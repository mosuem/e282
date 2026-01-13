// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';

/// ANSI color codes
const String reset = '\x1B[0m';
const String red = '\x1B[31m';
const String green = '\x1B[32m';
const String yellow = '\x1B[33m';
const String cyan = '\x1B[36m';
const String bold = '\x1B[1m';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show detailed execution output.',
    )
    ..addOption(
      'directory',
      abbr: 'd',
      help: 'The directory to scan for Dart files.',
      defaultsTo: '.',
    );

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print('${red}Error: ${e.toString()}$reset');
    print(parser.usage);
    exit(1);
  }

  if (results['help'] as bool) {
    print('${bold}Usage: dart e282.dart [options] [directory]$reset');
    print(parser.usage);
    return;
  }

  final verbose = results['verbose'] as bool;
  final localDirectoryPath = results.rest.isNotEmpty
      ? results.rest.first
      : results['directory'] as String;

  final targetDir = Directory(localDirectoryPath);
  if (!targetDir.existsSync()) {
    print('${red}Error: Directory not found: $localDirectoryPath$reset');
    exit(1);
  }

  print(
    '${bold}Scanning ${targetDir.path} for documentation examples...$reset\n',
  );

  final localTempDir = Directory.fromUri(
    targetDir.uri.resolve('doc_test_temp/'),
  );
  if (!localTempDir.existsSync()) {
    localTempDir.createSync(recursive: true);
  }

  var totalFound = 0;
  var passed = 0;
  var failed = 0;

  final codeBlockRegex = RegExp(r'```(.*?)```', dotAll: true);
  final docCommentPrefixRegex = RegExp(r'^\s*/// ?', multiLine: true);

  try {
    await for (final entity in targetDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.dart')) {
        if (entity.path.contains('doc_test_temp')) continue;

        final content = await entity.readAsString();
        final matches = codeBlockRegex.allMatches(content);

        for (final match in matches) {
          var codeBlock = match.group(1) ?? '';
          final sourceLocation = _calculateLocation(
            entity.path,
            content,
            match.start,
          );

          codeBlock = codeBlock.replaceAll(docCommentPrefixRegex, '').trim();

          if (codeBlock.startsWith('dart')) {
            codeBlock = codeBlock.substring(4).trim();
          }

          if (codeBlock.contains('main(')) {
            totalFound++;
            final filename = entity.uri.pathSegments.last;
            final codeWithLocation = '// Source: $sourceLocation\n\n$codeBlock';

            if (verbose) {
              print('$cyan--- Found example at $sourceLocation ---$reset');
              print(codeBlock);
              print('$cyan----------------------------------$reset');
              stdout.write('Running... ');
            } else {
              stdout.write('Running example found in $filename... ');
            }

            final success = await _runSnippet(
              codeWithLocation,
              localTempDir,
              verbose: verbose,
            );

            if (success) {
              print('${green}PASS$reset');
              passed++;
            } else {
              print('${red}FAIL$reset');
              print('       ${red}Source: $sourceLocation$reset');
              failed++;
            }
            if (verbose) {
              print('');
            }
          }
        }
      }
    }
  } finally {
    if (localTempDir.existsSync() & localTempDir.listSync().isEmpty) {
      localTempDir.deleteSync();
    }
  }

  print('\n$bold--- Report ---$reset');
  print('Total Examples Found: $totalFound');
  print('Passed: $green$passed$reset');
  print('Failed: $red$failed$reset');

  if (failed > 0) {
    exit(1);
  }
}

String _calculateLocation(String filePath, String content, int index) {
  final prefix = content.substring(0, index);
  final line = RegExp(r'\n').allMatches(prefix).length + 1;

  final lastNewLine = prefix.lastIndexOf('\n');
  final col = index - (lastNewLine == -1 ? 0 : lastNewLine);

  return '$filePath:$line:$col';
}

Future<bool> _runSnippet(
  String code,
  Directory tempDir, {
  required bool verbose,
}) async {
  final uniqueId = DateTime.now().microsecondsSinceEpoch;
  final tempFile = File('${tempDir.path}test_example_$uniqueId.dart');

  try {
    await tempFile.writeAsString(code);

    if (verbose) {
      print('Run dart analyze ${tempFile.path}');
    }

    final result = await Process.run('dart', ['analyze', tempFile.path]);

    if (result.exitCode != 0) {
      if (!verbose) print('');
      print('$yellow--- Error (Stderr) ---$reset');
      print(result.stderr);
      print('$yellow-----------------------$reset');
      return false;
    }

    if (verbose && result.stdout.toString().isNotEmpty) {
      print('\n$cyan--- Output (Stdout) ---$reset');
      print(result.stdout.toString().trim());
      print('$cyan-----------------------$reset');
    }

    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    return true;
  } catch (e) {
    print('\n${red}Execution Error: $e$reset');
    return false;
  }
}
