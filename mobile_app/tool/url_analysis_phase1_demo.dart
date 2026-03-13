// Simple console demo for the 50% URL analysis implementation.
//
// Run from the `mobile_app` directory with:
//   dart run tool/url_analysis_phase1_demo.dart

import 'dart:io';

import 'package:phishing_detector/services/url_analysis_phase1.dart';

Future<void> main() async {
  final samplePayloads = <String>[
    'Visit our site: https://example.com/path?b=2&a=1',
    'Scan to open www.google.com/maps?x=1',
    'This QR does not contain any link.',
  ];

  for (final payload in samplePayloads) {
    stdout.writeln('==============================');
    stdout.writeln('QR payload: $payload');

    final prep = await prepareUrlFromQrPayload(payload);

    stdout.writeln('Extracted URL    : ${prep.extractedUrl}');
    stdout.writeln('Validated URI    : ${prep.validatedUri}');
    stdout.writeln('Expanded URI     : ${prep.expandedUri}');
    stdout.writeln('Normalized URI   : ${prep.normalizedUri}');

    if (prep.normalizedUri != null) {
      final analysis =
          await analyzeDomainAndNetwork(prep.normalizedUri!);

      stdout.writeln('--- Domain & Network Analysis ---');
      stdout.writeln('Domain           : ${analysis.domain}');
      stdout.writeln('IP Address       : ${analysis.ipAddress ?? "(unresolved)"}');
      stdout.writeln('Domain Age (days): ${analysis.domainAgeInDays ?? "(unknown)"}');
      stdout.writeln('Has SSL (https)  : ${analysis.hasSsl}');
      stdout.writeln('Known TLD        : ${analysis.isKnownTld}');
    } else {
      stdout.writeln('No valid URL found; skipping domain analysis.');
    }

    stdout.writeln();
  }
}

