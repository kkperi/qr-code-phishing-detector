// lib/services/model_inference.dart
//
// Platform-aware export for model inference.
//
// On native platforms (Android, iOS, Windows, macOS, Linux) we use the real
// TFLite model via `tflite_flutter` in `model_inference_native.dart`.
//
// On the web, `tflite_flutter` is not supported because it relies on
// `dart:ffi`, so we export a lightweight stub implementation from
// `model_inference_web.dart` that provides the same API but returns a
// heuristic/dummy probability.

export 'model_inference_native.dart'
    if (dart.library.html) 'model_inference_web.dart';

