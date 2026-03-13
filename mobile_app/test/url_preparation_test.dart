import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:phishing_detector/services/url_analysis_phase1.dart';

void main() {
  group('URL Preparation module', () {
    test('URL Extraction - extractUrlFromQrPayload finds first URL', () {
      const payload = 'Scan this code to visit https://example.com/path?x=1';
      final extracted = extractUrlFromQrPayload(payload);

      expect(extracted, 'https://example.com/path?x=1');
    });

    test('URL Validation - invalid input returns null', () {
      final uri = validateUrl('not a url');
      expect(uri, isNull);
    });

    test('URL Validation - adds https scheme when missing', () {
      final uri = validateUrl('www.example.com/page');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'https');
      expect(uri.host, 'www.example.com');
    });

    test('URL Normalization - lowercases scheme/host and removes default port', () {
      final uri = Uri.parse('HTTPS://Example.COM:443/Path/?b=2&a=1');
      final normalized = normalizeUrl(uri);

      expect(normalized.scheme, 'https');
      expect(normalized.host, 'example.com');
      expect(normalized.port, 0);
      expect(normalized.path, '/Path/');
      // Query parameters should be sorted by key.
      expect(normalized.query, 'a=1&b=2');
    });

    test('URL Expansion & Redirection Handling - follows redirects up to maxRedirects',
        () async {
      // Fake client that responds with a single redirect, then a final 200.
      final client = _FakeHeadClient([
        _FakeHeadResponse(
          statusCode: 301,
          location: 'https://example.com/final',
        ),
        _FakeHeadResponse(
          statusCode: 200,
        ),
      ]);

      final start = Uri.parse('https://short.example/abc');
      final expanded = await expandUrl(start, client: client);

      expect(expanded.toString(), 'https://example.com/final');
    });

    test('URL Expansion & Redirection Handling - returns original URL when no redirect',
        () async {
      final client = _FakeHeadClient([
        _FakeHeadResponse(
          statusCode: 200,
        ),
      ]);

      final start = Uri.parse('https://example.com/no-redirect');
      final expanded = await expandUrl(start, client: client);

      expect(expanded, start);
    });

    test('High-level preparation - prepareUrlFromQrPayload with no URL', () async {
      const payload = 'This QR code has no url.';
      final result = await prepareUrlFromQrPayload(payload);

      expect(result.extractedUrl, isNull);
      expect(result.validatedUri, isNull);
      expect(result.expandedUri, isNull);
      expect(result.normalizedUri, isNull);
    });
  });
}

// Simple fake HEAD-response description for expandUrl tests.
class _FakeHeadResponse {
  _FakeHeadResponse({required this.statusCode, this.location});

  final int statusCode;
  final String? location;
}

// Minimal fake HTTP client that only supports the HEAD calls used by expandUrl.
class _FakeHeadClient implements http.Client {
  _FakeHeadClient(this._responses);

  final List<_FakeHeadResponse> _responses;
  int _index = 0;

  _FakeHeadResponse _next() =>
      _responses[_index < _responses.length ? _index++ : _responses.length - 1];

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) async {
    final r = _next();
    return http.Response('', r.statusCode,
        headers: r.location != null ? {'location': r.location!} : const {});
  }

  // The following methods are unused in these tests and can throw if called.
  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      Future.error(UnsupportedError('get not supported in _FakeHeadClient'));

  @override
  Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.error(UnsupportedError('post not supported in _FakeHeadClient'));

  @override
  Future<http.Response> put(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.error(UnsupportedError('put not supported in _FakeHeadClient'));

  @override
  Future<http.Response> patch(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.error(UnsupportedError('patch not supported in _FakeHeadClient'));

  @override
  Future<http.Response> delete(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      Future.error(
          UnsupportedError('delete not supported in _FakeHeadClient'));

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) =>
      Future.error(UnsupportedError('read not supported in _FakeHeadClient'));

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) =>
      Future.error(
          UnsupportedError('readBytes not supported in _FakeHeadClient'));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(UnsupportedError('send not supported in _FakeHeadClient'));

  @override
  void close() {}
}

