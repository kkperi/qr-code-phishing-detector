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
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _result =
            "An unexpected error occurred while analyzing the URL. Please try again.";
      });
    }
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
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'URL Phishing Detector',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.security),
                children: const [
                  Text(
                    "This application detects whether the URLs entered or scanned are phishing.\n\n-Made by Ali Asım Coşkun",
                  ),
                ],
              );
            },
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
              const SizedBox(height: 20), // Adds vertical spacing

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
