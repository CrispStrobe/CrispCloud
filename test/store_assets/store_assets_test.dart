@Tags(['golden', 'store-assets'])

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _navy = Color(0xFF0D2A4A);
const _blue = Color(0xFF1565C0);
const _cyan = Color(0xFF26C6DA);
const _ink = Color(0xFF102235);
const _muted = Color(0xFF60758A);
const _surface = Color(0xFFF5F8FB);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final roboto = FontLoader('StoreRoboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
    await Future.wait([roboto.load(), materialIcons.load()]);
  });

  Future<void> renderPhone(
    WidgetTester tester,
    Widget child,
    String filename,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 1920);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_StoreApp(child: child));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(_StoreApp),
      matchesGoldenFile('../../store/google_play/assets/phone/$filename'),
    );
  }

  testWidgets('01 multi-cloud phone screenshot', (tester) async {
    await renderPhone(
      tester,
      const _MarketingFrame(
        eyebrow: 'MULTI-CLOUD, SIMPLIFIED',
        title: 'Every cloud in one place',
        subtitle: 'Connect encrypted clouds, servers and local storage.',
        preview: _CloudConnectionsPreview(),
      ),
      '01-every-cloud.png',
    );
  });

  testWidgets('02 file browser phone screenshot', (tester) async {
    await renderPhone(
      tester,
      const _MarketingFrame(
        eyebrow: 'BROWSE & ORGANIZE',
        title: 'Your files, clearly arranged',
        subtitle: 'Preview, rename and manage files without switching apps.',
        preview: _FileBrowserPreview(),
      ),
      '02-file-browser.png',
    );
  });

  testWidgets('03 transfer phone screenshot', (tester) async {
    await renderPhone(
      tester,
      const _MarketingFrame(
        eyebrow: 'CLOUD-TO-CLOUD',
        title: 'Move data with confidence',
        subtitle: 'Queue transfers and keep them running in the background.',
        preview: _TransferPreview(),
      ),
      '03-secure-transfers.png',
    );
  });

  testWidgets('04 privacy phone screenshot', (tester) async {
    await renderPhone(
      tester,
      const _MarketingFrame(
        eyebrow: 'PRIVATE BY DESIGN',
        title: 'Your credentials stay yours',
        subtitle:
            'Local secure storage, biometric lock and optional encryption.',
        preview: _PrivacyPreview(),
      ),
      '04-private-by-design.png',
    );
  });

  testWidgets('Google Play feature graphic', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const _StoreApp(child: _FeatureGraphic()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(_StoreApp),
      matchesGoldenFile(
        '../../store/google_play/assets/feature-graphic-1024x500.png',
      ),
    );
  });
}

class _StoreApp extends StatelessWidget {
  const _StoreApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: _blue),
          fontFamily: 'StoreRoboto',
        ),
        home: Scaffold(body: child),
      );
}

class _MarketingFrame extends StatelessWidget {
  const _MarketingFrame({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.preview,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget preview;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071B31), _navy, Color(0xFF0E6075)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/app_icon_master.png',
                        width: 34,
                        height: 34,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'CrispCloud',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: _cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.02,
                    fontWeight: FontWeight.w800,
                    fontSize: 33,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFBDD3E6),
                    height: 1.35,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: preview,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PreviewShell extends StatelessWidget {
  const _PreviewShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: _surface,
        child: Column(
          children: [
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.white,
              child: Row(
                children: [
                  const Icon(Icons.menu_rounded, color: _ink),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const Icon(Icons.search_rounded, color: _ink),
                  const SizedBox(width: 12),
                  const Icon(Icons.more_vert_rounded, color: _ink),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
}

class _CloudConnectionsPreview extends StatelessWidget {
  const _CloudConnectionsPreview();

  @override
  Widget build(BuildContext context) => _PreviewShell(
        title: 'Storage locations',
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: const [
            Text(
              'CONNECTED',
              style: TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: _ProviderCard(
                    icon: Icons.shield_outlined,
                    name: 'Filen',
                    detail: 'Encrypted cloud',
                    connected: true,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _ProviderCard(
                    icon: Icons.cloud_done_outlined,
                    name: 'Nextcloud',
                    detail: 'Personal server',
                    connected: true,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              'ADD A LOCATION',
              style: TextStyle(
                color: _muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 7),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ProviderChip(Icons.lock_outline, 'Internxt'),
                _ProviderChip(Icons.cloud_outlined, 'pCloud'),
                _ProviderChip(Icons.dns_outlined, 'S3'),
                _ProviderChip(Icons.terminal_outlined, 'SFTP'),
                _ProviderChip(Icons.folder_shared_outlined, 'WebDAV'),
                _ProviderChip(Icons.phone_android_outlined, 'Local'),
              ],
            ),
          ],
        ),
      );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.icon,
    required this.name,
    required this.detail,
    required this.connected,
  });

  final IconData icon;
  final String name;
  final String detail;
  final bool connected;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE6EF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: _blue, size: 27),
                if (connected)
                  const Icon(Icons.check_circle,
                      color: Color(0xFF2E9D67), size: 17),
              ],
            ),
            const SizedBox(height: 8),
            Text(name,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 2),
            Text(detail, style: const TextStyle(fontSize: 10, color: _muted)),
          ],
        ),
      );
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        width: 94,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDCE6EF)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _blue, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _ink),
              ),
            ),
          ],
        ),
      );
}

class _FileBrowserPreview extends StatelessWidget {
  const _FileBrowserPreview();

  @override
  Widget build(BuildContext context) => _PreviewShell(
        title: 'Files',
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
              color: Colors.white,
              child: const Row(
                children: [
                  _LocationPill(icon: Icons.phone_android, label: 'Local'),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 17, color: _muted),
                  ),
                  _LocationPill(icon: Icons.shield_outlined, label: 'Filen'),
                ],
              ),
            ),
            const _PathBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 4),
                children: const [
                  _FileRow(Icons.folder_rounded, Color(0xFFFFB74D), 'Projects',
                      '12 items'),
                  _FileRow(Icons.folder_rounded, Color(0xFFFFB74D), 'Photos',
                      '418 items'),
                  _FileRow(Icons.picture_as_pdf_outlined, Color(0xFFE45757),
                      'Product brief.pdf', '2.4 MB'),
                  _FileRow(Icons.image_outlined, Color(0xFF26A69A),
                      'Launch artwork.png', '8.1 MB'),
                  _FileRow(Icons.description_outlined, Color(0xFF5C6BC0),
                      'Release notes.md', '18 KB'),
                ],
              ),
            ),
            const _BottomActions(),
          ],
        ),
      );
}

class _LocationPill extends StatelessWidget {
  const _LocationPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF3FC),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: _blue, size: 15),
            const SizedBox(width: 5),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _PathBar extends StatelessWidget {
  const _PathBar();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFDCE6EF)),
        ),
        child: const Row(
          children: [
            Icon(Icons.home_outlined, color: _muted, size: 17),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                '/ CrispCloud / Documents',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: _muted),
              ),
            ),
          ],
        ),
      );
}

class _FileRow extends StatelessWidget {
  const _FileRow(this.icon, this.color, this.name, this.detail);
  final IconData icon;
  final Color color;
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(width: 11),
            Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _ink))),
            Text(detail, style: const TextStyle(fontSize: 10, color: _muted)),
          ],
        ),
      );
}

class _BottomActions extends StatelessWidget {
  const _BottomActions();

  @override
  Widget build(BuildContext context) => Container(
        height: 48,
        color: Colors.white,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _MiniAction(Icons.create_new_folder_outlined, 'New'),
            _MiniAction(Icons.upload_rounded, 'Upload'),
            _MiniAction(Icons.sync_rounded, 'Sync'),
            _MiniAction(Icons.grid_view_rounded, 'View'),
          ],
        ),
      );
}

class _MiniAction extends StatelessWidget {
  const _MiniAction(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: _blue),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 9, color: _muted)),
        ],
      );
}

class _TransferPreview extends StatelessWidget {
  const _TransferPreview();

  @override
  Widget build(BuildContext context) => _PreviewShell(
        title: 'Transfers',
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            const _TransferSummary(),
            const SizedBox(height: 12),
            const _TransferCard(
              name: 'Project archive.zip',
              route: 'Local  to  Filen',
              progress: .72,
              detail: '1.8 GB of 2.5 GB  •  24 MB/s',
            ),
            const SizedBox(height: 9),
            const _TransferCard(
              name: 'Camera uploads',
              route: 'Nextcloud  to  pCloud',
              progress: .38,
              detail: '96 of 252 files',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE9F7F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.notifications_active_outlined,
                      color: Color(0xFF27845E)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Transfers continue securely in the background',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF236B50),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TransferSummary extends StatelessWidget {
  const _TransferSummary();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_blue, Color(0xFF168DA0)]),
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0x33FFFFFF),
              child: Icon(Icons.swap_vert_rounded, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('2 active transfers',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('Encrypted in transit',
                      style: TextStyle(color: Color(0xFFD7F1F5), fontSize: 10)),
                ],
              ),
            ),
            Icon(Icons.pause_circle_outline, color: Colors.white),
          ],
        ),
      );
}

class _TransferCard extends StatelessWidget {
  const _TransferCard(
      {required this.name,
      required this.route,
      required this.progress,
      required this.detail});
  final String name;
  final String route;
  final double progress;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(13)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, color: _blue),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _ink))),
                Text('${(progress * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _blue)),
              ],
            ),
            const SizedBox(height: 6),
            Text(route, style: const TextStyle(fontSize: 10, color: _muted)),
            const SizedBox(height: 10),
            LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 7),
            Text(detail, style: const TextStyle(fontSize: 9, color: _muted)),
          ],
        ),
      );
}

class _PrivacyPreview extends StatelessWidget {
  const _PrivacyPreview();

  @override
  Widget build(BuildContext context) => _PreviewShell(
        title: 'Privacy & security',
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient:
                    const LinearGradient(colors: [Color(0xFF0D6376), _navy]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Color(0x22FFFFFF),
                    child: Icon(Icons.verified_user_outlined,
                        color: _cyan, size: 30),
                  ),
                  SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Private by default',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        SizedBox(height: 3),
                        Text('No ads. No tracking. No data mining.',
                            style: TextStyle(
                                color: Color(0xFFC7DCEB), fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _SecurityRow(Icons.fingerprint_rounded, 'Biometric app lock',
                'Use fingerprint or face unlock', true),
            const _SecurityRow(Icons.key_rounded, 'Secure credentials',
                'Protected by Android Keystore', true),
            const _SecurityRow(Icons.enhanced_encryption_outlined,
                'File encryption', 'Optional AES-256-GCM before upload', true),
            const _SecurityRow(Icons.analytics_outlined, 'External analytics',
                'No usage data leaves your device', false),
            const _SecurityRow(Icons.bug_report_outlined, 'Crash reports',
                'Stored locally for your review', true),
          ],
        ),
      );
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow(this.icon, this.title, this.subtitle, this.enabled);
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFEAF3FC),
              child: Icon(icon, color: _blue, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 9, color: _muted)),
                ],
              ),
            ),
            Icon(enabled ? Icons.check_circle : Icons.block,
                color: enabled ? const Color(0xFF2E9D67) : _muted, size: 18),
          ],
        ),
      );
}

class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071B31), _navy, Color(0xFF0B7788)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(right: -90, top: -120, child: _Glow(size: 420)),
            const Positioned(left: 360, bottom: -190, child: _Glow(size: 330)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 55),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(34),
                    child: Image.asset('assets/images/app_icon_master.png',
                        width: 190, height: 190),
                  ),
                  const SizedBox(width: 58),
                  const Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CrispCloud',
                            style: TextStyle(
                                color: _cyan,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .4)),
                        SizedBox(height: 12),
                        Text('All your clouds.\nOne private workspace.',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 52,
                                height: 1.02,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.6)),
                        SizedBox(height: 23),
                        Wrap(
                          spacing: 10,
                          children: [
                            _FeaturePill('Browse'),
                            _FeaturePill('Transfer'),
                            _FeaturePill('Encrypt'),
                            _FeaturePill('Sync'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Color(0x183DE8F2)),
      );
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x18FFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
      );
}
