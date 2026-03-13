// lib/services/url_analysis_phase1.dart
//
// This file contains a "50% implementation" of the URL
// analysis pipeline used in the project. It focuses on
// the URL preparation and the domain/network analysis
// blocks shown in the architecture diagram:
//
// - URL Extraction
// - URL Validation
// - URL Expansion
// - Redirection Handling
// - URL Normalization
// - DNS Lookup
// - IP Address Extraction
// - Domain Age Check
// - SSL Certificate Check
// - TLD Verification
//
// The remaining parts of the system (feature engineering,
// model inference, UI, etc.) are handled by other files
// such as `feature_extraction.dart` and `model_inference.dart`.

import 'dart:io';

import 'package:http/http.dart' as http;

/// Result of running the URL preparation stage.
class UrlPreparationResult {
  UrlPreparationResult({
    required this.originalPayload,
    this.extractedUrl,
    this.validatedUri,
    this.expandedUri,
    this.normalizedUri,
  });

  /// Raw text decoded from the QR code.
  final String originalPayload;

  /// First URL string extracted from the payload, if any.
  final String? extractedUrl;

  /// Parsed and syntactically valid URL.
  final Uri? validatedUri;

  /// Final URL after following shorteners / redirects.
  final Uri? expandedUri;

  /// Canonical, normalized representation of the URL.
  final Uri? normalizedUri;
}

/// Result of the domain and network analysis stage.
class DomainNetworkAnalysisResult {
  DomainNetworkAnalysisResult({
    required this.domain,
    this.ipAddress,
    this.domainAgeInDays,
    required this.hasSsl,
    required this.isKnownTld,
  });

  /// Host part of the URL (e.g. "example.com").
  final String domain;

  /// IPv4/IPv6 address if it could be resolved.
  final String? ipAddress;

  /// Approximate age of the domain in days, if available.
  final int? domainAgeInDays;

  /// Whether the URL uses HTTPS (basic SSL check).
  final bool hasSsl;

  /// Whether the top‑level domain is recognised / allowed.
  final bool isKnownTld;
}

/// Extracts the first URL‑looking substring from a QR payload.
///
/// This supports common URL formats such as:
/// - https://example.com/path
/// - http://example.com
/// - www.example.com
String? extractUrlFromQrPayload(String payload) {
  final urlRegex = RegExp(
    r'((https?:\/\/)?(www\.)?[a-zA-Z0-9\-_]+\.[a-zA-Z]{2,}(\/\S*)?)',
  );

  final match = urlRegex.firstMatch(payload);
  if (match == null) return null;

  final url = match.group(0);
  if (url == null || url.trim().isEmpty) {
    return null;
  }
  return url.trim();
}

/// Parses and validates a URL string.
///
/// Returns `null` if the string cannot be parsed into a [Uri] or
/// if it does not contain a host component.
Uri? validateUrl(String? rawUrl) {
  if (rawUrl == null || rawUrl.trim().isEmpty) return null;

  final trimmed = rawUrl.trim();

  // Reject inputs that clearly cannot be URLs (e.g. contain whitespace).
  if (trimmed.contains(RegExp(r'\s'))) {
    return null;
  }

  // If the user scanned something like "www.example.com",
  // prepend a default scheme so that Uri parsing works.
  final normalizedInput = trimmed.startsWith('http://') ||
          trimmed.startsWith('https://')
      ? trimmed
      : 'https://$trimmed';

  try {
    final uri = Uri.parse(normalizedInput);
    if (uri.host.isEmpty) return null;
    return uri;
  } on FormatException {
    return null;
  }
}

/// Expands a potentially shortened URL by following redirects.
///
/// This function performs a series of `HEAD` requests with
/// `followRedirects` disabled, manually following the `Location`
/// header up to [maxRedirects] times. The last reachable Uri
/// (or the original [url] if no redirect occurs) is returned.
Future<Uri> expandUrl(
  Uri url, {
  http.Client? client,
  int maxRedirects = 3,
}) async {
  final httpClient = client ?? http.Client();
  try {
    var current = url;
    for (var i = 0; i < maxRedirects; i++) {
      final response = await httpClient.head(
        current,
        headers: const {'User-Agent': 'qr-phishing-detector/1.0'},
      );

      if (response.isRedirect || response.statusCode == 301 ||
          response.statusCode == 302 || response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers['location'];
        if (location == null) break;
        final next = Uri.tryParse(location);
        if (next == null) break;
        current = current.resolveUri(next);
      } else {
        break;
      }
    }
    return current;
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}

/// High‑level helper that:
/// 1. Extracts a URL from QR payload
/// 2. Validates it
/// 3. Expands short URLs / follows redirects
/// 4. Normalizes the final URL
Future<UrlPreparationResult> prepareUrlFromQrPayload(
  String payload, {
  http.Client? client,
}) async {
  final extracted = extractUrlFromQrPayload(payload);
  final validated = validateUrl(extracted);

  if (validated == null) {
    return UrlPreparationResult(
      originalPayload: payload,
      extractedUrl: extracted,
      validatedUri: null,
      expandedUri: null,
      normalizedUri: null,
    );
  }

  final expanded = await expandUrl(validated, client: client);
  final normalized = normalizeUrl(expanded);

  return UrlPreparationResult(
    originalPayload: payload,
    extractedUrl: extracted,
    validatedUri: validated,
    expandedUri: expanded,
    normalizedUri: normalized,
  );
}

/// Normalizes a [Uri] by:
/// - Lower‑casing scheme and host
/// - Removing default ports (80 for http, 443 for https)
/// - Removing an empty trailing slash on the path
/// - Sorting query parameters by key
Uri normalizeUrl(Uri url) {
  final isDefaultPort = (url.scheme == 'http' && url.port == 80) ||
      (url.scheme == 'https' && url.port == 443);

  final path = url.path == '/' ? '' : url.path;

  final sortedQueryParameters = Map<String, String>.fromEntries(
    url.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key)),
  );

  return Uri(
    scheme: url.scheme.toLowerCase(),
    userInfo: url.userInfo,
    host: url.host.toLowerCase(),
    port: isDefaultPort ? 0 : url.port,
    path: path,
    queryParameters:
        sortedQueryParameters.isEmpty ? null : sortedQueryParameters,
    fragment: url.fragment.isEmpty ? null : url.fragment,
  );
}

/// Type definition for a DNS lookup function so that tests
/// can inject a fake implementation.
typedef DnsLookup = Future<List<InternetAddress>> Function(String host);

/// Performs a DNS lookup for [host] and returns all resolved
/// [InternetAddress] entries.
Future<List<InternetAddress>> performDnsLookup(
  String host, {
  DnsLookup? lookup,
}) {
  final effectiveLookup = lookup ?? InternetAddress.lookup;
  return effectiveLookup(host);
}

/// Extracts a single IP address string from a list of
/// [InternetAddress] instances, preferring IPv4 if present.
String? extractIpAddress(List<InternetAddress> addresses) {
  if (addresses.isEmpty) return null;

  // Prefer IPv4 if possible.
  final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4);
  if (ipv4.isNotEmpty) {
    return ipv4.first.address;
  }
  return addresses.first.address;
}

/// Very small built‑in list of widely‑used TLDs.
/// In a production system you would replace this with a
/// comprehensive public suffix list.
const Set<String> _knownTlds = {
  'com',
  'org',
  'net',
  'edu',
  'gov',
  'io',
  'ai',
  'co',
  'info',
  'biz',
};

/// Returns `true` if the host's top‑level domain is in the
/// [_knownTlds] set.
bool isKnownTld(String host) {
  final parts = host.split('.');
  if (parts.length < 2) return false;
  final tld = parts.last.toLowerCase();
  return _knownTlds.contains(tld);
}

/// Basic SSL certificate check.
///
/// For the purposes of the mobile client and this "phase 1"
/// implementation, we simply treat any `https` URL as having
/// SSL enabled. More advanced checks (certificate validity,
/// expiry, issuer, etc.) would require a separate service.
bool hasSsl(Uri url) => url.scheme.toLowerCase() == 'https';

/// Abstraction for fetching domain‑level metadata (such as
/// creation date) from an external service.
abstract class DomainInfoProvider {
  Future<int?> getDomainAgeInDays(String domain);
}

/// Example implementation that calls an HTTP API to obtain
/// domain registration information.
///
/// This is intentionally simple and meant as a placeholder;
/// you can replace the URL and parsing logic with whichever
/// WHOIS / domain‑info provider you prefer.
class HttpDomainInfoProvider implements DomainInfoProvider {
  HttpDomainInfoProvider({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<int?> getDomainAgeInDays(String domain) async {
    // NOTE: This example uses the (hypothetical) endpoint
    // `https://example-whois-api.com/lookup?domain=...`.
    // Replace this with a real provider in your own project.
    final uri = Uri.https(
      'example-whois-api.com',
      '/lookup',
      {'domain': domain},
    );

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return null;

      // In a real implementation you would decode JSON
      // and compute the age from the creation date.
      //
      // To keep this file self‑contained and side‑effect‑free
      // for unit testing, we return null here.
      return null;
    } finally {
      _client.close();
    }
  }
}

/// High‑level helper that runs the domain and network
/// analysis stage of the pipeline.
Future<DomainNetworkAnalysisResult> analyzeDomainAndNetwork(
  Uri url, {
  DnsLookup? dnsLookup,
  DomainInfoProvider? domainInfoProvider,
}) async {
  final domain = url.host.toLowerCase();
  final hasSslForUrl = hasSsl(url);
  final knownTld = isKnownTld(domain);

  List<InternetAddress> addresses = [];
  try {
    addresses = await performDnsLookup(domain, lookup: dnsLookup);
  } on SocketException {
    // Ignore DNS failures and leave addresses empty.
  }

  final ipAddress = extractIpAddress(addresses);

  final provider = domainInfoProvider;
  int? domainAgeInDays;
  if (provider != null) {
    domainAgeInDays = await provider.getDomainAgeInDays(domain);
  }

  return DomainNetworkAnalysisResult(
    domain: domain,
    ipAddress: ipAddress,
    domainAgeInDays: domainAgeInDays,
    hasSsl: hasSslForUrl,
    isKnownTld: knownTld,
  );
}

