// Live venue / market-data canary — runs through Omniscope Dart adapters.
//
// Public probes always run. Private portfolio probes run only when the
// matching OMNISCOPE_* credentials are present in `.env`. Never places orders.
//
// Invoke via Flutter (this package imports dart:ui through Yahoo / dotenv):
//   make venue-canary
//   flutter test test/venue_canary_test.dart
//
// Exit / test failure when any non-skipped probe is not ok. Not part of
// `make check` / pre-push.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:omniscope/core/dotenv_asset.dart';
import 'package:omniscope/data/brokers/alpaca/alpaca_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/market/yahoo_market_data_client.dart';
import 'package:omniscope/data/venues/venue_catalog.dart';

enum ProbeStatus { ok, httpError, parseError, skipped }

class ProbeResult {
  ProbeResult({
    required this.venue,
    required this.probe,
    required this.status,
    this.detail,
  });

  final String venue;
  final String probe;
  final ProbeStatus status;
  final String? detail;

  Map<String, dynamic> toJson() => {
        'venue': venue,
        'probe': probe,
        'status': status.name,
        if (detail != null && detail!.isNotEmpty) 'detail': detail,
      };
}

/// Runs the probe matrix. Returns `0` on success, `1` when any probe failed.
Future<int> runVenueCanary({
  String? jsonOut,
  void Function(String line)? log,
}) async {
  void write(String line) => (log ?? stdout.writeln)(line);

  final envValues = _loadEnvValues();
  ExchangeCredentialsConfig.defaultExchangeIds =
      VenueCatalog.knownCredentialVenueIds;
  final creds = ExchangeCredentialsConfig.fromValues(envValues);

  final httpClient = http.Client();
  final results = <ProbeResult>[];

  try {
    final yahoo = YahooMarketDataClient(httpClient: httpClient);
    results.addAll(await _probeYahoo(yahoo));

    final cryptoCom = CryptoComExchangeClient(
      httpClient: httpClient,
      credentials: creds.forId(CryptoComExchangeClient.meta.id),
    );
    results.addAll(await _probeCryptoCom(cryptoCom));

    final alpaca = AlpacaExchangeClient(
      httpClient: httpClient,
      credentials: creds.forId(AlpacaExchangeClient.meta.id),
    );
    results.addAll(await _probeAlpaca(alpaca));
  } finally {
    httpClient.close();
  }

  final markdown = markdownTable(results);
  write(markdown);

  final payload = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'results': [for (final r in results) r.toJson()],
  };
  final jsonText = const JsonEncoder.withIndent('  ').convert(payload);

  final outPath = jsonOut ?? 'build/venue-canary.json';
  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$jsonText\n');
  write('Wrote $outPath');

  final summaryPath = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summaryPath != null && summaryPath.isNotEmpty) {
    File(summaryPath).writeAsStringSync(
      '## Venue canary\n\n$markdown\n',
      mode: FileMode.append,
    );
  }

  final failed = results.where(
    (r) =>
        r.status == ProbeStatus.httpError ||
        r.status == ProbeStatus.parseError,
  );
  if (failed.isNotEmpty) {
    write('${failed.length} probe(s) failed.');
    return 1;
  }
  return 0;
}

String markdownTable(List<ProbeResult> results) {
  final buf = StringBuffer();
  buf.writeln('| Venue | Probe | Status | Detail |');
  buf.writeln('|-------|-------|--------|--------|');
  for (final r in results) {
    final detail = (r.detail ?? '')
        .replaceAll('|', '\\|')
        .replaceAll('\n', ' ')
        .trim();
    final clipped =
        detail.length > 80 ? '${detail.substring(0, 77)}...' : detail;
    buf.writeln('| ${r.venue} | ${r.probe} | `${r.status.name}` | $clipped |');
  }
  return buf.toString();
}

Map<String, String> _loadEnvValues() {
  for (final path in ['.env', '.env.example']) {
    final file = File(path);
    if (file.existsSync()) {
      return DotEnvAsset.parse(file.readAsStringSync());
    }
  }
  return const {};
}

Future<List<ProbeResult>> _probeYahoo(YahooMarketDataClient client) async {
  const venue = 'yahoo';
  final out = <ProbeResult>[];

  out.add(
    await _run(venue, 'quote', () async {
      final quotes = await client.getQuotes(const ['AAPL']);
      if (quotes.isEmpty) {
        throw StateError('empty quotes');
      }
      if (quotes.single.price <= 0) {
        throw StateError('non-positive price');
      }
      return 'AAPL @ ${quotes.single.price}';
    }),
  );

  out.add(
    await _run(venue, 'history', () async {
      final candles = await client.getHistory(
        'AAPL',
        range: '5d',
        interval: '1d',
      );
      if (candles.isEmpty) {
        throw StateError('empty candles');
      }
      return '${candles.length} bars';
    }),
  );

  return out;
}

Future<List<ProbeResult>> _probeCryptoCom(
  CryptoComExchangeClient client,
) async {
  const venue = 'crypto_com';
  final out = <ProbeResult>[];

  out.add(
    await _run(venue, 'quote', () async {
      final quotes = await client.getQuotes(const ['BTC_USD']);
      if (quotes.isEmpty) {
        throw StateError('empty quotes');
      }
      return 'BTC_USD @ ${quotes.single.price}';
    }),
  );

  out.add(
    await _run(venue, 'history', () async {
      final candles = await client.getHistory(
        'BTC_USD',
        range: '1mo',
        interval: '1d',
      );
      if (candles.isEmpty) {
        throw StateError('empty candles');
      }
      return '${candles.length} bars';
    }),
  );

  out.add(
    await _run(venue, 'browse', () async {
      final symbols = await client.browseSymbols();
      if (symbols.isEmpty) {
        throw StateError('empty catalog');
      }
      return '${symbols.length} symbols';
    }),
  );

  if (!client.canFetchPortfolio) {
    out.add(
      ProbeResult(
        venue: venue,
        probe: 'portfolio',
        status: ProbeStatus.skipped,
        detail: 'no API key+secret',
      ),
    );
  } else {
    out.add(
      await _run(venue, 'portfolio', () async {
        final snap = await client.fetchPortfolio();
        return '${snap.balances.length} balances';
      }),
    );
  }

  return out;
}

Future<List<ProbeResult>> _probeAlpaca(AlpacaExchangeClient client) async {
  const venue = 'alpaca';
  final out = <ProbeResult>[];

  // Brokers have no public quote/history — equities stay on Yahoo.
  out.add(
    ProbeResult(
      venue: venue,
      probe: 'quote',
      status: ProbeStatus.skipped,
      detail: 'broker — quotes via Yahoo',
    ),
  );
  out.add(
    ProbeResult(
      venue: venue,
      probe: 'history',
      status: ProbeStatus.skipped,
      detail: 'broker — history via Yahoo',
    ),
  );

  if (!client.canFetchPortfolio) {
    out.add(
      ProbeResult(
        venue: venue,
        probe: 'portfolio',
        status: ProbeStatus.skipped,
        detail: 'no API key+secret',
      ),
    );
  } else {
    out.add(
      await _run(venue, 'portfolio', () async {
        final snap = await client.fetchPortfolio();
        return '${snap.balances.length} balances';
      }),
    );
  }

  return out;
}

Future<ProbeResult> _run(
  String venue,
  String probe,
  Future<String> Function() action,
) async {
  try {
    final detail = await action();
    return ProbeResult(
      venue: venue,
      probe: probe,
      status: ProbeStatus.ok,
      detail: detail,
    );
  } on MarketDataException catch (e) {
    final status = e.statusCode != null && e.statusCode! >= 400
        ? ProbeStatus.httpError
        : ProbeStatus.parseError;
    return ProbeResult(
      venue: venue,
      probe: probe,
      status: status,
      detail: e.message,
    );
  } on SocketException catch (e) {
    return ProbeResult(
      venue: venue,
      probe: probe,
      status: ProbeStatus.httpError,
      detail: e.message,
    );
  } on HttpException catch (e) {
    return ProbeResult(
      venue: venue,
      probe: probe,
      status: ProbeStatus.httpError,
      detail: e.message,
    );
  } catch (e) {
    final msg = '$e';
    final lower = msg.toLowerCase();
    final isHttp = lower.contains('http') ||
        lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('failed host');
    return ProbeResult(
      venue: venue,
      probe: probe,
      status: isHttp ? ProbeStatus.httpError : ProbeStatus.parseError,
      detail: msg,
    );
  }
}
