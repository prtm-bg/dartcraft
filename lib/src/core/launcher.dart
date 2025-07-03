import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

import '../exceptions/exceptions.dart';
import '../auth/microsoft_auth.dart';
import '../auth/ely_auth.dart';

/// Main Dartcraft launcher class
/// 
/// Provides comprehensive functionality for installing and launching Minecraft
/// with support for multiple authentication providers and cross-platform compatibility.
class Dartcraft {
  /// The Minecraft version to install/launch
  final String version;
  
  /// The directory where Minecraft will be installed
  final String installDirectory;
  
  /// Optional custom Java executable path
  final String? javaPath;
  
  /// Whether to use Ely.by authentication
  final bool useElyBy;
  
  /// Optional path to authlib-injector for Ely.by authentication
  String? authlibInjectorPath;

  /// Creates a new Dartcraft launcher instance
  /// 
  /// [version] - The Minecraft version to manage (e.g., '1.20.4')
  /// [installDirectory] - Directory where Minecraft files will be stored
  /// [javaPath] - Optional custom Java executable path
  /// [useElyBy] - Whether to enable Ely.by authentication support
  /// [authlibInjectorPath] - Optional path to authlib-injector JAR file
  Dartcraft(
    this.version,
    this.installDirectory, {
    this.javaPath,
    this.useElyBy = false,
    this.authlibInjectorPath,
  });

  /// Convenience constructor for testing with default settings
  factory Dartcraft.testing() {
    return Dartcraft(
      '1.20.4',
      path.join(Directory.current.path, 'minecraft_test'),
    );
  }

  /// Check if the specified Minecraft version is installed
  bool get isInstalled => _isVersionInstalled(version, installDirectory);

  /// Install the Minecraft version
  /// 
  /// Downloads the game files, libraries, assets, and native libraries
  /// required to run the specified Minecraft version.
  Future<void> install() async {
    if (isInstalled) {
      return;
    }

    try {
      final versionManifest = await _fetchVersionManifest();
      final versionInfo = _findVersionInManifest(versionManifest, version);
      
      if (versionInfo == null) {
        throw InstallationException('Version $version not found');
      }

      // Download and save version JSON
      final versionData = await _downloadVersionData(versionInfo);
      
      // Handle version inheritance for modded versions
      final processedVersionData = await _processVersionInheritance(versionData);
      
      // Download client JAR
      await _downloadClientJar(processedVersionData);
      
      // Install libraries
      await _installLibraries(processedVersionData);
      
      // Extract native libraries
      await _extractNativeLibraries(processedVersionData);
      
      // Install assets
      await _installAssets(processedVersionData);
      
      // Install logging configuration
      await _installLoggingConfig(processedVersionData);

    } catch (e) {
      throw InstallationException('Failed to install Minecraft $version: $e');
    }
  }

  /// Launch Minecraft with the specified authentication details
  /// 
  /// [username] - Player username
  /// [uuid] - Player UUID
  /// [accessToken] - Authentication access token
  /// [javaExecutable] - Optional custom Java executable
  /// [jvmArguments] - Optional JVM arguments
  /// [gameArguments] - Optional additional game arguments
  /// [showOutput] - Whether to display game output in console
  /// 
  /// Returns a [Process] object for the running Minecraft instance
  Future<Process> launch({
    required String username,
    required String uuid,
    required String accessToken,
    String? javaExecutable,
    List<String>? jvmArguments,
    Map<String, String>? gameArguments,
    bool showOutput = true,
  }) async {
    if (!isInstalled) {
      throw LaunchException('Minecraft $version is not installed. Call install() first.');
    }

    try {
      // Setup Ely.by authentication if needed
      if (useElyBy) {
        await _setupElyByAuthentication();
      }

      // Build launch command
      final command = await _buildLaunchCommand(
        username: username,
        uuid: uuid,
        accessToken: accessToken,
        javaExecutable: javaExecutable,
        jvmArguments: jvmArguments,
        gameArguments: gameArguments,
      );

      // Start the process
      final process = await Process.start(
        command.first,
        command.skip(1).toList(),
        workingDirectory: installDirectory,
        runInShell: Platform.isWindows,
      );

      if (showOutput) {
        _setupProcessOutput(process);
      }

      return process;
    } catch (e) {
      throw LaunchException('Failed to launch Minecraft: $e');
    }
  }

  /// Get a list of available Minecraft versions
  static Future<List<MinecraftVersion>> getAvailableVersions() async {
    try {
      final manifest = await _fetchVersionManifest();
      final versions = (manifest['versions'] as List)
          .map((v) => MinecraftVersion.fromJson(v))
          .toList();
      return versions;
    } catch (e) {
      throw DartcraftException('Failed to fetch available versions: $e');
    }
  }

  /// Get release versions only
  static Future<List<MinecraftVersion>> getReleaseVersions() async {
    final versions = await getAvailableVersions();
    return versions.where((v) => v.type == VersionType.release).toList();
  }

  /// Authenticate with Microsoft account
  /// 
  /// [authCode] - Authorization code from OAuth2 flow
  /// Returns authentication result with user details and tokens
  static Future<AuthenticationResult> authenticateWithMicrosoft(String authCode) async {
    try {
      return await MicrosoftAuth.authenticate(authCode);
    } catch (e) {
      throw AuthenticationException('Microsoft authentication failed: $e');
    }
  }

  /// Get Microsoft OAuth2 authorization URL
  static String getMicrosoftAuthUrl() {
    return MicrosoftAuth.getAuthorizationUrl();
  }

  /// Authenticate with Ely.by account
  /// 
  /// [username] - Ely.by username or email
  /// [password] - Account password
  /// Returns authentication result with user details and tokens
  Future<AuthenticationResult> authenticateWithElyBy(
    String username,
    String password,
  ) async {
    try {
      final result = await ElyAuth.authenticate(username, password);
      return AuthenticationResult.fromElyBy(result);
    } catch (e) {
      if (e is ElyAuthException && e.error == 'TwoFactorRequired') {
        throw TwoFactorRequiredException('Two-factor authentication required');
      }
      throw AuthenticationException('Ely.by authentication failed: $e');
    }
  }

  /// Authenticate with Ely.by account using two-factor authentication
  /// 
  /// [username] - Ely.by username or email
  /// [password] - Account password
  /// [twoFactorCode] - Two-factor authentication code
  /// Returns authentication result with user details and tokens
  Future<AuthenticationResult> authenticateWithElyByTwoFactor(
    String username,
    String password,
    String twoFactorCode,
  ) async {
    try {
      final result = await ElyAuth.authenticateWithTwoFactor(
        username,
        password,
        twoFactorCode,
      );
      return AuthenticationResult.fromElyBy(result);
    } catch (e) {
      throw AuthenticationException('Ely.by 2FA authentication failed: $e');
    }
  }

  // Private implementation methods
  
  static Future<Map<String, dynamic>> _fetchVersionManifest() async {
    const url = 'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json';
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode != 200) {
      throw DartcraftException('Failed to fetch version manifest');
    }
    
    return json.decode(response.body);
  }

  Map<String, dynamic>? _findVersionInManifest(
    Map<String, dynamic> manifest,
    String targetVersion,
  ) {
    final versions = manifest['versions'] as List;
    for (final version in versions) {
      if (version['id'] == targetVersion) {
        return version;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _downloadVersionData(
    Map<String, dynamic> versionInfo,
  ) async {
    final url = versionInfo['url'] as String;
    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode != 200) {
      throw InstallationException('Failed to download version data');
    }

    // Verify SHA1 if available
    if (versionInfo.containsKey('sha1')) {
      final expectedSha1 = versionInfo['sha1'] as String;
      final actualSha1 = sha1.convert(response.bodyBytes).toString();
      if (expectedSha1 != actualSha1) {
        throw InstallationException('Version data SHA1 verification failed');
      }
    }

    // Save version JSON
    final versionDir = path.join(installDirectory, 'versions', version);
    await Directory(versionDir).create(recursive: true);
    
    final versionFile = File(path.join(versionDir, '$version.json'));
    await versionFile.writeAsBytes(response.bodyBytes);

    return json.decode(response.body);
  }

  Future<Map<String, dynamic>> _processVersionInheritance(
    Map<String, dynamic> versionData,
  ) async {
    if (!versionData.containsKey('inheritsFrom')) {
      return versionData;
    }

    final parentVersion = versionData['inheritsFrom'] as String;
    
    // Install parent version if not present
    if (!_isVersionInstalled(parentVersion, installDirectory)) {
      final parentLauncher = Dartcraft(parentVersion, installDirectory);
      await parentLauncher.install();
    }

    // Load parent version data
    final parentFile = File(
      path.join(installDirectory, 'versions', parentVersion, '$parentVersion.json'),
    );
    final parentData = json.decode(await parentFile.readAsString());

    // Merge parent and child data
    return _mergeVersionData(parentData, versionData);
  }

  Map<String, dynamic> _mergeVersionData(
    Map<String, dynamic> parent,
    Map<String, dynamic> child,
  ) {
    final result = Map<String, dynamic>.from(parent);
    
    child.forEach((key, value) {
      if (key == 'libraries' && result.containsKey('libraries')) {
        // Merge libraries
        final parentLibs = List<dynamic>.from(result['libraries']);
        final childLibs = List<dynamic>.from(value);
        result['libraries'] = [...parentLibs, ...childLibs];
      } else if (key != 'inheritsFrom') {
        result[key] = value;
      }
    });

    return result;
  }

  Future<void> _downloadClientJar(Map<String, dynamic> versionData) async {
    final downloads = versionData['downloads'] as Map<String, dynamic>;
    final client = downloads['client'] as Map<String, dynamic>;
    
    final url = client['url'] as String;
    final sha1Hash = client['sha1'] as String;
    
    final jarPath = path.join(installDirectory, 'versions', version, '$version.jar');
    await _downloadFileWithVerification(url, jarPath, sha1Hash);
  }

  Future<void> _downloadFileWithVerification(
    String url,
    String filePath,
    String expectedSha1,
  ) async {
    // Check if file already exists and is valid
    final file = File(filePath);
    if (file.existsSync()) {
      final existingBytes = await file.readAsBytes();
      final existingSha1 = sha1.convert(existingBytes).toString();
      if (existingSha1 == expectedSha1) {
        return; // File is already valid
      }
    }

    // Download the file
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw InstallationException('Failed to download file: $url');
    }

    // Verify SHA1
    final actualSha1 = sha1.convert(response.bodyBytes).toString();
    if (actualSha1 != expectedSha1) {
      throw InstallationException('File verification failed: $filePath');
    }

    // Save the file
    await Directory(path.dirname(filePath)).create(recursive: true);
    await file.writeAsBytes(response.bodyBytes);
  }

  Future<void> _installLibraries(Map<String, dynamic> versionData) async {
    final libraries = versionData['libraries'] as List? ?? [];
    
    for (final library in libraries) {
      await _installLibrary(library);
    }
  }

  Future<void> _installLibrary(Map<String, dynamic> library) async {
    // Check rules to see if this library applies to current platform
    if (!_libraryAppliesToPlatform(library)) {
      return;
    }

    final downloads = library['downloads'] as Map<String, dynamic>?;
    if (downloads == null) return;

    // Install main artifact
    final artifact = downloads['artifact'] as Map<String, dynamic>?;
    if (artifact != null) {
      final url = artifact['url'] as String;
      final sha1Hash = artifact['sha1'] as String;
      final libraryPath = path.join(installDirectory, 'libraries', artifact['path']);
      await _downloadFileWithVerification(url, libraryPath, sha1Hash);
    }

    // Install native classifiers for current platform
    final classifiers = downloads['classifiers'] as Map<String, dynamic>?;
    if (classifiers != null) {
      final nativeKey = _getNativeClassifierKey();
      if (nativeKey != null && classifiers.containsKey(nativeKey)) {
        final native = classifiers[nativeKey] as Map<String, dynamic>;
        final url = native['url'] as String;
        final sha1Hash = native['sha1'] as String;
        final nativePath = path.join(installDirectory, 'libraries', native['path']);
        await _downloadFileWithVerification(url, nativePath, sha1Hash);
      }
    }
  }

  bool _libraryAppliesToPlatform(Map<String, dynamic> library) {
    final rules = library['rules'] as List?;
    if (rules == null) return true;

    bool allowed = false;
    for (final rule in rules) {
      final action = rule['action'] as String;
      final os = rule['os'] as Map<String, dynamic>?;
      
      if (os == null) {
        // Rule applies to all platforms
        allowed = action == 'allow';
      } else {
        // Rule is platform-specific
        final osName = os['name'] as String?;
        if (_matchesCurrentPlatform(osName)) {
          allowed = action == 'allow';
        }
      }
    }

    return allowed;
  }

  bool _matchesCurrentPlatform(String? osName) {
    if (osName == null) return true;
    
    switch (osName) {
      case 'windows':
        return Platform.isWindows;
      case 'osx':
        return Platform.isMacOS;
      case 'linux':
        return Platform.isLinux;
      default:
        return false;
    }
  }

  String? _getNativeClassifierKey() {
    if (Platform.isWindows) {
      return Platform.environment['PROCESSOR_ARCHITECTURE']?.contains('64') == true
          ? 'natives-windows-x64'
          : 'natives-windows-x86';
    } else if (Platform.isMacOS) {
      // Check for Apple Silicon
      final result = Process.runSync('uname', ['-m']);
      final arch = result.stdout.toString().trim();
      return arch == 'arm64' ? 'natives-macos-arm64' : 'natives-macos';
    } else if (Platform.isLinux) {
      return 'natives-linux';
    }
    return null;
  }

  Future<void> _extractNativeLibraries(Map<String, dynamic> versionData) async {
    final nativesDir = path.join(installDirectory, 'versions', version, 'natives');
    
    // Clean and create natives directory
    final nativesDirObj = Directory(nativesDir);
    if (nativesDirObj.existsSync()) {
      await nativesDirObj.delete(recursive: true);
    }
    await nativesDirObj.create(recursive: true);

    final libraries = versionData['libraries'] as List? ?? [];
    
    for (final library in libraries) {
      await _extractNativeLibrary(library, nativesDir);
    }
  }

  Future<void> _extractNativeLibrary(
    Map<String, dynamic> library,
    String nativesDir,
  ) async {
    if (!_libraryAppliesToPlatform(library)) return;

    final downloads = library['downloads'] as Map<String, dynamic>?;
    final classifiers = downloads?['classifiers'] as Map<String, dynamic>?;
    
    if (classifiers == null) return;

    final nativeKey = _getNativeClassifierKey();
    if (nativeKey == null || !classifiers.containsKey(nativeKey)) return;

    final native = classifiers[nativeKey] as Map<String, dynamic>;
    final nativePath = path.join(installDirectory, 'libraries', native['path']);
    final nativeFile = File(nativePath);
    
    if (!nativeFile.existsSync()) return;

    // Extract the native library
    final bytes = await nativeFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      if (file.isFile) {
        final fileName = path.basename(file.name);
        // Skip META-INF files
        if (fileName.startsWith('META-INF')) continue;
        
        final extractPath = path.join(nativesDir, fileName);
        final extractFile = File(extractPath);
        await extractFile.writeAsBytes(file.content as List<int>);
        
        // Make executable on Unix systems
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', extractPath]);
        }
      }
    }
  }

  Future<void> _installAssets(Map<String, dynamic> versionData) async {
    final assetIndex = versionData['assetIndex'] as Map<String, dynamic>?;
    if (assetIndex == null) return;

    final indexUrl = assetIndex['url'] as String;
    final indexId = assetIndex['id'] as String;
    
    // Download asset index
    final indexPath = path.join(installDirectory, 'assets', 'indexes', '$indexId.json');
    await _downloadFileWithVerification(
      indexUrl,
      indexPath,
      assetIndex['sha1'] as String,
    );

    // Parse asset index and download assets
    final indexData = json.decode(await File(indexPath).readAsString());
    final objects = indexData['objects'] as Map<String, dynamic>;

    for (final entry in objects.entries) {
      final assetInfo = entry.value as Map<String, dynamic>;
      final hash = assetInfo['hash'] as String;
      final size = assetInfo['size'] as int;
      
      final assetUrl = 'https://resources.download.minecraft.net/${hash.substring(0, 2)}/$hash';
      final assetPath = path.join(installDirectory, 'assets', 'objects', hash.substring(0, 2), hash);
      
      // Check if asset already exists
      final assetFile = File(assetPath);
      if (assetFile.existsSync() && await assetFile.length() == size) {
        continue;
      }

      await _downloadFileWithVerification(assetUrl, assetPath, hash);
    }
  }

  Future<void> _installLoggingConfig(Map<String, dynamic> versionData) async {
    final logging = versionData['logging'] as Map<String, dynamic>?;
    if (logging == null) return;

    final client = logging['client'] as Map<String, dynamic>?;
    if (client == null) return;

    final file = client['file'] as Map<String, dynamic>?;
    if (file == null) return;

    final url = file['url'] as String;
    final sha1Hash = file['id'] as String;
    final configPath = path.join(installDirectory, 'assets', 'log_configs', file['id']);

    await _downloadFileWithVerification(url, configPath, sha1Hash);
  }

  Future<void> _setupElyByAuthentication() async {
    if (authlibInjectorPath == null) {
      authlibInjectorPath = await ElyAuth.downloadAuthlibInjector(installDirectory);
    }
  }

  Future<List<String>> _buildLaunchCommand({
    required String username,
    required String uuid,
    required String accessToken,
    String? javaExecutable,
    List<String>? jvmArguments,
    Map<String, String>? gameArguments,
  }) async {
    final versionFile = File(
      path.join(installDirectory, 'versions', version, '$version.json'),
    );
    final versionData = json.decode(await versionFile.readAsString());

    final command = <String>[];

    // Java executable
    command.add(javaExecutable ?? javaPath ?? 'java');

    // Platform-specific JVM arguments
    if (Platform.isMacOS) {
      command.add('-XstartOnFirstThread');
    }

    // User JVM arguments
    if (jvmArguments != null) {
      command.addAll(jvmArguments);
    }

    // Ely.by authlib-injector arguments
    if (useElyBy && authlibInjectorPath != null) {
      command.addAll(ElyAuth.getAuthlibJvmArgs(authlibInjectorPath!));
    }

    // Natives library path
    final nativesPath = path.join(installDirectory, 'versions', version, 'natives');
    command.add('-Djava.library.path=$nativesPath');

    // Classpath
    final classpath = await _buildClasspath(versionData);
    command.addAll(['-cp', classpath]);

    // Main class
    command.add(versionData['mainClass'] as String);

    // Game arguments
    final gameArgs = _buildGameArguments(versionData, {
      'auth_player_name': username,
      'version_name': version,
      'game_directory': installDirectory,
      'assets_root': path.join(installDirectory, 'assets'),
      'assets_index_name': versionData['assets'] ?? version,
      'auth_uuid': uuid,
      'auth_access_token': accessToken,
      'user_type': 'mojang',
      'version_type': versionData['type'] ?? 'release',
      ...?gameArguments,
    });
    command.addAll(gameArgs);

    return command;
  }

  Future<String> _buildClasspath(Map<String, dynamic> versionData) async {
    final classpathEntries = <String>[];

    // Add libraries
    final libraries = versionData['libraries'] as List? ?? [];
    for (final library in libraries) {
      if (!_libraryAppliesToPlatform(library)) continue;
      
      final downloads = library['downloads'] as Map<String, dynamic>?;
      final artifact = downloads?['artifact'] as Map<String, dynamic>?;
      
      if (artifact != null) {
        final libraryPath = path.join(installDirectory, 'libraries', artifact['path']);
        classpathEntries.add(libraryPath);
      }
    }

    // Add client JAR
    final clientJar = path.join(installDirectory, 'versions', version, '$version.jar');
    classpathEntries.add(clientJar);

    return classpathEntries.join(Platform.isWindows ? ';' : ':');
  }

  List<String> _buildGameArguments(
    Map<String, dynamic> versionData,
    Map<String, String> variables,
  ) {
    final arguments = <String>[];
    
    // Use modern arguments format if available
    if (versionData.containsKey('arguments')) {
      final gameArgs = versionData['arguments']['game'] as List;
      for (final arg in gameArgs) {
        if (arg is String) {
          arguments.add(_replaceVariables(arg, variables));
        } else if (arg is Map) {
          // Conditional argument - check rules
          final rules = arg['rules'] as List?;
          if (rules != null && _evaluateRules(rules)) {
            final value = arg['value'];
            if (value is String) {
              arguments.add(_replaceVariables(value, variables));
            } else if (value is List) {
              for (final v in value) {
                arguments.add(_replaceVariables(v as String, variables));
              }
            }
          }
        }
      }
    } else {
      // Fallback to legacy minecraftArguments
      final minecraftArguments = versionData['minecraftArguments'] as String? ?? '';
      final argList = minecraftArguments.split(' ');
      for (final arg in argList) {
        if (arg.isNotEmpty) {
          arguments.add(_replaceVariables(arg, variables));
        }
      }
    }

    return arguments;
  }

  String _replaceVariables(String template, Map<String, String> variables) {
    var result = template;
    variables.forEach((key, value) {
      result = result.replaceAll('\${$key}', value);
    });
    return result;
  }

  bool _evaluateRules(List rules) {
    // Simple rule evaluation - can be made more sophisticated
    return true;
  }

  void _setupProcessOutput(Process process) {
    process.stdout.transform(utf8.decoder).listen((data) {
      print('[Minecraft] $data');
    });

    process.stderr.transform(utf8.decoder).listen((data) {
      print('[Minecraft Error] $data');
    });
  }

  bool _isVersionInstalled(String version, String installDir) {
    final versionDir = path.join(installDir, 'versions', version);
    final versionJar = path.join(versionDir, '$version.jar');
    final versionJson = path.join(versionDir, '$version.json');
    
    return Directory(versionDir).existsSync() &&
           File(versionJar).existsSync() &&
           File(versionJson).existsSync();
  }
}

/// Represents a Minecraft version
class MinecraftVersion {
  final String id;
  final VersionType type;
  final DateTime releaseTime;
  final String url;
  final String sha1;

  MinecraftVersion({
    required this.id,
    required this.type,
    required this.releaseTime,
    required this.url,
    required this.sha1,
  });

  factory MinecraftVersion.fromJson(Map<String, dynamic> json) {
    return MinecraftVersion(
      id: json['id'] as String,
      type: VersionType.fromString(json['type'] as String),
      releaseTime: DateTime.parse(json['releaseTime'] as String),
      url: json['url'] as String,
      sha1: json['sha1'] as String,
    );
  }
}

/// Version types
enum VersionType {
  release,
  snapshot,
  oldBeta,
  oldAlpha;

  static VersionType fromString(String value) {
    switch (value) {
      case 'release':
        return VersionType.release;
      case 'snapshot':
        return VersionType.snapshot;
      case 'old_beta':
        return VersionType.oldBeta;
      case 'old_alpha':
        return VersionType.oldAlpha;
      default:
        return VersionType.release;
    }
  }
}

/// Authentication result
class AuthenticationResult {
  final String username;
  final String uuid;
  final String accessToken;
  final String? refreshToken;

  AuthenticationResult({
    required this.username,
    required this.uuid,
    required this.accessToken,
    this.refreshToken,
  });

  factory AuthenticationResult.fromElyBy(Map<String, dynamic> result) {
    final profile = result['selectedProfile'] as Map<String, dynamic>;
    return AuthenticationResult(
      username: profile['name'] as String,
      uuid: profile['id'] as String,
      accessToken: result['accessToken'] as String,
    );
  }
}

/// Two-factor authentication required exception
class TwoFactorRequiredException extends AuthenticationException {
  const TwoFactorRequiredException(String message) : super(message);
}
