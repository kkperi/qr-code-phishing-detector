// Native (non-web) implementation of the model inference
// using tflite_flutter and the on-device TFLite model.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

class ModelInference {
  // Singleton Pattern
  ModelInference._privateConstructor();
  static final ModelInference instance = ModelInference._privateConstructor();

  Interpreter? _interpreter;

  Future<void> loadModel() async {
    if (_interpreter != null) {
      // Model already loaded
      return;
    }
    try {
      // 1) Read model.tflite as ByteData
      ByteData rawModelData = await rootBundle.load('assets/model.tflite');

      // 2) Convert ByteData to Uint8List
      final Uint8List modelBytes = rawModelData.buffer.asUint8List(
        rawModelData.offsetInBytes,
        rawModelData.lengthInBytes,
      );

      // 3) Load model from buffer
      _interpreter = await Interpreter.fromBuffer(modelBytes);
      // ignore: avoid_print
      print("[INFO] Model loaded from buffer successfully!");
    } catch (e) {
      // ignore: avoid_print
      print("[ERROR] Failed to load model: $e");
    }
  }

  bool get isModelReady => _interpreter != null;

  Future<double> predictUrlFeatures(List<double> features) async {
    await loadModel();
    if (_interpreter == null) {
      return -1.0; // Error case
    }

    // Input shape: [1, 9]
    var input = [features];
    var output = List.generate(1, (_) => List.filled(1, 0.0));

    try {
      _interpreter!.run(input, output);
      double prob = output[0][0];
      return prob;
    } catch (e) {
      // ignore: avoid_print
      print("[ERROR] Inference failed: $e");
      return -1.0;
    }
  }
}

