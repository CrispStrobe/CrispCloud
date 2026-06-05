// lib/services/provider_comparison_service.dart
//
// Provider comparison: cost/GB, features, privacy score, and recommendations.

import 'cloud_storage_interface.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Pricing information for a cloud provider.
class ProviderPricing {
  final double freeStorageGB;
  final double? costPerGBMonthly; // null = free tier only / unlimited free
  final String currency;
  final bool hasFreeplan;
  final String? paidPlanName;
  final double? paidPlanPriceMonthly;

  const ProviderPricing({
    required this.freeStorageGB,
    this.costPerGBMonthly,
    this.currency = 'USD',
    required this.hasFreeplan,
    this.paidPlanName,
    this.paidPlanPriceMonthly,
  });

  Map<String, dynamic> toJson() => {
        'freeStorageGB': freeStorageGB,
        'costPerGBMonthly': costPerGBMonthly,
        'currency': currency,
        'hasFreeplan': hasFreeplan,
        'paidPlanName': paidPlanName,
        'paidPlanPriceMonthly': paidPlanPriceMonthly,
      };

  factory ProviderPricing.fromJson(Map<String, dynamic> json) =>
      ProviderPricing(
        freeStorageGB: (json['freeStorageGB'] as num).toDouble(),
        costPerGBMonthly: json['costPerGBMonthly'] != null
            ? (json['costPerGBMonthly'] as num).toDouble()
            : null,
        currency: json['currency'] as String? ?? 'USD',
        hasFreeplan: json['hasFreeplan'] as bool,
        paidPlanName: json['paidPlanName'] as String?,
        paidPlanPriceMonthly: json['paidPlanPriceMonthly'] != null
            ? (json['paidPlanPriceMonthly'] as num).toDouble()
            : null,
      );
}

/// Feature flags for a cloud provider.
class ProviderFeatures {
  final bool e2eEncryption;
  final bool versionHistory;
  final bool sharing;
  final bool search;
  final bool thumbnails;
  final bool trash;
  final bool streaming;
  final bool multipart;
  final bool serverSideCopy;
  final bool fullTextSearch;

  const ProviderFeatures({
    required this.e2eEncryption,
    required this.versionHistory,
    required this.sharing,
    required this.search,
    required this.thumbnails,
    required this.trash,
    required this.streaming,
    required this.multipart,
    required this.serverSideCopy,
    required this.fullTextSearch,
  });

  /// Count of enabled features.
  int get featureCount {
    int count = 0;
    if (e2eEncryption) count++;
    if (versionHistory) count++;
    if (sharing) count++;
    if (search) count++;
    if (thumbnails) count++;
    if (trash) count++;
    if (streaming) count++;
    if (multipart) count++;
    if (serverSideCopy) count++;
    if (fullTextSearch) count++;
    return count;
  }

  Map<String, dynamic> toJson() => {
        'e2eEncryption': e2eEncryption,
        'versionHistory': versionHistory,
        'sharing': sharing,
        'search': search,
        'thumbnails': thumbnails,
        'trash': trash,
        'streaming': streaming,
        'multipart': multipart,
        'serverSideCopy': serverSideCopy,
        'fullTextSearch': fullTextSearch,
      };

  factory ProviderFeatures.fromJson(Map<String, dynamic> json) =>
      ProviderFeatures(
        e2eEncryption: json['e2eEncryption'] as bool,
        versionHistory: json['versionHistory'] as bool,
        sharing: json['sharing'] as bool,
        search: json['search'] as bool,
        thumbnails: json['thumbnails'] as bool,
        trash: json['trash'] as bool,
        streaming: json['streaming'] as bool,
        multipart: json['multipart'] as bool,
        serverSideCopy: json['serverSideCopy'] as bool,
        fullTextSearch: json['fullTextSearch'] as bool,
      );
}

/// Privacy and jurisdiction information.
class PrivacyInfo {
  final bool encryptionAtRest;
  final bool encryptionInTransit;
  final bool zeroKnowledge;
  final String jurisdiction; // ISO country code, e.g. 'DE', 'US', 'EU'
  final bool gdprCompliant;
  final bool openSource;

  const PrivacyInfo({
    required this.encryptionAtRest,
    required this.encryptionInTransit,
    required this.zeroKnowledge,
    required this.jurisdiction,
    required this.gdprCompliant,
    required this.openSource,
  });

  /// Computed privacy score 0–100.
  ///
  /// Algorithm:
  ///   +20  e2e / zero-knowledge client-side encryption
  ///   +15  zeroKnowledge (server cannot read files)
  ///   +15  encryptionAtRest
  ///   +10  encryptionInTransit
  ///   +15  GDPR compliant
  ///   +10  open source
  ///   +15  EU or DE or CH jurisdiction
  int get privacyScore {
    int score = 0;
    if (encryptionAtRest) score += 15;
    if (encryptionInTransit) score += 10;
    if (zeroKnowledge) score += 15;
    if (gdprCompliant) score += 15;
    if (openSource) score += 10;
    // EU jurisdiction bonus: DE, EU, CH, AT, NL, FR, SE, FI, NO ...
    const euJurisdictions = {'EU', 'DE', 'CH', 'AT', 'NL', 'FR', 'SE', 'FI', 'NO', 'DK', 'BE', 'LU'};
    if (euJurisdictions.contains(jurisdiction.toUpperCase())) score += 15;
    // e2eEncryption field maps to the +20 encryption bonus
    // We approximate it via zeroKnowledge (true only when e2e is client-side).
    // Additional +20 for explicit e2e: stored in encryptionAtRest + zeroKnowledge combo,
    // but we add the remaining 20 here if both are true.
    if (encryptionAtRest && zeroKnowledge) score += 20;
    // Clamp to 100
    return score.clamp(0, 100);
  }

  Map<String, dynamic> toJson() => {
        'encryptionAtRest': encryptionAtRest,
        'encryptionInTransit': encryptionInTransit,
        'zeroKnowledge': zeroKnowledge,
        'jurisdiction': jurisdiction,
        'gdprCompliant': gdprCompliant,
        'openSource': openSource,
        'privacyScore': privacyScore,
      };

  factory PrivacyInfo.fromJson(Map<String, dynamic> json) => PrivacyInfo(
        encryptionAtRest: json['encryptionAtRest'] as bool,
        encryptionInTransit: json['encryptionInTransit'] as bool,
        zeroKnowledge: json['zeroKnowledge'] as bool,
        jurisdiction: json['jurisdiction'] as String,
        gdprCompliant: json['gdprCompliant'] as bool,
        openSource: json['openSource'] as bool,
      );
}

/// Storage and rate limits.
class ProviderLimits {
  final double? maxFileSizeMB;    // null = unlimited
  final double? maxStorageGB;     // null = unlimited
  final int? rateLimitPerMinute;  // null = no stated limit
  final double? bandwidthLimitMBps; // null = no stated limit

  const ProviderLimits({
    this.maxFileSizeMB,
    this.maxStorageGB,
    this.rateLimitPerMinute,
    this.bandwidthLimitMBps,
  });

  Map<String, dynamic> toJson() => {
        'maxFileSizeMB': maxFileSizeMB,
        'maxStorageGB': maxStorageGB,
        'rateLimitPerMinute': rateLimitPerMinute,
        'bandwidthLimitMBps': bandwidthLimitMBps,
      };

  factory ProviderLimits.fromJson(Map<String, dynamic> json) => ProviderLimits(
        maxFileSizeMB: json['maxFileSizeMB'] != null
            ? (json['maxFileSizeMB'] as num).toDouble()
            : null,
        maxStorageGB: json['maxStorageGB'] != null
            ? (json['maxStorageGB'] as num).toDouble()
            : null,
        rateLimitPerMinute: json['rateLimitPerMinute'] as int?,
        bandwidthLimitMBps: json['bandwidthLimitMBps'] != null
            ? (json['bandwidthLimitMBps'] as num).toDouble()
            : null,
      );
}

/// Complete info record for one provider.
class ProviderInfo {
  final String name;
  final CloudProvider providerType;
  final ProviderPricing pricing;
  final ProviderFeatures features;
  final PrivacyInfo privacy;
  final ProviderLimits limits;

  const ProviderInfo({
    required this.name,
    required this.providerType,
    required this.pricing,
    required this.features,
    required this.privacy,
    required this.limits,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'providerType': providerType.name,
        'pricing': pricing.toJson(),
        'features': features.toJson(),
        'privacy': privacy.toJson(),
        'limits': limits.toJson(),
      };

  factory ProviderInfo.fromJson(Map<String, dynamic> json) => ProviderInfo(
        name: json['name'] as String,
        providerType: CloudProvider.values.firstWhere(
          (e) => e.name == json['providerType'],
        ),
        pricing: ProviderPricing.fromJson(
            json['pricing'] as Map<String, dynamic>),
        features: ProviderFeatures.fromJson(
            json['features'] as Map<String, dynamic>),
        privacy:
            PrivacyInfo.fromJson(json['privacy'] as Map<String, dynamic>),
        limits:
            ProviderLimits.fromJson(json['limits'] as Map<String, dynamic>),
      );
}

/// Use-case enum for recommendations.
enum ComparisonUseCase {
  backup,
  collaboration,
  privacy,
  budget,
  largeFiles,
}

/// Result of comparing a set of providers.
class ComparisonResult {
  final List<ProviderInfo> providers;
  final ProviderInfo? bestValue;      // cheapest cost/GB (paid tier)
  final ProviderInfo? mostPrivate;    // highest privacy score
  final ProviderInfo? mostFeatures;   // most feature flags true
  final ProviderInfo? bestForLargeFiles; // highest/unlimited max file size

  const ComparisonResult({
    required this.providers,
    this.bestValue,
    this.mostPrivate,
    this.mostFeatures,
    this.bestForLargeFiles,
  });
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Service providing built-in data and comparison logic for all 11 providers.
class ProviderComparisonService {
  ProviderComparisonService._();
  static final ProviderComparisonService instance =
      ProviderComparisonService._();

  // -------------------------------------------------------------------------
  // Built-in provider data
  // -------------------------------------------------------------------------

  static final Map<CloudProvider, ProviderInfo> _data = {
    // -----------------------------------------------------------------------
    // Filen — zero-knowledge, EU (DE), open source
    // Free 10 GB; paid plans from €2.99/mo (100 GB) → ~0.030 €/GB
    // -----------------------------------------------------------------------
    CloudProvider.filen: const ProviderInfo(
      name: 'Filen',
      providerType: CloudProvider.filen,
      pricing: const ProviderPricing(
        freeStorageGB: 10,
        costPerGBMonthly: 0.030,
        currency: 'EUR',
        hasFreeplan: true,
        paidPlanName: 'Filen 100 GB',
        paidPlanPriceMonthly: 2.99,
      ),
      features: const ProviderFeatures(
        e2eEncryption: true,
        versionHistory: true,
        sharing: true,
        search: false,
        thumbnails: false,
        trash: true,
        streaming: false,
        multipart: false,
        serverSideCopy: false,
        fullTextSearch: false,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: true,
        jurisdiction: 'DE',
        gdprCompliant: true,
        openSource: true,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: null,      // unlimited
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // Internxt — zero-knowledge, EU (ES), open source
    // Free 10 GB; paid plans from €0.99/mo (20 GB) → ~0.050 €/GB
    // -----------------------------------------------------------------------
    CloudProvider.internxt: const ProviderInfo(
      name: 'Internxt',
      providerType: CloudProvider.internxt,
      pricing: const ProviderPricing(
        freeStorageGB: 10,
        costPerGBMonthly: 0.050,
        currency: 'EUR',
        hasFreeplan: true,
        paidPlanName: 'Internxt 200 GB',
        paidPlanPriceMonthly: 3.49,
      ),
      features: const ProviderFeatures(
        e2eEncryption: true,
        versionHistory: true,
        sharing: true,
        search: false,
        thumbnails: false,
        trash: true,
        streaming: false,
        multipart: false,
        serverSideCopy: false,
        fullTextSearch: false,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: true,
        jurisdiction: 'EU',
        gdprCompliant: true,
        openSource: true,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: null,
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // SFTP — self-hosted, no inherent cost, jurisdiction = user-defined
    // We model it as free / unlimited (self-hosted).
    // -----------------------------------------------------------------------
    CloudProvider.sftp: const ProviderInfo(
      name: 'SFTP',
      providerType: CloudProvider.sftp,
      pricing: const ProviderPricing(
        freeStorageGB: double.infinity,
        costPerGBMonthly: 0.0,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: null,
        paidPlanPriceMonthly: null,
      ),
      features: const ProviderFeatures(
        e2eEncryption: false,
        versionHistory: false,
        sharing: false,
        search: false,
        thumbnails: false,
        trash: false,
        streaming: true,
        multipart: false,
        serverSideCopy: false,
        fullTextSearch: false,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: false,
        encryptionInTransit: true,  // SSH transport
        zeroKnowledge: false,
        jurisdiction: 'SELF',
        gdprCompliant: false,
        openSource: true,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: null,
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // WebDAV — self-hosted protocol, effectively free / unlimited
    // -----------------------------------------------------------------------
    CloudProvider.webdav: const ProviderInfo(
      name: 'WebDAV',
      providerType: CloudProvider.webdav,
      pricing: const ProviderPricing(
        freeStorageGB: double.infinity,
        costPerGBMonthly: 0.0,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: null,
        paidPlanPriceMonthly: null,
      ),
      features: const ProviderFeatures(
        e2eEncryption: false,
        versionHistory: false,
        sharing: false,
        search: false,
        thumbnails: false,
        trash: false,
        streaming: false,
        multipart: false,
        serverSideCopy: false,
        fullTextSearch: false,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: false,
        encryptionInTransit: true,  // TLS when https://
        zeroKnowledge: false,
        jurisdiction: 'SELF',
        gdprCompliant: false,
        openSource: true,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: null,
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // S3 (AWS) — ~$0.023/GB/mo (us-east-1 standard), no free storage tier
    // Free tier: 5 GB for 12 months, then pay-as-you-go
    // -----------------------------------------------------------------------
    CloudProvider.s3: const ProviderInfo(
      name: 'S3',
      providerType: CloudProvider.s3,
      pricing: const ProviderPricing(
        freeStorageGB: 5,
        costPerGBMonthly: 0.023,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: 'S3 Standard',
        paidPlanPriceMonthly: null, // pay-as-you-go
      ),
      features: const ProviderFeatures(
        e2eEncryption: false,
        versionHistory: true,
        sharing: true,
        search: false,
        thumbnails: false,
        trash: false,
        streaming: true,
        multipart: true,
        serverSideCopy: true,
        fullTextSearch: false,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: false,
        jurisdiction: 'US',
        gdprCompliant: true,
        openSource: false,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: null, // effectively unlimited (5 TB per object via multipart)
        maxStorageGB: null,
        rateLimitPerMinute: 3500,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // FTP — self-hosted legacy protocol
    // -----------------------------------------------------------------------
    CloudProvider.ftp: const ProviderInfo(
      name: 'FTP',
      providerType: CloudProvider.ftp,
      pricing: const ProviderPricing(
        freeStorageGB: double.infinity,
        costPerGBMonthly: 0.0,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: null,
        paidPlanPriceMonthly: null,
      ),
      features: const ProviderFeatures(
        e2eEncryption: false,
        versionHistory: false,
        sharing: false,
        search: false,
        thumbnails: false,
        trash: false,
        streaming: false,
        multipart: false,
        serverSideCopy: false,
        fullTextSearch: false,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: false,
        encryptionInTransit: false, // plain FTP; FTPS adds TLS
        zeroKnowledge: false,
        jurisdiction: 'SELF',
        gdprCompliant: false,
        openSource: true,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: null,
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // Google Drive — 15 GB free; Google One from $1.99/mo (100 GB) = $0.020/GB
    // -----------------------------------------------------------------------
    CloudProvider.gdrive: const ProviderInfo(
      name: 'Google Drive',
      providerType: CloudProvider.gdrive,
      pricing: const ProviderPricing(
        freeStorageGB: 15,
        costPerGBMonthly: 0.020,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: 'Google One 100 GB',
        paidPlanPriceMonthly: 1.99,
      ),
      features: const ProviderFeatures(
        e2eEncryption: false,
        versionHistory: true,
        sharing: true,
        search: true,
        thumbnails: true,
        trash: true,
        streaming: false,
        multipart: false,
        serverSideCopy: true,
        fullTextSearch: true,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: false,
        jurisdiction: 'US',
        gdprCompliant: true,
        openSource: false,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: 5 * 1024, // 5 GB per file
        maxStorageGB: null,
        rateLimitPerMinute: 100,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // OneDrive — 5 GB free; Microsoft 365 from $1.99/mo (100 GB) = $0.020/GB
    // -----------------------------------------------------------------------
    CloudProvider.onedrive: const ProviderInfo(
      name: 'OneDrive',
      providerType: CloudProvider.onedrive,
      pricing: const ProviderPricing(
        freeStorageGB: 5,
        costPerGBMonthly: 0.020,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: 'Microsoft 365 Basic',
        paidPlanPriceMonthly: 1.99,
      ),
      features: const ProviderFeatures(
        e2eEncryption: false,
        versionHistory: true,
        sharing: true,
        search: true,
        thumbnails: true,
        trash: true,
        streaming: false,
        multipart: false,
        serverSideCopy: true,
        fullTextSearch: true,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: false,
        jurisdiction: 'US',
        gdprCompliant: true,
        openSource: false,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: 250 * 1024, // 250 GB per file
        maxStorageGB: null,
        rateLimitPerMinute: 10000,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // Dropbox — 2 GB free; Plus from $9.99/mo (2 TB) = $0.005/GB
    // -----------------------------------------------------------------------
    CloudProvider.dropbox: const ProviderInfo(
      name: 'Dropbox',
      providerType: CloudProvider.dropbox,
      pricing: const ProviderPricing(
        freeStorageGB: 2,
        costPerGBMonthly: 0.005,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: 'Dropbox Plus',
        paidPlanPriceMonthly: 9.99,
      ),
      features: const ProviderFeatures(
        e2eEncryption: false,
        versionHistory: true,
        sharing: true,
        search: true,
        thumbnails: true,
        trash: true,
        streaming: false,
        multipart: false,
        serverSideCopy: true,
        fullTextSearch: true,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: false,
        jurisdiction: 'US',
        gdprCompliant: true,
        openSource: false,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: null,      // no hard per-file limit (web 50 GB cap)
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // Nextcloud — self-hosted open source; ~0 cost
    // -----------------------------------------------------------------------
    CloudProvider.nextcloud: const ProviderInfo(
      name: 'Nextcloud',
      providerType: CloudProvider.nextcloud,
      pricing: const ProviderPricing(
        freeStorageGB: double.infinity,
        costPerGBMonthly: 0.0,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: null,
        paidPlanPriceMonthly: null,
      ),
      features: const ProviderFeatures(
        e2eEncryption: true,   // E2E encryption app available
        versionHistory: true,
        sharing: true,
        search: true,
        thumbnails: false,
        trash: true,
        streaming: false,
        multipart: false,
        serverSideCopy: false,
        fullTextSearch: false,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: false,   // server-side encryption, not zero-knowledge
        jurisdiction: 'SELF',
        gdprCompliant: true,
        openSource: true,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: null,
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),

    // -----------------------------------------------------------------------
    // pCloud — 10 GB free; Premium 500 GB lifetime or $4.99/mo = $0.010/GB
    // EU option available (jurisdiction = EU)
    // -----------------------------------------------------------------------
    CloudProvider.pcloud: const ProviderInfo(
      name: 'pCloud',
      providerType: CloudProvider.pcloud,
      pricing: const ProviderPricing(
        freeStorageGB: 10,
        costPerGBMonthly: 0.010,
        currency: 'USD',
        hasFreeplan: true,
        paidPlanName: 'pCloud Premium 500 GB',
        paidPlanPriceMonthly: 4.99,
      ),
      features: const ProviderFeatures(
        e2eEncryption: false,   // pCloud Crypto is an add-on
        versionHistory: false,
        sharing: true,
        search: false,
        thumbnails: false,
        trash: true,
        streaming: false,
        multipart: false,
        serverSideCopy: false,
        fullTextSearch: false,
      ),
      privacy: const PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: false,
        jurisdiction: 'EU',
        gdprCompliant: true,
        openSource: false,
      ),
      limits: const ProviderLimits(
        maxFileSizeMB: null,
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),
    CloudProvider.azure: const ProviderInfo(
      name: 'Azure Blob Storage',
      providerType: CloudProvider.azure,
      pricing: ProviderPricing(
        freeStorageGB: 5,
        costPerGBMonthly: 0.018,
        currency: 'USD',
        hasFreePlan: true,
        paidPlanName: 'Pay-as-you-go',
        paidPlanPriceMonthly: null,
      ),
      features: ProviderFeatures(
        e2eEncryption: false,
        versionHistory: true,
        sharing: true,
        search: false,
        thumbnails: false,
        trash: true,
        streaming: true,
        multipart: true,
        serverSideCopy: true,
        fullTextSearch: false,
      ),
      privacy: PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: false,
        jurisdiction: 'US/EU (configurable)',
        gdprCompliant: true,
        openSource: false,
      ),
      limits: ProviderLimits(
        maxFileSizeMB: 190000,
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),
    CloudProvider.b2: const ProviderInfo(
      name: 'Backblaze B2',
      providerType: CloudProvider.b2,
      pricing: ProviderPricing(
        freeStorageGB: 10,
        costPerGBMonthly: 0.005,
        currency: 'USD',
        hasFreePlan: true,
        paidPlanName: 'Pay-as-you-go',
        paidPlanPriceMonthly: null,
      ),
      features: ProviderFeatures(
        e2eEncryption: false,
        versionHistory: true,
        sharing: true,
        search: false,
        thumbnails: false,
        trash: true,
        streaming: true,
        multipart: true,
        serverSideCopy: false,
        fullTextSearch: false,
      ),
      privacy: PrivacyInfo(
        encryptionAtRest: true,
        encryptionInTransit: true,
        zeroKnowledge: false,
        jurisdiction: 'US',
        gdprCompliant: true,
        openSource: false,
      ),
      limits: ProviderLimits(
        maxFileSizeMB: null,
        maxStorageGB: null,
        rateLimitPerMinute: null,
        bandwidthLimitMBps: null,
      ),
    ),
  };

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Returns built-in [ProviderInfo] for [providerType].
  ProviderInfo getProviderInfo(CloudProvider providerType) {
    final info = _data[providerType];
    if (info == null) {
      throw ArgumentError('No provider info for $providerType');
    }
    return info;
  }

  /// Returns all 11 built-in provider infos.
  List<ProviderInfo> getAllProviders() => List.unmodifiable(_data.values);

  /// Compare a subset of providers by their [CloudProvider] enum values.
  ///
  /// If [providerTypes] is empty, returns an empty [ComparisonResult].
  ComparisonResult compareProviders(List<CloudProvider> providerTypes) {
    if (providerTypes.isEmpty) {
      return const ComparisonResult(providers: []);
    }

    final infos = providerTypes.map(getProviderInfo).toList();

    final bestValue = _bestValue(infos);
    final mostPrivate = _mostPrivate(infos);
    final mostFeatures = _mostFeatures(infos);
    final bestForLargeFiles = _bestForLargeFiles(infos);

    return ComparisonResult(
      providers: infos,
      bestValue: bestValue,
      mostPrivate: mostPrivate,
      mostFeatures: mostFeatures,
      bestForLargeFiles: bestForLargeFiles,
    );
  }

  /// Rank all providers cheapest-first (free providers first, then by cost/GB).
  List<ProviderInfo> rankByPrice() {
    final all = List<ProviderInfo>.from(_data.values);
    all.sort((a, b) {
      final aCost = a.pricing.costPerGBMonthly ?? 0.0;
      final bCost = b.pricing.costPerGBMonthly ?? 0.0;
      return aCost.compareTo(bCost);
    });
    return all;
  }

  /// Rank all providers by privacy score (highest first).
  List<ProviderInfo> rankByPrivacy() {
    final all = List<ProviderInfo>.from(_data.values);
    all.sort(
        (a, b) => b.privacy.privacyScore.compareTo(a.privacy.privacyScore));
    return all;
  }

  /// Rank all providers by feature count (most features first).
  List<ProviderInfo> rankByFeatures() {
    final all = List<ProviderInfo>.from(_data.values);
    all.sort(
        (a, b) => b.features.featureCount.compareTo(a.features.featureCount));
    return all;
  }

  /// Return the recommended provider for a given [useCase].
  ProviderInfo getRecommendation(ComparisonUseCase useCase) {
    switch (useCase) {
      case ComparisonUseCase.backup:
        // Versioning + large file support + reliability → S3
        return getProviderInfo(CloudProvider.s3);

      case ComparisonUseCase.collaboration:
        // Sharing, native share links, full-text search → Google Drive
        return getProviderInfo(CloudProvider.gdrive);

      case ComparisonUseCase.privacy:
        // Highest privacy score → Filen (ZK + E2E + DE + open source + GDPR)
        final ranked = rankByPrivacy();
        return ranked.first;

      case ComparisonUseCase.budget:
        // Cheapest cost/GB on paid tier → Dropbox ($0.005/GB)
        final ranked = rankByPrice();
        // Skip truly-free self-hosted providers (cost == 0) to find cheapest
        // paid commercial option.
        return ranked.firstWhere(
          (p) =>
              (p.pricing.costPerGBMonthly ?? 0.0) > 0.0 &&
              p.pricing.freeStorageGB.isFinite,
          orElse: () => ranked.first,
        );

      case ComparisonUseCase.largeFiles:
        // Multipart + no file-size limit → S3 (5 TB via multipart)
        return getProviderInfo(CloudProvider.s3);
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  ProviderInfo? _bestValue(List<ProviderInfo> infos) {
    // Prefer providers with a real paid cost (not 0/null self-hosted).
    final commercial = infos.where(
        (p) => (p.pricing.costPerGBMonthly ?? 0.0) > 0.0 &&
               p.pricing.freeStorageGB.isFinite);
    if (commercial.isEmpty) {
      // Fall back to cheapest overall
      return infos.reduce((a, b) {
        final aCost = a.pricing.costPerGBMonthly ?? 0.0;
        final bCost = b.pricing.costPerGBMonthly ?? 0.0;
        return aCost <= bCost ? a : b;
      });
    }
    return commercial.reduce((a, b) {
      final aCost = a.pricing.costPerGBMonthly!;
      final bCost = b.pricing.costPerGBMonthly!;
      return aCost <= bCost ? a : b;
    });
  }

  ProviderInfo _mostPrivate(List<ProviderInfo> infos) => infos.reduce(
      (a, b) => a.privacy.privacyScore >= b.privacy.privacyScore ? a : b);

  ProviderInfo _mostFeatures(List<ProviderInfo> infos) => infos.reduce(
      (a, b) =>
          a.features.featureCount >= b.features.featureCount ? a : b);

  ProviderInfo _bestForLargeFiles(List<ProviderInfo> infos) {
    // Prefer null (unlimited) maxFileSizeMB, then largest value.
    final unlimited =
        infos.where((p) => p.limits.maxFileSizeMB == null).toList();
    if (unlimited.isNotEmpty) {
      // Among unlimited, prefer multipart support.
      final withMultipart =
          unlimited.where((p) => p.features.multipart).toList();
      return withMultipart.isNotEmpty ? withMultipart.first : unlimited.first;
    }
    return infos.reduce((a, b) {
      final aMB = a.limits.maxFileSizeMB ?? 0.0;
      final bMB = b.limits.maxFileSizeMB ?? 0.0;
      return aMB >= bMB ? a : b;
    });
  }
}
