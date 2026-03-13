import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phishing_detector/services/url_analysis_phase1.dart';

class _FakeDomainInfoProvider implements DomainInfoProvider {
  _FakeDomainInfoProvider(this.ageInDays);

  final int? ageInDays;

  @override
  Future<int?> getDomainAgeInDays(String domain) async => ageInDays;
}

void main() {
  group('Domain and Network Analysis module', () {
    test('DNS Lookup - performDnsLookup uses injected lookup function', () async {
      final addresses = await performDnsLookup(
        'example.com',
        lookup: (host) async => [
          InternetAddress('93.184.216.34', type: InternetAddressType.IPv4),
        ],
      );

      expect(addresses, hasLength(1));
      expect(addresses.first.address, '93.184.216.34');
    });

    test('IP Address Extraction - extractIpAddress prefers IPv4', () {
      final addresses = [
        InternetAddress('2001:db8::1', type: InternetAddressType.IPv6),
        InternetAddress('93.184.216.34', type: InternetAddressType.IPv4),
      ];

      final ip = extractIpAddress(addresses);
      expect(ip, '93.184.216.34');
    });

    test('TLD Verification - isKnownTld detects known and unknown TLDs', () {
      expect(isKnownTld('example.com'), isTrue);
      expect(isKnownTld('example.unknown'), isFalse);
    });

    test('SSL Certificate Check - hasSsl is true only for https scheme', () {
      expect(hasSsl(Uri.parse('https://example.com')), isTrue);
      expect(hasSsl(Uri.parse('http://example.com')), isFalse);
    });

    test('Aggregated analysis - analyzeDomainAndNetwork aggregates results', () async {
      final url = Uri.parse('https://example.com/path');

      final result = await analyzeDomainAndNetwork(
        url,
        dnsLookup: (host) async => [
          InternetAddress('93.184.216.34', type: InternetAddressType.IPv4),
        ],
        domainInfoProvider: _FakeDomainInfoProvider(365), // domain age
      );

      expect(result.domain, 'example.com');
      expect(result.ipAddress, '93.184.216.34');
      expect(result.domainAgeInDays, 365);
      expect(result.hasSsl, isTrue);
      expect(result.isKnownTld, isTrue);
    });
  });
}

