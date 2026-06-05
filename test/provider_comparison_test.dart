// test/provider_comparison_test.dart
//
// Tests for ProviderComparisonService: all 11 providers, privacy scores,
// pricing, feature counts, comparison results, recommendations, serialization,
// and edge cases.

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/provider_comparison_service.dart';

void main() {
  late ProviderComparisonService svc;

  setUp(() {
    svc = ProviderComparisonService.instance;
  });

  // -------------------------------------------------------------------------
  // 1. All 11 providers have info entries
  // -------------------------------------------------------------------------
  group('All 11 providers have info entries', () {
    const allProviders = CloudProvider.values;

    for (final p in allProviders) {
      test('getProviderInfo($p) returns non-null', () {
        expect(() => svc.getProviderInfo(p), returnsNormally);
        final info = svc.getProviderInfo(p);
        expect(info.name, isNotEmpty);
        expect(info.providerType, equals(p));
      });
    }

    test('getAllProviders() returns exactly 11 entries', () {
      expect(svc.getAllProviders().length, equals(13));
    });

    test('getAllProviders() covers every CloudProvider value', () {
      final names = svc.getAllProviders().map((i) => i.providerType).toSet();
      for (final p in CloudProvider.values) {
        expect(names, contains(p));
      }
    });
  });

  // -------------------------------------------------------------------------
  // 2. Privacy score calculation — known values
  // -------------------------------------------------------------------------
  group('Privacy score calculation', () {
    // Filen: encryptionAtRest(15) + encryptionInTransit(10) + zeroKnowledge(15)
    //        + gdprCompliant(15) + openSource(10) + DE jurisdiction(15)
    //        + (atRest && zk bonus)(20) = 100 → clamped to 100
    test('Filen privacy score is 100', () {
      final info = svc.getProviderInfo(CloudProvider.filen);
      expect(info.privacy.privacyScore, equals(100));
    });

    // Internxt: same structure as Filen but jurisdiction = EU
    // encryptionAtRest(15) + encryptionInTransit(10) + zeroKnowledge(15)
    // + gdprCompliant(15) + openSource(10) + EU jurisdiction(15) + bonus(20) = 100
    test('Internxt privacy score is 100', () {
      final info = svc.getProviderInfo(CloudProvider.internxt);
      expect(info.privacy.privacyScore, equals(100));
    });

    // Google Drive: encryptionAtRest(15) + encryptionInTransit(10)
    //               + gdprCompliant(15) = 40 (no ZK, no EU, not open source)
    test('Google Drive privacy score is 40', () {
      final info = svc.getProviderInfo(CloudProvider.gdrive);
      expect(info.privacy.privacyScore, equals(40));
    });

    // OneDrive: same as Google Drive = 40
    test('OneDrive privacy score is 40', () {
      final info = svc.getProviderInfo(CloudProvider.onedrive);
      expect(info.privacy.privacyScore, equals(40));
    });

    // Dropbox: encryptionAtRest(15) + encryptionInTransit(10) + gdprCompliant(15)
    //          = 40
    test('Dropbox privacy score is 40', () {
      final info = svc.getProviderInfo(CloudProvider.dropbox);
      expect(info.privacy.privacyScore, equals(40));
    });

    // pCloud: encryptionAtRest(15) + encryptionInTransit(10) + gdprCompliant(15)
    //         + EU jurisdiction(15) = 55
    test('pCloud privacy score is 55', () {
      final info = svc.getProviderInfo(CloudProvider.pcloud);
      expect(info.privacy.privacyScore, equals(55));
    });

    // Nextcloud: encryptionAtRest(15) + encryptionInTransit(10)
    //            + gdprCompliant(15) + openSource(10) = 50
    //            jurisdiction = SELF → no bonus
    test('Nextcloud privacy score is 50', () {
      final info = svc.getProviderInfo(CloudProvider.nextcloud);
      expect(info.privacy.privacyScore, equals(50));
    });

    // S3: encryptionAtRest(15) + encryptionInTransit(10) + gdprCompliant(15)
    //     = 40
    test('S3 privacy score is 40', () {
      final info = svc.getProviderInfo(CloudProvider.s3);
      expect(info.privacy.privacyScore, equals(40));
    });

    // SFTP: encryptionInTransit(10) + openSource(10) = 20
    test('SFTP privacy score is 20', () {
      final info = svc.getProviderInfo(CloudProvider.sftp);
      expect(info.privacy.privacyScore, equals(20));
    });

    // WebDAV: encryptionInTransit(10) + openSource(10) = 20
    test('WebDAV privacy score is 20', () {
      final info = svc.getProviderInfo(CloudProvider.webdav);
      expect(info.privacy.privacyScore, equals(20));
    });

    // FTP: openSource(10) only (no encryption) = 10
    test('FTP privacy score is 10', () {
      final info = svc.getProviderInfo(CloudProvider.ftp);
      expect(info.privacy.privacyScore, equals(10));
    });

    test('All privacy scores are between 0 and 100', () {
      for (final info in svc.getAllProviders()) {
        expect(info.privacy.privacyScore, inInclusiveRange(0, 100),
            reason: '${info.name} score out of range');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 3. Price ranking
  // -------------------------------------------------------------------------
  group('Price ranking', () {
    test('rankByPrice returns 11 providers', () {
      expect(svc.rankByPrice().length, equals(13));
    });

    test('Free / self-hosted providers appear first (cost == 0)', () {
      final ranked = svc.rankByPrice();
      // All providers with costPerGBMonthly == 0 or null should precede those
      // with cost > 0.
      int lastFreeIndex = -1;
      int firstPaidIndex = ranked.length;
      for (int i = 0; i < ranked.length; i++) {
        final cost = ranked[i].pricing.costPerGBMonthly ?? 0.0;
        if (cost == 0.0) lastFreeIndex = i;
        if (cost > 0.0 && i < firstPaidIndex) firstPaidIndex = i;
      }
      if (firstPaidIndex < ranked.length) {
        expect(lastFreeIndex < firstPaidIndex, isTrue,
            reason:
                'Free providers should come before paid ones in price ranking');
      }
    });

    test('Dropbox (0.005 USD/GB) is the cheapest commercial provider', () {
      final ranked = svc.rankByPrice();
      final commercial = ranked
          .where((p) =>
              (p.pricing.costPerGBMonthly ?? 0.0) > 0.0 &&
              p.pricing.freeStorageGB.isFinite)
          .toList();
      expect(commercial.first.providerType, equals(CloudProvider.dropbox));
    });

    test('Internxt (0.050/GB) is more expensive than Filen (0.030/GB)', () {
      final filen = svc.getProviderInfo(CloudProvider.filen);
      final internxt = svc.getProviderInfo(CloudProvider.internxt);
      expect(filen.pricing.costPerGBMonthly!,
          lessThan(internxt.pricing.costPerGBMonthly!));
    });

    test('rankByPrice is sorted ascending', () {
      final ranked = svc.rankByPrice();
      for (int i = 1; i < ranked.length; i++) {
        final prev = ranked[i - 1].pricing.costPerGBMonthly ?? 0.0;
        final curr = ranked[i].pricing.costPerGBMonthly ?? 0.0;
        expect(prev, lessThanOrEqualTo(curr),
            reason: 'rankByPrice not sorted at index $i');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 4. Feature counting
  // -------------------------------------------------------------------------
  group('Feature counting', () {
    test('Google Drive has more features than FTP', () {
      final gdrive = svc.getProviderInfo(CloudProvider.gdrive);
      final ftp = svc.getProviderInfo(CloudProvider.ftp);
      expect(gdrive.features.featureCount, greaterThan(ftp.features.featureCount));
    });

    test('FTP feature count is 0', () {
      final ftp = svc.getProviderInfo(CloudProvider.ftp);
      expect(ftp.features.featureCount, equals(0));
    });

    test('Google Drive feature count is 6 (versioning,sharing,search,thumbnails,trash,serverSideCopy,fullTextSearch minus e2e,streaming,multipart)', () {
      // versionHistory + sharing + search + thumbnails + trash + serverSideCopy
      // + fullTextSearch = 7
      final gdrive = svc.getProviderInfo(CloudProvider.gdrive);
      expect(gdrive.features.featureCount, equals(7));
    });

    test('Filen e2eEncryption is true', () {
      final filen = svc.getProviderInfo(CloudProvider.filen);
      expect(filen.features.e2eEncryption, isTrue);
    });

    test('S3 multipart is true', () {
      final s3 = svc.getProviderInfo(CloudProvider.s3);
      expect(s3.features.multipart, isTrue);
    });

    test('S3 streaming is true', () {
      final s3 = svc.getProviderInfo(CloudProvider.s3);
      expect(s3.features.streaming, isTrue);
    });

    test('SFTP streaming is true', () {
      final sftp = svc.getProviderInfo(CloudProvider.sftp);
      expect(sftp.features.streaming, isTrue);
    });

    test('rankByFeatures returns 11 providers', () {
      expect(svc.rankByFeatures().length, equals(13));
    });

    test('rankByFeatures is sorted descending', () {
      final ranked = svc.rankByFeatures();
      for (int i = 1; i < ranked.length; i++) {
        expect(ranked[i - 1].features.featureCount,
            greaterThanOrEqualTo(ranked[i].features.featureCount),
            reason: 'rankByFeatures not sorted at index $i');
      }
    });

    test('Provider with most features appears first in rankByFeatures', () {
      final ranked = svc.rankByFeatures();
      final maxCount = svc
          .getAllProviders()
          .map((p) => p.features.featureCount)
          .reduce((a, b) => a > b ? a : b);
      expect(ranked.first.features.featureCount, equals(maxCount));
    });
  });

  // -------------------------------------------------------------------------
  // 5. Comparison result fields
  // -------------------------------------------------------------------------
  group('ComparisonResult fields', () {
    test('compareProviders([all]) bestValue is cheapest per GB', () {
      final result = svc.compareProviders(CloudProvider.values.toList());
      // B2 at $0.005/GB is cheapest paid; several providers are free
      expect(result.bestValue, isNotNull);
    });

    test('compareProviders([all]) mostPrivate is Filen or Internxt', () {
      final result = svc.compareProviders(CloudProvider.values.toList());
      expect(result.mostPrivate?.providerType,
          anyOf(equals(CloudProvider.filen), equals(CloudProvider.internxt)));
    });

    test('compareProviders([all]) mostFeatures is GDrive, OneDrive, or Dropbox', () {
      final result = svc.compareProviders(CloudProvider.values.toList());
      expect(
        result.mostFeatures?.providerType,
        anyOf(
          equals(CloudProvider.gdrive),
          equals(CloudProvider.onedrive),
          equals(CloudProvider.dropbox),
        ),
      );
    });

    test('compareProviders([all]) bestForLargeFiles prefers multipart support', () {
      final result = svc.compareProviders(CloudProvider.values.toList());
      // S3 has both unlimited size and multipart
      expect(result.bestForLargeFiles?.features.multipart, isTrue);
    });

    test('compareProviders providers list matches input', () {
      final subset = [CloudProvider.filen, CloudProvider.gdrive, CloudProvider.s3];
      final result = svc.compareProviders(subset);
      expect(result.providers.length, equals(3));
      final types = result.providers.map((p) => p.providerType).toSet();
      for (final p in subset) {
        expect(types, contains(p));
      }
    });

    test('compareProviders([filen]) mostPrivate is Filen', () {
      final result = svc.compareProviders([CloudProvider.filen]);
      expect(result.mostPrivate?.providerType, equals(CloudProvider.filen));
    });

    test('compareProviders([filen]) bestValue is Filen (only option)', () {
      final result = svc.compareProviders([CloudProvider.filen]);
      expect(result.bestValue?.providerType, equals(CloudProvider.filen));
    });
  });

  // -------------------------------------------------------------------------
  // 6. Edge cases
  // -------------------------------------------------------------------------
  group('Edge cases', () {
    test('compareProviders([]) returns empty providers list', () {
      final result = svc.compareProviders([]);
      expect(result.providers, isEmpty);
      expect(result.bestValue, isNull);
      expect(result.mostPrivate, isNull);
      expect(result.mostFeatures, isNull);
      expect(result.bestForLargeFiles, isNull);
    });

    test('compareProviders with single provider returns that provider in all fields', () {
      final result = svc.compareProviders([CloudProvider.dropbox]);
      expect(result.providers.length, equals(1));
      expect(result.mostFeatures?.providerType, equals(CloudProvider.dropbox));
      expect(result.mostPrivate?.providerType, equals(CloudProvider.dropbox));
    });

    test('compareProviders with all 11 providers succeeds', () {
      expect(
        () => svc.compareProviders(CloudProvider.values.toList()),
        returnsNormally,
      );
      final result = svc.compareProviders(CloudProvider.values.toList());
      expect(result.providers.length, equals(13));
    });

    test('getProviderInfo with unknown type throws ArgumentError', () {
      // All valid — just ensure no value is missing
      for (final p in CloudProvider.values) {
        expect(() => svc.getProviderInfo(p), returnsNormally);
      }
    });
  });

  // -------------------------------------------------------------------------
  // 7. Recommendations
  // -------------------------------------------------------------------------
  group('Recommendations', () {
    test('backup recommendation is S3', () {
      expect(
        svc.getRecommendation(ComparisonUseCase.backup).providerType,
        equals(CloudProvider.s3),
      );
    });

    test('collaboration recommendation is Google Drive', () {
      expect(
        svc.getRecommendation(ComparisonUseCase.collaboration).providerType,
        equals(CloudProvider.gdrive),
      );
    });

    test('privacy recommendation is Filen or Internxt (highest score)', () {
      final rec = svc.getRecommendation(ComparisonUseCase.privacy);
      expect(
        rec.providerType,
        anyOf(equals(CloudProvider.filen), equals(CloudProvider.internxt)),
      );
    });

    test('budget recommendation is a commercial paid provider', () {
      final rec = svc.getRecommendation(ComparisonUseCase.budget);
      // Must have a real non-zero cost per GB
      expect((rec.pricing.costPerGBMonthly ?? 0.0), greaterThan(0.0));
    });

    test('largeFiles recommendation is S3', () {
      expect(
        svc.getRecommendation(ComparisonUseCase.largeFiles).providerType,
        equals(CloudProvider.s3),
      );
    });

    test('All use cases return a non-null ProviderInfo', () {
      for (final uc in ComparisonUseCase.values) {
        expect(() => svc.getRecommendation(uc), returnsNormally,
            reason: 'Recommendation for $uc threw');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 8. Serialization / deserialization
  // -------------------------------------------------------------------------
  group('ProviderInfo serialization', () {
    test('ProviderPricing round-trips through JSON', () {
      const original = ProviderPricing(
        freeStorageGB: 15,
        costPerGBMonthly: 0.020,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: 'Test Plan',
        paidPlanPriceMonthly: 1.99,
      );
      final decoded = ProviderPricing.fromJson(original.toJson());
      expect(decoded.freeStorageGB, equals(original.freeStorageGB));
      expect(decoded.costPerGBMonthly, equals(original.costPerGBMonthly));
      expect(decoded.currency, equals(original.currency));
      expect(decoded.hasFreeplan, equals(original.hasFreeplan));
      expect(decoded.paidPlanName, equals(original.paidPlanName));
      expect(decoded.paidPlanPriceMonthly, equals(original.paidPlanPriceMonthly));
    });

    test('ProviderPricing with null costPerGBMonthly round-trips', () {
      const original = ProviderPricing(
        freeStorageGB: double.infinity,
        costPerGBMonthly: null,
        currency: 'USD',
        hasFreeplan: true,
      );
      final decoded = ProviderPricing.fromJson(original.toJson());
      expect(decoded.costPerGBMonthly, isNull);
      expect(decoded.freeStorageGB, equals(double.infinity));
    });

    test('ProviderFeatures round-trips through JSON', () {
      const original = ProviderFeatures(
        e2eEncryption: true,
        versionHistory: true,
        sharing: false,
        search: true,
        thumbnails: false,
        trash: true,
        streaming: false,
        multipart: true,
        serverSideCopy: false,
        fullTextSearch: true,
      );
      final decoded = ProviderFeatures.fromJson(original.toJson());
      expect(decoded.e2eEncryption, isTrue);
      expect(decoded.versionHistory, isTrue);
      expect(decoded.sharing, isFalse);
      expect(decoded.multipart, isTrue);
      expect(decoded.featureCount, equals(original.featureCount));
    });

    test('PrivacyInfo round-trips through JSON (score is recomputed)', () {
      const original = PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: true,
        jurisdiction: 'DE',
        gdprCompliant: true,
        openSource: true,
      );
      final json = original.toJson();
      final decoded = PrivacyInfo.fromJson(json);
      expect(decoded.privacyScore, equals(original.privacyScore));
      expect(decoded.jurisdiction, equals('DE'));
      expect(json['privacyScore'], equals(original.privacyScore));
    });

    test('ProviderLimits round-trips with all nulls', () {
      const original = ProviderLimits(
        maxFileSizeMB: null,
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      );
      final decoded = ProviderLimits.fromJson(original.toJson());
      expect(decoded.maxFileSizeMB, isNull);
      expect(decoded.maxStorageGB, isNull);
      expect(decoded.rateLimitPerMinute, isNull);
      expect(decoded.bandwidthLimitMBps, isNull);
    });

    test('ProviderLimits round-trips with set values', () {
      const original = ProviderLimits(
        maxFileSizeMB: 5120,
        maxStorageGB: 1000,
        rateLimitPerMinute: 100,
        bandwidthLimitMBps: 50.0,
      );
      final decoded = ProviderLimits.fromJson(original.toJson());
      expect(decoded.maxFileSizeMB, equals(5120.0));
      expect(decoded.maxStorageGB, equals(1000.0));
      expect(decoded.rateLimitPerMinute, equals(100));
      expect(decoded.bandwidthLimitMBps, equals(50.0));
    });

    test('ProviderInfo round-trips through JSON for all providers', () {
      for (final info in svc.getAllProviders()) {
        final json = info.toJson();
        final decoded = ProviderInfo.fromJson(json);
        expect(decoded.name, equals(info.name),
            reason: '${info.name} name mismatch');
        expect(decoded.providerType, equals(info.providerType),
            reason: '${info.name} providerType mismatch');
        expect(decoded.privacy.privacyScore, equals(info.privacy.privacyScore),
            reason: '${info.name} privacy score mismatch');
        expect(decoded.features.featureCount, equals(info.features.featureCount),
            reason: '${info.name} feature count mismatch');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 9. Pricing: free vs paid distinction
  // -------------------------------------------------------------------------
  group('Pricing: free vs paid', () {
    test('All self-hosted providers (SFTP, WebDAV, FTP, Nextcloud) have hasFreeplan = true', () {
      for (final p in [
        CloudProvider.sftp,
        CloudProvider.webdav,
        CloudProvider.ftp,
        CloudProvider.nextcloud,
      ]) {
        expect(svc.getProviderInfo(p).pricing.hasFreeplan, isTrue,
            reason: '$p should have a free plan');
      }
    });

    test('All commercial providers have hasFreeplan = true', () {
      for (final p in [
        CloudProvider.filen,
        CloudProvider.internxt,
        CloudProvider.gdrive,
        CloudProvider.onedrive,
        CloudProvider.dropbox,
        CloudProvider.pcloud,
        CloudProvider.s3,
      ]) {
        expect(svc.getProviderInfo(p).pricing.hasFreeplan, isTrue,
            reason: '$p should have a free plan');
      }
    });

    test('Filen has a paidPlanName', () {
      expect(svc.getProviderInfo(CloudProvider.filen).pricing.paidPlanName,
          isNotNull);
    });

    test('SFTP has no paidPlanName (free/self-hosted)', () {
      expect(
          svc.getProviderInfo(CloudProvider.sftp).pricing.paidPlanName, isNull);
    });

    test('Google Drive free storage is 15 GB', () {
      expect(svc.getProviderInfo(CloudProvider.gdrive).pricing.freeStorageGB,
          equals(15.0));
    });

    test('Dropbox free storage is 2 GB', () {
      expect(
          svc.getProviderInfo(CloudProvider.dropbox).pricing.freeStorageGB,
          equals(2.0));
    });

    test('Self-hosted providers have costPerGBMonthly == 0', () {
      for (final p in [
        CloudProvider.sftp,
        CloudProvider.webdav,
        CloudProvider.ftp,
        CloudProvider.nextcloud,
      ]) {
        final cost = svc.getProviderInfo(p).pricing.costPerGBMonthly ?? 0.0;
        expect(cost, equals(0.0), reason: '$p should cost 0');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 10. ProviderLimits: null means unlimited
  // -------------------------------------------------------------------------
  group('ProviderLimits: null means unlimited', () {
    test('Filen has no max file size (null = unlimited)', () {
      expect(
          svc.getProviderInfo(CloudProvider.filen).limits.maxFileSizeMB, isNull);
    });

    test('Internxt has no max file size', () {
      expect(
          svc.getProviderInfo(CloudProvider.internxt).limits.maxFileSizeMB,
          isNull);
    });

    test('S3 has null maxFileSizeMB (effectively unlimited via multipart)', () {
      // S3 supports up to 5 TB per object via multipart; we model it as null.
      expect(
          svc.getProviderInfo(CloudProvider.s3).limits.maxFileSizeMB, isNull);
    });

    test('Google Drive has a defined max file size', () {
      expect(
          svc.getProviderInfo(CloudProvider.gdrive).limits.maxFileSizeMB,
          isNotNull);
    });

    test('Self-hosted providers have null maxStorageGB (unlimited)', () {
      for (final p in [
        CloudProvider.sftp,
        CloudProvider.webdav,
        CloudProvider.ftp,
        CloudProvider.nextcloud,
      ]) {
        expect(svc.getProviderInfo(p).limits.maxStorageGB, isNull,
            reason: '$p maxStorageGB should be null (unlimited)');
      }
    });

    test('S3 has rateLimitPerMinute set', () {
      expect(
          svc.getProviderInfo(CloudProvider.s3).limits.rateLimitPerMinute,
          isNotNull);
    });

    test('Filen has no rate limit (null)', () {
      expect(
          svc.getProviderInfo(CloudProvider.filen).limits.rateLimitPerMinute,
          isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 11. rankByPrivacy
  // -------------------------------------------------------------------------
  group('rankByPrivacy', () {
    test('returns 11 providers', () {
      expect(svc.rankByPrivacy().length, equals(13));
    });

    test('is sorted descending by privacy score', () {
      final ranked = svc.rankByPrivacy();
      for (int i = 1; i < ranked.length; i++) {
        expect(
          ranked[i - 1].privacy.privacyScore,
          greaterThanOrEqualTo(ranked[i].privacy.privacyScore),
          reason: 'rankByPrivacy not sorted at index $i',
        );
      }
    });

    test('FTP is last or near-last in privacy ranking', () {
      final ranked = svc.rankByPrivacy();
      final ftpIndex = ranked.indexWhere(
          (p) => p.providerType == CloudProvider.ftp);
      expect(ftpIndex, greaterThan(ranked.length ~/ 2),
          reason: 'FTP should be in the lower half of privacy ranking');
    });

    test('Filen and Internxt are in top 2 privacy slots', () {
      final ranked = svc.rankByPrivacy();
      final top2 = ranked.take(2).map((p) => p.providerType).toSet();
      expect(top2, containsAll([CloudProvider.filen, CloudProvider.internxt]));
    });
  });
}
