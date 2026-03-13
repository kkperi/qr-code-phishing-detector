// lib/main.dart

import 'package:flutter/material.dart';
import 'services/model_inference.dart';
import 'services/feature_extraction.dart';
import 'services/url_analysis_phase1.dart';
import 'services/url_expander.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

/*
 * main function
 * 
 * The entry point of the application. It initializes the app and runs the main
 * event loop to listen for events and update the UI.
 * 
 */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Perform an initial test by loading and testing the model
  double testVal = await ModelInference.instance.predictUrlFeatures([
    10.0, // domain_length
    0.0, // have_ip
    0.0, // have_at
    22.0, // url_length
    2.0, // url_depth
    0.0, // redirection
    1.0, // https_domain
    0.0, // tiny_url
    0.0, // prefix_suffix
  ]);
  print("[DEBUG] dummyPredict => $testVal");

  runApp(const MyApp());
}

/*
 * MyApp class
 * 
 * This class represents the root of the application. It creates a MaterialApp
 * widget to provide the basic visual structure for the app, including the title,
 * theme, and initial screen.
 * 
 */
class MyApp extends StatelessWidget {
  // Constructor for MyApp, accepting a key
  const MyApp({super.key});

  /*
    * build method
    * 
    * This method builds the UI of the application using the MaterialApp widget.
    * It provides the basic visual structure for the app, including the title,
    * theme, and initial screen.
    * 
    * Parameters:
    * - context: The build context for the widget
    * 
    * Returns:
    * - MaterialApp widget with the app title, theme, and initial screen
    * 
    */
  @override
  Widget build(BuildContext context) {
    // MaterialApp provides the basic visual structure for the app
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Phishing URL Detector', // Title of the application
      debugShowCheckedModeBanner: false, // Hides the debug banner
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            textStyle: const TextStyle(fontSize: 16),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Colors.grey),
        ),
      ),
      home:
          const HomeScreen(), // Sets HomeScreen as the initial screen of the app
    );
  }
}

/*
 * HomeScreen class
 * 
 * This class represents the main screen of the application where users can
 * enter a URL or scan a QR code to analyze for phishing. It provides a text
 * input field, buttons for analysis and scanning, and displays the result.
 * 
 */
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/*
 * _HomeScreenState class
 * 
 * This class represents the state of the HomeScreen widget. It manages the
 * state of the URL input field, analysis result, loading state, and handles
 * the navigation to the QR scanning screen. It also contains the logic for
 * analyzing the entered or scanned URL for phishing.
 * 
 */
class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController =
      TextEditingController(); // Controller for the URL input field
  String _result = ""; // Variable to hold the analysis result
  bool _isLoading = false; // Indicator for loading state
  UrlPreparationResult?
      _prepResult; // Stores details from URL preparation pipeline
  DomainNetworkAnalysisResult?
      _networkResult; // Stores domain & network analysis details
  List<double>?
      _featureVector; // Stores numeric features extracted from the URL
  double?
      _predictionProbability; // Stores model probability output (phishing likelihood)
  String?
      _predictionLabel; // Stores human-readable prediction label (Phishing/Safe)

  _EvaluationMetrics? _evaluationMetrics;
  bool _isMetricsLoading = false;
  String? _metricsError;
  int _analysisCount = 0;

  // Stores recent scan results so we can compute metrics
  // based on the user's previous scans.
  final List<_ScanRecord> _scanHistory = [];
  static const int _maxScanHistory = 50;
  String? _lastScanId;

  @override
  void initState() {
    super.initState();
    // Lazy computation: metrics are calculated when the user requests them.
  }

  /*
   * _navigateToScanner method
   * 
   * This method navigates to the QRViewExample screen to scan a QR code.
   * It waits for the scanned URL and updates the text field with the scanned URL.
   * 
   */
  void _navigateToScanner() async {
    // Navigate to the QRViewExample screen and wait for the scanned URL
    final scannedUrl = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRViewExample()),
    );

    // If a URL was scanned, update the text field and analyze the URL
    if (scannedUrl != null && scannedUrl is String) {
      _urlController.text = scannedUrl;
      _analyzeUrl(scannedUrl);
    }
  }

  String _lastUrl = ""; // Stores the last URL analyzed
  String _lastLabel = ""; // Stores the last label (Phishing/Safe)

  /*
   * _analyzeUrl method
   * 
   * This method analyzes the URL for phishing by expanding the URL, extracting
   * features, and performing model inference. It updates the result based on
   * the prediction and probability of the model.
   * 
   * Parameters:
   * - url: The URL to analyze for phishing
   * 
   */
  Future<void> _analyzeUrl(String url) async {
    if (url.isEmpty) {
      // If URL is empty, show a message
      setState(() {
        _result = "Please enter a URL.";
      });
      return;
    }

    // Reset previous analysis and set loading state to true
    setState(() {
      _isLoading = true;
      _prepResult = null;
      _networkResult = null;
      _result = "";
      _featureVector = null;
      _predictionProbability = null;
      _predictionLabel = null;
    });

    try {
      // 1) URL Preparation: extraction, validation, expansion, normalization
      final prep = await prepareUrlFromQrPayload(url);

      // If we could not obtain a valid URL, show a message and stop.
      if (prep.normalizedUri == null) {
        setState(() {
          _isLoading = false;
          _prepResult = prep;
          _result =
              "Could not extract a valid URL from the input. Please check the text or QR code.";
        });
        return;
      }

      final finalUrl = prep.normalizedUri.toString();
      _urlController.text = finalUrl;

      // 2) Domain & Network Analysis
      final networkResult =
          await analyzeDomainAndNetwork(prep.normalizedUri!);

      // 3) Feature extraction based on the final normalized URL
      List<double> features = extractFeatures(finalUrl);

      // 4) Model inference
      double prob =
          await ModelInference.instance.predictUrlFeatures(features);

      // 5) Determine label based on probability
      int label = prob >= 0.5 ? 1 : 0;
      String labelStr = label == 1 ? "Phishing" : "Safe";

      // Update the state with the result and stop loading
      final scanId =
          "${DateTime.now().millisecondsSinceEpoch}-${finalUrl.hashCode}";
      setState(() {
        _isLoading = false;
        _result =
            "Prediction: $labelStr\nProbability: ${prob.toStringAsFixed(4)}";
        _lastUrl = finalUrl;
        _lastLabel = labelStr;
        _prepResult = prep;
        _networkResult = networkResult;
        _featureVector = features;
        _predictionProbability = prob;
        _predictionLabel = labelStr;
        _analysisCount += 1;
        _lastScanId = scanId;

        _scanHistory.insert(
          0,
          _ScanRecord(
            id: scanId,
            url: finalUrl,
            probability: prob,
            predictedLabel: label,
            actualLabel: null, // filled by user after viewing result
            inferenceTimeMs: null, // filled when metrics are computed
          ),
        );
        if (_scanHistory.length > _maxScanHistory) {
          _scanHistory.removeLast();
        }
      });

      // Automatically recompute evaluation metrics after every 3 analyses
      if (_analysisCount % 3 == 0) {
        _computeEvaluationMetrics();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _result =
            "An unexpected error occurred while analyzing the URL. Please try again.";
      });
    }
  }

  Future<void> _computeEvaluationMetrics() async {
    if (_isMetricsLoading) return;
    setState(() {
      _isMetricsLoading = true;
      _metricsError = null;
    });

    // Compute metrics based on user-labeled previous scans.
    final labeled = _scanHistory.where((s) => s.actualLabel != null).toList();

    if (labeled.isEmpty) {
      setState(() {
        _isMetricsLoading = false;
        _metricsError =
            "No labeled scans yet. After scanning, tap 'Mark as Safe' or 'Mark as Phishing', then recompute.";
      });
      return;
    }

    int tp = 0, tn = 0, fp = 0, fn = 0;
    final inferenceTimesMs = <int>[];

    for (final s in labeled) {
      final predicted = s.probability >= 0.5 ? 1 : 0; // fixed threshold
      final actual = s.actualLabel!;

      if (predicted == 1 && actual == 1) tp++;
      if (predicted == 0 && actual == 0) tn++;
      if (predicted == 1 && actual == 0) fp++;
      if (predicted == 0 && actual == 1) fn++;

      if (s.inferenceTimeMs != null) {
        inferenceTimesMs.add(s.inferenceTimeMs!);
      }
    }

    final total = tp + tn + fp + fn;
    double safeDiv(double a, double b) => b == 0 ? 0 : (a / b);

    final double accuracy =
        (tp + tn).toDouble() / total.toDouble();
    final precision = safeDiv(tp.toDouble(), (tp + fp).toDouble());
    final recall = safeDiv(tp.toDouble(), (tp + fn).toDouble());
    final double f1 = (precision + recall) == 0
        ? 0.0
        : 2.0 * (precision * recall) / (precision + recall);

    int avg(List<int> xs) =>
        xs.isEmpty ? 0 : (xs.reduce((a, b) => a + b) / xs.length).round();
    int maxVal(List<int> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a > b ? a : b);

    setState(() {
      _evaluationMetrics = _EvaluationMetrics(
        tp: tp,
        tn: tn,
        fp: fp,
        fn: fn,
        accuracy: accuracy,
        precision: precision,
        recall: recall,
        f1Score: f1,
        avgInferenceTimeMs: avg(inferenceTimesMs),
        maxInferenceTimeMs: maxVal(inferenceTimesMs),
        avgTotalPipelineTimeMs: 0,
        maxTotalPipelineTimeMs: 0,
        evaluatedCount: total,
        skippedCount: _scanHistory.length - labeled.length,
        threshold: 0.5,
      );
      _isMetricsLoading = false;
      _metricsError = null;
    });
  }

  void _openMetricsPanel() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: _buildEvaluationMetricsCard(inPanel: true),
            ),
          ),
        );
      },
    );
  }

  /*
   * dispose method
   * 
   * This method disposes of the _urlController when the widget is removed.
   * 
   * Note: It is important to dispose of controllers to prevent memory leaks.
   * 
   */
  @override
  void dispose() {
    _urlController.dispose(); // Dispose the controller when widget is removed
    super.dispose();
  }

  /*
   * build method
   * 
   * This method builds the UI of the HomeScreen widget using a Scaffold widget.
   * It includes an app bar, input field, action buttons, loading indicator,
   * result display, and a redirect button. The UI is updated based on the state.
   * 
   * Parameters:
   * - context: The build context for the widget
   * 
   * Returns:
   * - Scaffold widget with the app bar, input field, buttons, and result display
   * 
   */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("URL Phishing Detector"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: "Evaluation metrics",
            onPressed: _openMetricsPanel,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding:
              const EdgeInsets.all(24.0), // Adds padding around the content
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start, // Aligns children to the start
            children: [
              // Header Section
              Center(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.security,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 64,
                      ),
                    ),
                    const SizedBox(height: 10), // Adds vertical spacing
                    Text(
                      "Phishing URL Detector",
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30), // Adds vertical spacing

              // URL Input Field
              const Text(
                "Enter URL or Scan QR Code:", // Instruction text
                style: TextStyle(
                  fontSize: 18, // Text size
                  fontWeight: FontWeight.w600, // Text weight
                ),
              ),
              const SizedBox(height: 10), // Adds vertical spacing
              TextField(
                controller: _urlController, // Controller for the text field
                decoration: const InputDecoration(
                  hintText:
                      "https://www.example.com", // Hint text displayed inside the text field
                ),
              ),
              const SizedBox(height: 20), // Adds vertical spacing

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _analyzeUrl(_urlController.text
                            .trim()); // Calls analyze function with trimmed URL
                      },
                      icon:
                          const Icon(Icons.search), // Search icon on the button
                      label: const Text("Analyze"), // Button label
                    ),
                  ),
                  const SizedBox(width: 16), // Adds horizontal spacing
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _navigateToScanner, // Navigates to the QR scanner
                      icon:
                          const Icon(Icons.qr_code_scanner), // QR scanner icon
                      label: const Text("Scan QR Code"), // Button label
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30), // Adds vertical spacing

              // Loading Indicator
              if (_isLoading)
                const Center(
                  child:
                      CircularProgressIndicator(), // Shows a loading spinner when analyzing
                ),

              // Result Display
              if (_result.isNotEmpty && !_isLoading)
                Center(
                  child: Card(
                    elevation: 4, // Shadow depth of the card
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          12), // Rounded corners for the card
                    ),
                    color: labelColor(_result
                        .split('\n')[0]), // Sets card color based on the label
                    child: Padding(
                      padding: const EdgeInsets.all(
                          16.0), // Adds padding inside the card
                      child: Text(
                        _result, // Displays the analysis result
                        style: const TextStyle(
                          fontSize: 18, // Text size
                          color: Colors.white, // Text color
                          fontWeight: FontWeight.w600, // Text weight
                        ),
                      ),
                    ),
                  ),
                ),
              if (_prepResult != null && !_isLoading)
                const SizedBox(height: 20),
              if (_prepResult != null && !_isLoading)
                _buildPipelineDetailsCard(),
              const SizedBox(height: 20),
              _buildEvaluationMetricsCard(),
              const SizedBox(height: 20), // Adds vertical spacing

              if (_lastScanId != null && !_isLoading) ...[
                _buildScanLabelCard(),
                const SizedBox(height: 20),
              ],

              // Redirect Button
              if (_lastUrl.isNotEmpty && !_isLoading)
                Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_lastLabel == "Phishing") {
                        // Shows a warning dialog if the URL is identified as phishing
                        bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text("Warning"), // Dialog title
                              content: const Text(
                                  "The website you will be redirected to can be malicious. Are you sure?"), // Dialog content
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(
                                      context, false), // Cancels the action
                                  child: const Text("No"), // Button label
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(
                                      context, true), // Confirms the action
                                  child: const Text("Yes"), // Button label
                                ),
                              ],
                            );
                          },
                        );
                        if (confirm == true) {
                          await launchUrl(Uri.parse(
                              _lastUrl)); // Launches the URL if confirmed
                        }
                      } else {
                        await launchUrl(Uri.parse(
                            _lastUrl)); // Launches the URL if not phishing
                      }
                    },
                    child: const Text("Redirect"), // Button label
                  ),
                ),
              if (_result.isEmpty && !_isLoading)
                const Center(
                  child: Text(
                    "Analyze a URL or scan a QR code to get started.", // Prompt text when no analysis has been done
                    style: TextStyle(
                      fontSize: 16, // Text size
                      color: Colors.grey, // Text color
                    ),
                    textAlign: TextAlign.center, // Centers the text
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /*
   * labelColor method
   * 
   * This method returns a color based on the prediction label.
   * 
   * Parameters:
   * - prediction: The prediction label (Phishing/Safe)
   * 
   * Returns:
   * - Color based on the prediction label
   * 
   */
  Color labelColor(String prediction) {
    if (prediction.contains("Phishing")) {
      return Colors.redAccent; // Red color for phishing
    } else if (prediction.contains("Safe")) {
      return Colors.green; // Green color for safe URLs
    } else {
      return Colors.grey; // Grey color for unknown results
    }
  }

  // Helper widget that shows the detailed pipeline information
  // for URL preparation and domain/network analysis.
  Widget _buildPipelineDetailsCard() {
    final prep = _prepResult;
    final net = _networkResult;
    final features = _featureVector;
    final prob = _predictionProbability;
    final label = _predictionLabel;
    if (prep == null) {
      return const SizedBox.shrink();
    }

    String _stringOrFallback(Object? value, String fallback) {
      if (value == null) return fallback;
      final text = value.toString();
      return text.isEmpty ? fallback : text;
    }

    int _subdomainCountFromHost(String? host) {
      if (host == null || host.isEmpty) return 0;
      final parts = host.split('.');
      if (parts.length <= 2) return 0;
      return parts.length - 2;
    }

    String detectSuspiciousKeywords(String? url) {
      if (url == null) return "Not checked";
      final lower = url.toLowerCase();
      const keywords = [
        'login',
        'verify',
        'update',
        'secure',
        'account',
        'bank',
        'paypal',
        'confirm',
      ];
      final found = keywords.where((k) => lower.contains(k)).toList();
      if (found.isEmpty) {
        return "No obvious phishing keywords";
      }
      return "Contains: ${found.join(', ')}";
    }

    Widget buildRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 3,
      color: Colors.indigo.shade400,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "URL Preparation",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            buildRow(
              "Original Payload",
              _stringOrFallback(prep.originalPayload, "Not available"),
            ),
            buildRow(
              "Extracted URL",
              _stringOrFallback(prep.extractedUrl, "No URL detected"),
            ),
            buildRow(
              "Validated URL",
              _stringOrFallback(
                prep.validatedUri?.toString(),
                "Invalid or missing",
              ),
            ),
            buildRow(
              "Expanded URL",
              _stringOrFallback(
                prep.expandedUri?.toString(),
                "Same as validated (no redirect)",
              ),
            ),
            buildRow(
              "Normalized URL",
              _stringOrFallback(
                prep.normalizedUri?.toString(),
                "Not available",
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Domain & Network Analysis",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (net != null) ...[
              buildRow("Domain", net.domain),
              buildRow(
                "IP Address",
                _stringOrFallback(net.ipAddress, "Unresolved"),
              ),
              buildRow(
                "Domain Age (days)",
                _stringOrFallback(net.domainAgeInDays, "Unknown"),
              ),
              buildRow(
                "SSL (HTTPS)",
                net.hasSsl ? "Yes" : "No",
              ),
              buildRow(
                "Known TLD",
                net.isKnownTld ? "Yes" : "No",
              ),
            ] else ...[
              const Text(
                "No domain/network information available.",
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              "Feature Extraction",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (features != null && features.length >= 9) ...[
              buildRow(
                "URL Length Analysis",
                "${features[3].toInt()} characters",
              ),
              buildRow(
                "URL Depth (path segments)",
                features[4].toInt().toString(),
              ),
              buildRow(
                "Subdomain Count",
                _subdomainCountFromHost(prep.normalizedUri?.host).toString(),
              ),
              buildRow(
                "Has IP Address",
                features[1] == 1.0 ? "Yes" : "No",
              ),
              buildRow(
                "Contains '@' symbol",
                features[2] == 1.0 ? "Yes" : "No",
              ),
              buildRow(
                "HTTPS in URL",
                features[6] == 1.0 ? "Yes" : "No",
              ),
              buildRow(
                "Tiny URL Service",
                features[7] == 1.0 ? "tinyurl / bit.ly" : "No",
              ),
              buildRow(
                "Prefix/Suffix in Domain ('-')",
                features[8] == 1.0 ? "Present" : "Absent",
              ),
              buildRow(
                "Redirect Indicator",
                features[5] == 1.0
                    ? "Inline redirect pattern detected ('//')"
                    : "No inline redirect pattern",
              ),
              buildRow(
                "Redirect Count",
                prep.expandedUri != null &&
                        prep.validatedUri != null &&
                        prep.expandedUri.toString() !=
                            prep.validatedUri.toString()
                    ? "1+ redirect followed during expansion"
                    : "0 (no redirect detected during expansion)",
              ),
              buildRow(
                "Suspicious Keyword Detection",
                detectSuspiciousKeywords(prep.normalizedUri?.toString()),
              ),
              buildRow(
                "Feature Vector Generation",
                "Generated ${features.length} numerical features from URL structure and content",
              ),
            ] else ...[
              const Text(
                "No feature vector available.",
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              "Threat Classification",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (prob != null && label != null) ...[
              buildRow(
                "Model Loading",
                "TFLite model loaded successfully on device",
              ),
              buildRow(
                "ML Classification (TFLite)",
                label,
              ),
              buildRow(
                "Probability Calculation",
                "${(prob * 100).toStringAsFixed(2)}%",
              ),
              buildRow(
                "Rule-Based Adjustment",
                "None (raw probability is used)",
              ),
              buildRow(
                "Final Risk Score",
                "${(prob * 100).toStringAsFixed(2)} / 100",
              ),
            ] else ...[
              const Text(
                "No threat classification details available.",
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Helper widget that shows the evaluation metrics used
  // when the model was trained and assessed (as in the report).
  Widget _buildEvaluationMetricsCard({bool inPanel = false}) {
    Widget sectionTitle(String text) {
      return Padding(
        padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    Widget metricRow(String name, String description,
        {String? formula, String? value}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (value != null)
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: const TextStyle(fontSize: 13),
            ),
            if (formula != null) ...[
              const SizedBox(height: 2),
              Text(
                formula,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.black87,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Evaluation Metrics",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isMetricsLoading ? null : _computeEvaluationMetrics,
                  child: Text(_evaluationMetrics == null
                      ? "Compute"
                      : "Recompute"),
                ),
              ],
            ),
            if (!inPanel)
              const Padding(
                padding: EdgeInsets.only(top: 2.0),
                child: Text(
                  "Tip: You can also open this from the top-right Metrics button.",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            if (_isMetricsLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: LinearProgressIndicator(),
              ),
            if (_metricsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _metricsError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 12),
            sectionTitle("6.1 Classification Performance Metrics"),
            if (_evaluationMetrics != null) ...[
              metricRow(
                "Confusion Matrix",
                "Counts on the built-in evaluation set (TP, TN, FP, FN).",
                value:
                    "TP=${_evaluationMetrics!.tp}  TN=${_evaluationMetrics!.tn}  FP=${_evaluationMetrics!.fp}  FN=${_evaluationMetrics!.fn}",
              ),
              metricRow(
                "Evaluated samples",
                "Number of labeled URLs scored inside the app.",
                value: _evaluationMetrics!.evaluatedCount.toString(),
              ),
              metricRow(
                "Skipped samples",
                "URLs skipped due to network/DNS failures or model errors on device.",
                value: _evaluationMetrics!.skippedCount.toString(),
              ),
              metricRow(
                "Decision threshold",
                "Fixed probability threshold used to label phishing vs safe.",
                value: _evaluationMetrics!.threshold.toStringAsFixed(2),
              ),
            ],
            metricRow(
              "Accuracy",
              "Measures the overall correctness of URL classification as Safe or Phishing.",
              formula: "Accuracy = (TP + TN) / (TP + TN + FP + FN)",
              value: _evaluationMetrics == null
                  ? null
                  : "${(_evaluationMetrics!.accuracy * 100).toStringAsFixed(2)}%",
            ),
            metricRow(
              "Precision",
              "Indicates how many URLs predicted as phishing are actually phishing.",
              formula: "Precision = TP / (TP + FP)",
              value: _evaluationMetrics == null
                  ? null
                  : "${(_evaluationMetrics!.precision * 100).toStringAsFixed(2)}%",
            ),
            metricRow(
              "Recall (Sensitivity)",
              "Measures the ability of the system to correctly detect phishing URLs.",
              formula: "Recall = TP / (TP + FN)",
              value: _evaluationMetrics == null
                  ? null
                  : "${(_evaluationMetrics!.recall * 100).toStringAsFixed(2)}%",
            ),
            metricRow(
              "F1-Score",
              "Harmonic mean of precision and recall, balancing false positives and false negatives.",
              formula: "F1-score = 2 × (Precision × Recall) / (Precision + Recall)",
              value: _evaluationMetrics == null
                  ? null
                  : "${(_evaluationMetrics!.f1Score * 100).toStringAsFixed(2)}%",
            ),
            const SizedBox(height: 12),
            sectionTitle("6.2 Efficiency and System-Level Metrics"),
            metricRow(
              "Inference Time",
              "Time taken by the on-device ML model to classify a scanned QR code.",
              value: _evaluationMetrics == null
                  ? null
                  : "avg ${_evaluationMetrics!.avgInferenceTimeMs} ms (max ${_evaluationMetrics!.maxInferenceTimeMs} ms)",
            ),
            metricRow(
              "Redirection Resolution Success",
              "Indicates how effectively shortened and multi-level redirected URLs are expanded.",
            ),
            metricRow(
              "Mobile Suitability",
              "Assesses whether the system performs efficiently on low-resource mobile devices.",
            ),
            metricRow(
              "Real-Time Performance",
              "Ensures that phishing detection occurs before the user is redirected to the target site.",
              value: _evaluationMetrics == null
                  ? null
                  : "avg ${_evaluationMetrics!.avgTotalPipelineTimeMs} ms (max ${_evaluationMetrics!.maxTotalPipelineTimeMs} ms)",
            ),
            if (_evaluationMetrics == null && !_isMetricsLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  "Tap Compute to calculate metrics on this device.",
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanLabelCard() {
    final id = _lastScanId;
    if (id == null) return const SizedBox.shrink();

    final idx = _scanHistory.indexWhere((s) => s.id == id);
    if (idx < 0) return const SizedBox.shrink();

    final scan = _scanHistory[idx];
    final actual = scan.actualLabel;

    String actualText() {
      if (actual == null) return "Not labeled yet";
      return actual == 1 ? "Phishing" : "Safe";
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Label this scan (for metrics)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "Actual label: ${actualText()}",
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _scanHistory[idx] =
                            _scanHistory[idx].copyWith(actualLabel: 0);
                      });
                    },
                    child: const Text("Mark as Safe"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _scanHistory[idx] =
                            _scanHistory[idx].copyWith(actualLabel: 1);
                      });
                    },
                    child: const Text("Mark as Phishing"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "After labeling a few scans, open Metrics and tap Compute/Recompute.",
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledUrl {
  const _LabeledUrl(this.url, this.label);
  final String url;
  final int label; // 0 = Safe, 1 = Phishing
}

class _EvaluationMetrics {
  const _EvaluationMetrics({
    required this.tp,
    required this.tn,
    required this.fp,
    required this.fn,
    required this.accuracy,
    required this.precision,
    required this.recall,
    required this.f1Score,
    required this.avgInferenceTimeMs,
    required this.maxInferenceTimeMs,
    required this.avgTotalPipelineTimeMs,
    required this.maxTotalPipelineTimeMs,
    required this.evaluatedCount,
    required this.skippedCount,
    required this.threshold,
  });

  final int tp;
  final int tn;
  final int fp;
  final int fn;

  final double accuracy;
  final double precision;
  final double recall;
  final double f1Score;

  final int avgInferenceTimeMs;
  final int maxInferenceTimeMs;
  final int avgTotalPipelineTimeMs;
  final int maxTotalPipelineTimeMs;

  final int evaluatedCount;
  final int skippedCount;
  final double threshold;
}

class _ScanRecord {
  const _ScanRecord({
    required this.id,
    required this.url,
    required this.probability,
    required this.predictedLabel,
    required this.actualLabel,
    required this.inferenceTimeMs,
  });

  final String id;
  final String url;
  final double probability;
  final int predictedLabel; // 0/1 computed using 0.5 at scan time
  final int? actualLabel; // 0/1 set by user
  final int? inferenceTimeMs;

  _ScanRecord copyWith({int? actualLabel}) {
    return _ScanRecord(
      id: id,
      url: url,
      probability: probability,
      predictedLabel: predictedLabel,
      actualLabel: actualLabel,
      inferenceTimeMs: inferenceTimeMs,
    );
  }
}

/*
 * QRViewExample class
 * 
 * This class represents the screen for scanning QR codes. It uses the MobileScanner
 * widget to display the camera view and detect QR codes. The detected QR code
 * is returned to the HomeScreen for analysis.
 * 
 */
class QRViewExample extends StatefulWidget {
  const QRViewExample({super.key});

  @override
  State<StatefulWidget> createState() => _QRViewExampleState();
}

/*
 * _QRViewExampleState class
 * 
 * This class represents the state of the QRViewExample widget. It manages the
 * scanner controller, scanning state, and the callback function for barcode
 * detection. It displays the camera view and an overlay to indicate the scanning
 * area.
 * 
 */
class _QRViewExampleState extends State<QRViewExample> {
  final GlobalKey qrKey =
      GlobalKey(debugLabel: 'QR'); // Unique key for the QR view
  MobileScannerController controller =
      MobileScannerController(); // Controller to manage the scanner
  bool _isScanning = true; // Flag to indicate if scanning is active

  @override
  void dispose() {
    controller
        .dispose(); // Dispose the scanner controller when the widget is removed
    super.dispose();
  }

  /*
   * _foundBarcode method
   * 
   * This method is called when a barcode is detected by the scanner. It extracts
   * the raw value of the barcode and stops further scanning. The scanned code
   * is then returned to the HomeScreen and the scanner is closed.
   * 
   * Parameters:
   * - capture: The BarcodeCapture object containing the detected barcodes
   * 
   */
  void _foundBarcode(BarcodeCapture capture) {
    if (!_isScanning) return; // Exit if scanning has been stopped

    final List<Barcode> barcodes =
        capture.barcodes; // List of detected barcodes
    for (final barcode in barcodes) {
      final String? code =
          barcode.rawValue; // Extract the raw value of the barcode
      if (code != null && _isScanning) {
        _isScanning = false; // Stop further scanning
        controller.stop(); // Stop the scanner

        Navigator.pop(
            context, code); // Return the scanned code and close the scanner
        break; // Exit the loop after processing the first valid code
      }
    }
  }

  /*
   * build method
   * 
   * This method builds the UI of the QRViewExample widget using a Scaffold widget.
   * It includes the MobileScanner widget to display the camera view and detect
   * QR codes. An overlay is added to indicate the scanning area.
   * 
   * Parameters:
   * - context: The build context for the widget
   * 
   * Returns:
   * - Scaffold widget with the camera view and scanning overlay
   * 
   */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'), // Title displayed in the app bar
        backgroundColor: Colors.indigo, // Sets the app bar background color
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller, // Assigns the scanner controller
            onDetect: _foundBarcode, // Sets the callback for barcode detection
          ),
          // Overlay to indicate the scanning area
          Positioned(
            top: 100, // Position from the top of the screen
            left: 50, // Position from the left of the screen
            right: 50, // Position from the right of the screen
            child: Container(
              height: 250, // Height of the overlay box
              decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.indigo, width: 2), // Border styling
                borderRadius: BorderRadius.circular(
                    12), // Rounded corners for the overlay
              ),
            ),
          ),
        ],
      ),
    );
  }
}
