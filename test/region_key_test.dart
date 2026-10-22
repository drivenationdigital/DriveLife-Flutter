import 'package:drivelife/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// The region prefix on a dashboard or checkout link.
///
/// The accounts dashboard splits an event ref on this prefix, so getting it
/// wrong is an unopenable link rather than a wrong-looking one. Two new
/// regions are joining the network, which is why this is a function with a
/// test rather than `site == 'us' ? 'us' : 'uk'` written out three times.
void main() {
  test('the UK is uk, not its country code', () {
    // The country is GB and the region key is uk. Lowercasing the country
    // would give "gb", which the dashboard does not know.
    for (final site in ['GB', 'gb', 'UK', 'uk', 'IE']) {
      expect(dashboardRegionKey(site), 'uk', reason: site);
    }
  });

  test('north america is us', () {
    for (final site in ['US', 'us', 'USA', 'CA', 'MX']) {
      expect(dashboardRegionKey(site), 'us', reason: site);
    }
  });

  test('the new regions', () {
    expect(dashboardRegionKey('EU'), 'eu');
    expect(dashboardRegionKey('AU'), 'au');
    expect(dashboardRegionKey('NZ'), 'au');
  });

  test('anything unknown falls to uk, as the server does', () {
    // dl_normalise_site() sends everything it does not recognise to GB, so
    // a link built here has to agree or it points at the wrong catalogue.
    for (final site in ['', '  ', 'ZZ', 'JP', null]) {
      expect(dashboardRegionKey(site), 'uk', reason: '$site');
    }
  });

  test('whitespace and case do not change the answer', () {
    expect(dashboardRegionKey('  Us  '), 'us');
    expect(dashboardRegionKey('  eu'), 'eu');
  });
}
