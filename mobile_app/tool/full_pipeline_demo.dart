// Console demo that runs the "full" 50% pipeline:
// - URL extraction, validation, expansion, normalization
// - Domain & network analysis
// - Feature extraction
// - TFLite model inference
//
// Run from the `mobile_app` directory:
//   dart run tool/full_pipeline_demo.dart

import 'dart:io';

import 'package:phishing_detector/services/feature_extraction.dart';
import 'package:phishing_detector/services/model_inference.dart';
import 'package:phishing_detector/services/url_analysis_phase1.dart';

Future<void> main() async {
  const payload =
      'Scan this QR to visit https://example.com/login?b=2&a=1'; // Example QR content

  stdout.writeln('=== FULL PIPELINE DEMO (50% implementation) ===');
  stdout.writeln('QR payload: $payload');
  stdout.writeln('');

  // 1) URL preparation
  final prep = await prepareUrlFromQrPayload(payload);

  stdout.writeln('--- URL Preparation ---');
  stdout.writeln('Original payload : ${prep.originalPayload}');
  stdout.writeln('Extracted URL    : ${prep.extractedUrl}');
  stdout.writeln('Validated URI    : ${prep.validatedUri}');
  stdout.writeln('Expanded URI     : ${prep.expandedUri}');
  stdout.writeln('Normalized URI   : ${prep.normalizedUri}');
  stdout.writeln('');

  if (prep.normalizedUri == null) {
    stdout.writeln('No valid URL -> stopping before model inference.');
    return;
  }

  // 2) Domain & network analysis
  final net = await analyzeDomainAndNetwork(prep.normalizedUri!);

  stdout.writeln('--- Domain & Network Analysis ---');
  stdout.writeln('Domain           : ${net.domain}');
  stdout.writeln('IP Address       : ${net.ipAddress ?? "(unresolved)"}');
  stdout.writeln('Domain Age (days): ${net.domainAgeInDays ?? "(unknown)"}');
  stdout.writeln('Has SSL (https)  : ${net.hasSsl}');
  stdout.writeln('Known TLD        : ${net.isKnownTld}');
  stdout.writeln('');

  // 3) Feature extraction on the normalized URL
  final finalUrl = prep.normalizedUri.toString();
  stdout.writeln('--- Feature Extraction & Model Inference ---');
  stdout.writeln('Final URL used for features: $finalUrl');

  final features = extractFeatures(finalUrl);
  stdout.writeln('Extracted features (9): $features');

  // 4) TFLite inference
  final probability =
      await ModelInference.instance.predictUrlFeatures(features);
  final label = probability >= 0.5 ? 'Phishing' : 'Safe';

  stdout.writeln('Model probability: ${probability.toStringAsFixed(4)}');
  stdout.writeln('Predicted label : $label');
  stdout.writeln('=== END DEMO ===');
}

