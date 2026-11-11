import 'package:crisp_storage/src/rust_library.dart';
import 'package:test/test.dart';

void main() {
  group('RustTarget.of', () {
    final cases = <(String, String, bool), String?>{
      ('iOS', 'arm64', false): 'aarch64-apple-ios',
      ('iOS', 'arm64', true): 'aarch64-apple-ios-sim',
      ('iOS', 'x64', true): 'x86_64-apple-ios',
      ('iOS', 'x64', false): null,
      ('iOS', 'arm', false): null,
      ('macOS', 'arm64', false): 'aarch64-apple-darwin',
      ('macOS', 'x64', false): 'x86_64-apple-darwin',
      ('macOS', 'riscv64', false): null,
      ('linux', 'x64', false): 'x86_64-unknown-linux-gnu',
      ('linux', 'arm64', false): 'aarch64-unknown-linux-gnu',
      ('linux', 'ia32', false): null,
      ('windows', 'x64', false): 'x86_64-pc-windows-msvc',
      ('windows', 'arm64', false): 'aarch64-pc-windows-msvc',
      ('android', 'arm64', false): null,
      ('fuchsia', 'x64', false): null,
      // package:code_assets reports OS names in lowercase.
      ('ios', 'arm64', true): 'aarch64-apple-ios-sim',
      ('macos', 'x64', false): 'x86_64-apple-darwin',
      ('MACOS', 'arm64', false): 'aarch64-apple-darwin',
    };
    cases.forEach((input, triple) {
      test(
        '${input.$1} ${input.$2}${input.$3 ? ' simulator' : ''} → $triple',
        () {
          final target = RustTarget.of(
            os: input.$1,
            architecture: input.$2,
            iosSimulator: input.$3,
          );
          expect(target?.triple, triple);
        },
      );
    });

    test('file names match each platform library convention', () {
      expect(
        RustTarget.of(os: 'iOS', architecture: 'arm64')!.fileName,
        'libcrisp_smb_bridge.dylib',
      );
      expect(
        RustTarget.of(os: 'macOS', architecture: 'x64')!.cargoOutput,
        'libcrisp_smb_bridge.dylib',
      );
      expect(
        RustTarget.of(os: 'linux', architecture: 'x64')!.fileName,
        'libcrisp_smb_bridge.so',
      );
      expect(
        RustTarget.of(os: 'windows', architecture: 'x64')!.fileName,
        'crisp_smb_bridge.dll',
      );
    });

    test('simulator flag is ignored outside iOS', () {
      expect(
        RustTarget.of(
          os: 'macOS',
          architecture: 'arm64',
          iosSimulator: true,
        )!.triple,
        'aarch64-apple-darwin',
      );
    });
  });

  group('appleSdkName', () {
    test('maps Apple targets to xcrun SDK names', () {
      expect(appleSdkName(os: 'ios'), 'iphoneos');
      expect(appleSdkName(os: 'iOS', iosSimulator: true), 'iphonesimulator');
      expect(appleSdkName(os: 'macos'), 'macosx');
      expect(appleSdkName(os: 'macos', iosSimulator: true), 'macosx');
    });
    test('has no SDK for other systems', () {
      for (final os in ['linux', 'windows', 'android', 'fuchsia']) {
        expect(appleSdkName(os: os), isNull, reason: os);
      }
    });
  });

  group('findCargo', () {
    bool Function(String) only(Set<String> paths) => paths.contains;

    test('prefers an explicit CARGO', () {
      expect(
        findCargo({
          'CARGO': '/opt/rust/cargo',
          'PATH': '/usr/bin',
        }, exists: only({'/opt/rust/cargo', '/usr/bin/cargo'})),
        '/opt/rust/cargo',
      );
    });

    test('ignores a CARGO that does not exist', () {
      expect(
        findCargo({
          'CARGO': '/missing/cargo',
          'PATH': '/usr/bin',
        }, exists: only({'/usr/bin/cargo'})),
        '/usr/bin/cargo',
      );
    });

    test('searches PATH in order and skips empty entries', () {
      expect(
        findCargo({
          'PATH': '::/a:/b:/c',
        }, exists: only({'/b/cargo', '/c/cargo'})),
        '/b/cargo',
      );
    });

    test('falls back to ~/.cargo/bin for Xcode build phases', () {
      expect(
        findCargo({
          'PATH': '/usr/bin:/bin',
          'HOME': '/Users/dev',
        }, exists: only({'/Users/dev/.cargo/bin/cargo'})),
        '/Users/dev/.cargo/bin/cargo',
      );
    });

    test('CARGO_HOME wins over HOME', () {
      expect(
        findCargo(
          {'HOME': '/Users/dev', 'CARGO_HOME': '/opt/cargo'},
          exists: only({'/opt/cargo/bin/cargo', '/Users/dev/.cargo/bin/cargo'}),
        ),
        '/opt/cargo/bin/cargo',
      );
    });

    test('Windows uses ; separators, backslashes and cargo.exe', () {
      expect(
        findCargo(
          {'PATH': r'C:\x;C:\rust\bin', 'USERPROFILE': r'C:\Users\dev'},
          exists: only({r'C:\rust\bin\cargo.exe'}),
          windows: true,
        ),
        r'C:\rust\bin\cargo.exe',
      );
      expect(
        findCargo(
          {'USERPROFILE': r'C:\Users\dev'},
          exists: only({r'C:\Users\dev\.cargo\bin\cargo.exe'}),
          windows: true,
        ),
        r'C:\Users\dev\.cargo\bin\cargo.exe',
      );
    });

    test('returns the bare name when nothing is found', () {
      expect(findCargo({}, exists: (_) => false), 'cargo');
      expect(findCargo({}, exists: (_) => false, windows: true), 'cargo.exe');
    });
  });

  group('bundledRustLibraryCandidates', () {
    test('iOS looks in the app Frameworks folder first, then @rpath', () {
      final c = bundledRustLibraryCandidates(
        os: 'ios',
        executable:
            '/private/var/containers/Bundle/Application/X/Runner.app/Runner',
      );
      expect(
        c.first,
        '/private/var/containers/Bundle/Application/X/Runner.app/Frameworks/'
        'libcrisp_smb_bridge.framework/libcrisp_smb_bridge',
      );
      expect(c, contains('@rpath/crisp_smb_bridge.framework/crisp_smb_bridge'));
      expect(
        c.indexWhere((p) => p.startsWith('@rpath')),
        greaterThan(c.lastIndexWhere((p) => p.startsWith('/'))),
      );
    });

    test('macOS resolves Contents/Frameworks relative to MacOS/', () {
      final c = bundledRustLibraryCandidates(
        os: 'macos',
        executable: '/Applications/Crisper.app/Contents/MacOS/Crisper',
      );
      expect(
        c.first,
        '/Applications/Crisper.app/Contents/MacOS/../Frameworks/'
        'libcrisp_smb_bridge.framework/libcrisp_smb_bridge',
      );
      expect(
        c,
        contains(
          '/Applications/Crisper.app/Contents/MacOS/../Frameworks/libcrisp_smb_bridge.dylib',
        ),
      );
      expect(
        bundledRustLibraryCandidates(
          os: 'macos',
          executable: '/opt/crisp/bin/crisp',
        ),
        contains('/opt/crisp/bin/../lib/libcrisp_smb_bridge.dylib'),
      );
    });

    test('Linux bundle lib/ then loader search', () {
      expect(
        bundledRustLibraryCandidates(
          os: 'linux',
          executable: '/opt/app/crisper',
        ),
        [
          '/opt/app/lib/libcrisp_smb_bridge.so',
          '/opt/app/../lib/libcrisp_smb_bridge.so',
          'libcrisp_smb_bridge.so',
        ],
      );
    });

    test('Windows uses the executable folder', () {
      expect(
        bundledRustLibraryCandidates(
          os: 'windows',
          executable: r'C:\Program Files\Crisper\crisper.exe',
        ),
        [
          r'C:\Program Files\Crisper\crisp_smb_bridge.dll',
          r'C:\Program Files\Crisper\..\lib\crisp_smb_bridge.dll',
          'crisp_smb_bridge.dll',
        ],
      );
    });

    test('Android relies on the loader; unknown systems have none', () {
      expect(
        bundledRustLibraryCandidates(
          os: 'android',
          executable: '/system/bin/app_process',
        ),
        ['libcrisp_smb_bridge.so'],
      );
      expect(
        bundledRustLibraryCandidates(os: 'fuchsia', executable: '/x'),
        isEmpty,
      );
    });

    test('an executable without a folder resolves relative to .', () {
      expect(
        bundledRustLibraryCandidates(os: 'linux', executable: 'crisper').first,
        './lib/libcrisp_smb_bridge.so',
      );
    });
  });
}
