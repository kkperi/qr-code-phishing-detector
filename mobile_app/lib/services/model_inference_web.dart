// Web implementation of the ModelInference API.
//
// The tflite_flutter package relies on dart:ffi, which is not
// available on the web platform. To keep the application usable
// in the browser, this stub provides the same API as the native
// implementation but returns a deterministic dummy probability.
//
// This means:
// - URL preparation and domain/network analysis still run fully.
// - The "Prediction" output is illustrative rather than backed
//   by the actual TFLite model when running on the web.

class ModelInference {
  ModelInference._privateConstructor();
  static final ModelInference instance = ModelInference._privateConstructor();

  Future<void> loadModel() async {
    // No-op on web: the native TFLite model cannot be loaded here.
  }

  bool get isModelReady => true;

  Future<double> predictUrlFeatures(List<double> features) async {
    // Very simple heuristic/dummy prediction so that the UI
    // continues to function. You can replace this with a call
    // to a server-side model if needed.
    if (features.isEmpty) return 0.5;

    final domainLength = features[0];
    final hasIp = features.length > 1 ? features[1] : 0.0;

    // Heuristic: URLs with an IP address and very long domains
    // are slightly more suspicious.
    final base = 0.4 +
        0.3 * hasIp.clamp(0.0, 1.0) +
        0.3 * (domainLength / 100.0).clamp(0.0, 1.0);

    return base.clamp(0.0, 1.0);
  }
}

