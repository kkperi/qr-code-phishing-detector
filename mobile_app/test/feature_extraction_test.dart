import 'package:flutter_test/flutter_test.dart';
import 'package:phishing_detector/services/feature_extraction.dart';

void main() {
  group('Feature Extraction module', () {
    test('extractFeatures computes all 9 features correctly for a normal URL', () {
      const url = 'https://www.example.com/path/to/resource';

      final features = extractFeatures(url);

      expect(features, hasLength(9));
      // 1. domain_length
      expect(features[0], 'www.example.com'.length.toDouble());
      // 2. have_ip
      expect(features[1], 0.0);
      // 3. have_at
      expect(features[2], 0.0);
      // 4. url_length
      expect(features[3], url.length.toDouble());
      // 5. url_depth (path segments)
      expect(features[4], 3.0);
      // 6. redirection flag (no '//' in path)
      expect(features[5], 0.0);
      // 7. https_domain
      expect(features[6], 1.0);
      // 8. tiny_url
      expect(features[7], 0.0);
      // 9. prefix_suffix
      expect(features[8], 0.0);
    });

    test('extractFeatures detects IP-based URL and @ symbol', () {
      const url = 'http://192.168.1.10/login@user';

      final features = extractFeatures(url);

      // have_ip should be 1.0 for IP hosts
      expect(features[1], 1.0);
      // have_at should be 1.0 because of '@'
      expect(features[2], 1.0);
      // https_domain should be 0.0 because scheme is http
      expect(features[6], 0.0);
    });

    test('extractFeatures flags tiny URL domains and hyphenated domains', () {
      const tinyUrl = 'https://tinyurl.com/abc123';
      const hyphenDomain = 'https://secure-pay.example-bank.com';

      final tinyFeatures = extractFeatures(tinyUrl);
      final hyphenFeatures = extractFeatures(hyphenDomain);

      // tinyurl.com should be detected as a shortening service.
      expect(tinyFeatures[7], 1.0);

      // Domain containing '-' should set prefix_suffix feature to 1.0.
      expect(hyphenFeatures[8], 1.0);
    });

    test('extractFeatures returns zeros on parse error', () {
      final features = extractFeatures('this is not a valid url');

      expect(features, hasLength(9));
      expect(features.every((v) => v == 0.0), isTrue);
    });

    test('isIPAddress correctly recognises IPv4 addresses', () {
      expect(isIPAddress('192.168.0.1'), isTrue);
      expect(isIPAddress('999.999.999.999'), isFalse);
      expect(isIPAddress('example.com'), isFalse);
    });
  });
}

