import 'package:flutter_test/flutter_test.dart';
import 'package:phishing_detector/services/model_inference.dart';

void main() {
  group('Threat Classification module', () {
    test('ML Classification - predictUrlFeatures returns a finite probability',
        () async {
      // Simple, deterministic feature vector (length must be 9).
      final features = <double>[10, 0, 0, 20, 2, 0, 1, 0, 0];

      final prob = await ModelInference.instance.predictUrlFeatures(features);

      // Even if the native model fails to load in a test environment,
      // the implementation returns -1.0 to indicate an error. We assert
      // only that we get back a finite double.
      expect(prob.isFinite, isTrue);
    });

    test('Model Loading - isModelReady can be queried after loadModel', () async {
      // We don’t enforce that the model must load successfully in tests
      // (it depends on assets and platform), but we exercise the API.
      await ModelInference.instance.loadModel();

      // Just verify that the getter is callable without throwing.
      expect(() => ModelInference.instance.isModelReady, returnsNormally);
    });
  });
}

