import 'package:dartcraft/dartcraft.dart';
import 'package:test/test.dart';
import 'dart:io';

void main() {
  group('Dartcraft Core Tests', () {
    late Dartcraft dartcraft;
    late String testDir;

    setUp(() {
      testDir = Directory.systemTemp.createTempSync('dartcraft_test_').path;
      dartcraft = Dartcraft('1.20.4', testDir);
    });

    tearDown(() {
      try {
        Directory(testDir).deleteSync(recursive: true);
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    test('should create Dartcraft instance with correct properties', () {
      expect(dartcraft.version, equals('1.20.4'));
      expect(dartcraft.installDirectory, equals(testDir));
      expect(dartcraft.useElyBy, isFalse);
      expect(dartcraft.javaPath, isNull);
      expect(dartcraft.authlibInjectorPath, isNull);
    });

    test('should create testing instance', () {
      final testInstance = Dartcraft.testing();
      expect(testInstance.version, equals('1.20.4'));
      expect(testInstance.installDirectory, isNotEmpty);
      expect(testInstance.useElyBy, isFalse);
    });

    test('should report not installed for fresh directory', () {
      expect(dartcraft.isInstalled, isFalse);
    });

    test('should create Dartcraft with Ely.by support', () {
      final elyDartcraft = Dartcraft(
        '1.20.4',
        testDir,
        useElyBy: true,
        authlibInjectorPath: '/path/to/authlib.jar',
      );
      
      expect(elyDartcraft.useElyBy, isTrue);
      expect(elyDartcraft.authlibInjectorPath, equals('/path/to/authlib.jar'));
    });

    test('should get Microsoft auth URL', () {
      MicrosoftAuth.configure(
        clientId: 'test-client-id',
        redirectUri: 'http://localhost:8080/callback',
      );
      
      final authUrl = Dartcraft.getMicrosoftAuthUrl();
      expect(authUrl, contains('login.microsoftonline.com'));
      expect(authUrl, contains('test-client-id'));
      expect(authUrl, contains('http://localhost:8080/callback'));
    });
  });

  group('Version Management Tests', () {
    test('should fetch available versions', () async {
      try {
        final versions = await Dartcraft.getAvailableVersions();
        expect(versions, isNotEmpty);
        expect(versions.first.id, isNotEmpty);
        expect(versions.first.type, isA<VersionType>());
        expect(versions.first.releaseTime, isA<DateTime>());
      } catch (e) {
        // Network tests might fail in CI, so we skip if offline
        if (e.toString().contains('Failed to connect') || 
            e.toString().contains('NetworkException')) {
          markTestSkipped('Network test skipped - offline');
        } else {
          rethrow;
        }
      }
    });

    test('should fetch release versions', () async {
      try {
        final versions = await Dartcraft.getReleaseVersions();
        expect(versions, isNotEmpty);
        expect(versions.every((v) => v.type == VersionType.release), isTrue);
      } catch (e) {
        if (e.toString().contains('Failed to connect') || 
            e.toString().contains('NetworkException')) {
          markTestSkipped('Network test skipped - offline');
        } else {
          rethrow;
        }
      }
    });
  });

  group('Exception Tests', () {
    test('should create and throw DartcraftException', () {
      const exception = DartcraftException('Test message');
      expect(exception.message, equals('Test message'));
      expect(exception.cause, isNull);
      expect(exception.toString(), equals('DartcraftException: Test message'));
    });

    test('should create and throw AuthenticationException', () {
      const exception = AuthenticationException('Auth failed', 'cause');
      expect(exception.message, equals('Auth failed'));
      expect(exception.cause, equals('cause'));
      expect(exception.toString(), equals('AuthenticationException: Auth failed'));
    });

    test('should create and throw InstallationException', () {
      const exception = InstallationException('Install failed');
      expect(exception.message, equals('Install failed'));
      expect(exception.toString(), equals('InstallationException: Install failed'));
    });

    test('should create and throw LaunchException', () {
      const exception = LaunchException('Launch failed');
      expect(exception.message, equals('Launch failed'));
      expect(exception.toString(), equals('LaunchException: Launch failed'));
    });

    test('should create and throw TwoFactorRequiredException', () {
      const exception = TwoFactorRequiredException('2FA required');
      expect(exception.message, equals('2FA required'));
      expect(exception, isA<AuthenticationException>());
    });
  });

  group('Authentication Result Tests', () {
    test('should create AuthenticationResult', () {
      final result = AuthenticationResult(
        username: 'TestUser',
        uuid: 'test-uuid',
        accessToken: 'test-token',
        refreshToken: 'refresh-token',
      );

      expect(result.username, equals('TestUser'));
      expect(result.uuid, equals('test-uuid'));
      expect(result.accessToken, equals('test-token'));
      expect(result.refreshToken, equals('refresh-token'));
    });

    test('should create AuthenticationResult from Ely.by response', () {
      final elyResponse = {
        'selectedProfile': {
          'name': 'ElyUser',
          'id': 'ely-uuid',
        },
        'accessToken': 'ely-token',
      };

      final result = AuthenticationResult.fromElyBy(elyResponse);
      expect(result.username, equals('ElyUser'));
      expect(result.uuid, equals('ely-uuid'));
      expect(result.accessToken, equals('ely-token'));
      expect(result.refreshToken, isNull);
    });
  });

  group('MinecraftVersion Tests', () {
    test('should create MinecraftVersion from JSON', () {
      final json = {
        'id': '1.20.4',
        'type': 'release',
        'releaseTime': '2023-12-07T12:56:18+00:00',
        'url': 'https://example.com/version.json',
        'sha1': 'abcd1234',
      };

      final version = MinecraftVersion.fromJson(json);
      expect(version.id, equals('1.20.4'));
      expect(version.type, equals(VersionType.release));
      expect(version.releaseTime, isA<DateTime>());
      expect(version.url, equals('https://example.com/version.json'));
      expect(version.sha1, equals('abcd1234'));
    });
  });

  group('VersionType Tests', () {
    test('should parse version types correctly', () {
      expect(VersionType.fromString('release'), equals(VersionType.release));
      expect(VersionType.fromString('snapshot'), equals(VersionType.snapshot));
      expect(VersionType.fromString('old_beta'), equals(VersionType.oldBeta));
      expect(VersionType.fromString('old_alpha'), equals(VersionType.oldAlpha));
      expect(VersionType.fromString('unknown'), equals(VersionType.release)); // fallback
    });
  });

  group('Microsoft Authentication Tests', () {
    test('should generate authorization URL with default config', () {
      final url = MicrosoftAuth.getAuthorizationUrl();
      expect(url, contains('login.microsoftonline.com'));
      expect(url, contains('XboxLive.signin'));
      expect(url, contains('offline_access'));
    });

    test('should generate authorization URL with custom config', () {
      MicrosoftAuth.configure(
        clientId: 'custom-client-id',
        redirectUri: 'https://example.com/callback',
      );

      final url = MicrosoftAuth.getAuthorizationUrl();
      expect(url, contains('custom-client-id'));
      expect(url, contains('https://example.com/callback'));
    });
  });
}
