import 'dart:async';

import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

/// A provider whose one-time load is slow and whose checks are fast, like the
/// shipped German dictionary on a cold isolate.
class _ColdProvider extends OfficeProofingProvider {
  _ColdProvider(this.load);

  final Future<void> load;
  int warmUps = 0;
  int checks = 0;
  bool disposed = false;

  @override
  String get id => 'cold';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<void> warmUp() {
    warmUps++;
    return load;
  }

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    checks++;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
    );
  }

  @override
  Future<void> dispose() async => disposed = true;
}

OfficeProofingRequest _request() => OfficeProofingRequest(
  documentId: 'warm-up',
  blockId: 'paragraph',
  revision: 1,
  text: 'Ein Satz.',
  language: 'de-DE',
);

void main() {
  test('a cold load is not charged to the first request deadline', () async {
    final provider = _ColdProvider(
      Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    final service = OfficeProofingService(
      providers: <OfficeProofingProvider>[provider],
      timeout: const Duration(milliseconds: 100),
    );
    addTearDown(service.dispose);
    final report = await service.check(_request());
    expect(report.complete, isTrue, reason: report.results.single.message);
    expect(provider.warmUps, 1);
    expect(provider.checks, 1);
    expect(provider.disposed, isFalse);
  });

  test('a load beyond its own bound fails without disposing', () async {
    final load = Completer<void>();
    final provider = _ColdProvider(load.future);
    final service = OfficeProofingService(
      providers: <OfficeProofingProvider>[provider],
      timeout: const Duration(seconds: 5),
      warmUpTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(service.dispose);
    final first = await service.check(_request());
    expect(first.complete, isFalse);
    expect(first.results.single.status, OfficeProofingStatus.failed);
    expect(provider.checks, 0);
    expect(provider.disposed, isFalse);
    load.complete();
    final second = await service.check(_request());
    expect(second.complete, isTrue);
    expect(provider.checks, 1);
  });

  test('warmUpTimeout must be positive', () {
    expect(
      () => OfficeProofingService(
        providers: const <OfficeProofingProvider>[],
        warmUpTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}
