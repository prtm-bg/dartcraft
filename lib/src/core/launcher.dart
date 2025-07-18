import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

import '../exceptions/exceptions.dart';
import '../auth/microsoft_auth.dart';
import '../auth/ely_auth.dart';

/// Callback function for debug output and progress reporting
typedef DebugCallback = void Function(String message);

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

  /// Optional debug callback for progress reporting
  final DebugCallback? debugCallback;

  /// Creates a new Dartcraft launcher instance
  /// 
  /// [version] - The Minecraft version to manage (e.g., '1.20.4')
  /// [installDirectory] - Directory where Minecraft files will be stored
  /// [javaPath] - Optional custom Java executable path
  /// [useElyBy] - Whether to enable Ely.by authentication support
  /// [authlibInjectorPath] - Optional path to authlib-injector JAR file
  /// [debugCallback] - Optional callback for debug output and progress reporting
  Dartcraft(
    this.version,
    this.installDirectory, {
    this.javaPath,
    this.useElyBy = false,
    this.authlibInjectorPath,
    this.debugCallback,
  });

  /// Convenience constructor for testing with default settings
  factory Dartcraft.testing({DebugCallback? debugCallback}) {
    return Dartcraft(
      '1.20.4',
      path.join(Directory.current.path, 'minecraft_test'),
      debugCallback: debugCallback,
    );
  }

  /// Send debug message if callback is provided
  void _debug(String message) {
    debugCallback?.call(message);
  }

  /// Whether the Minecraft version is already installed
  /// 
  /// Returns `true` if all required files for the specified version exist,
  /// `false` otherwise.
  bool get isInstalled => _isVersionInstalled(version, installDirectory);

  /// Installs the specified Minecraft version
  /// 
  /// Downloads and installs all required components for the Minecraft version:
  /// - Version manifest and metadata
  /// - Game JAR file with SHA1 verification
  /// - Required libraries and dependencies
  /// - Game assets (textures, sounds, etc.)
  /// - Native libraries for the current platform
  /// - Logging configuration
  /// 
  /// Example:
  /// ```dart
  /// final launcher = Dartcraft('1.20.4', '/minecraft');
  /// 
  /// if (!launcher.isInstalled) {
  ///   print('Installing Minecraft...');
  ///   await launcher.install();
  ///   print('Installation complete!');
  /// }
  /// ```
  /// 
  /// Throws [InstallationException] if the version is not found or installation fails.
  /// Throws [NetworkException] if network requests fail.
  Future<void> install() async {
    if (isInstalled) {
      _debug('Minecraft $version is already installed');
      return;
    }

    _debug('Starting installation of Minecraft $version...');

    try {
      _debug('Fetching version manifest...');
      final versionManifest = await _fetchVersionManifest();
      final versionInfo = _findVersionInManifest(versionManifest, version);
      
      if (versionInfo == null) {
        throw InstallationException('Version $version not found');
      }

      _debug('Found version $version in manifest');

      // Download and save version JSON
      _debug('Downloading version data...');
      final versionData = await _downloadVersionData(versionInfo);
      
      // Handle version inheritance for modded versions
      _debug('Processing version inheritance...');
      final processedVersionData = await _processVersionInheritance(versionData);
      
      // Download client JAR
      _debug('Downloading client JAR...');
      await _downloadClientJar(processedVersionData);
      
      // Install libraries
      _debug('Installing libraries...');
      await _installLibraries(processedVersionData);
      
      // Extract native libraries
      _debug('Extracting native libraries...');
      await _extractNativeLibraries(processedVersionData);
      
      // Install assets
      _debug('Installing game assets...');
      await _installAssets(processedVersionData);
      
      // Install logging configuration
      _debug('Installing logging configuration...');
      await _installLoggingConfig(processedVersionData);

      _debug('Minecraft $version installation completed successfully!');

    } catch (e) {
      _debug('Installation failed: $e');
      throw InstallationException('Failed to install Minecraft $version: $e');
    }
  }

  /// Launches Minecraft with the specified authentication details
  /// 
  /// Starts a new Minecraft process with the provided authentication information.
  /// The game must be installed first using [install()].
  /// 
  /// Parameters:
  /// - [username] - Player's display name in-game
  /// - [uuid] - Player's unique identifier (with or without dashes)
  /// - [accessToken] - Valid authentication token from Microsoft or Ely.by
  /// - [javaExecutable] - Optional custom Java executable path
  /// - [jvmArguments] - Optional JVM arguments (e.g., `-Xmx2G` for memory)
  /// - [gameArguments] - Optional additional game arguments
  /// - [showOutput] - Whether to display game output in console (default: true)
  /// 
  /// Example:
  /// ```dart
  /// final launcher = Dartcraft('1.20.4', '/minecraft');
  /// 
  /// // Ensure game is installed
  /// if (!launcher.isInstalled) {
  ///   await launcher.install();
  /// }
  /// 
  /// // Launch with authentication
  /// final process = await launcher.launch(
  ///   username: 'PlayerName',
  ///   uuid: '12345678-1234-1234-1234-123456789abc',
  ///   accessToken: 'your-access-token',
  ///   jvmArguments: ['-Xmx2G', '-Xms1G'],
  /// );
  /// 
  /// // Wait for game to exit
  /// final exitCode = await process.exitCode;
  /// print('Game exited with code: $exitCode');
  /// ```
  /// 
  /// Returns a [Process] object representing the running Minecraft instance.
  /// 
  /// Throws [LaunchException] if the game is not installed or launch fails.
  /// Throws [ValidationException] if authentication details are invalid.
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

    _debug('Starting launch process for Minecraft $version...');
    _debug('Player: $username (UUID: $uuid)');

    try {
      // Setup Ely.by authentication if needed
      if (useElyBy) {
        _debug('Setting up Ely.by authentication...');
        await _setupElyByAuthentication();
      }

      // Build launch command
      _debug('Building launch command...');
      final command = await _buildLaunchCommand(
        username: username,
        uuid: uuid,
        accessToken: accessToken,
        javaExecutable: javaExecutable,
        jvmArguments: jvmArguments,
        gameArguments: gameArguments,
      );

      _debug('Launch command built successfully');

      // Start the process
      _debug('Starting Minecraft process...');
      final process = await Process.start(
        command.first,
        command.skip(1).toList(),
        workingDirectory: installDirectory,
        runInShell: Platform.isWindows,
      );

      _debug('Minecraft process started successfully (PID: ${process.pid})');

      if (showOutput) {
        _setupProcessOutput(process);
      }

      return process;
    } catch (e) {
      _debug('Launch failed: $e');
      throw LaunchException('Failed to launch Minecraft: $e');
    }
  }

  /// Gets a list of all available Minecraft versions
  /// 
  /// Fetches the complete version manifest from Mojang's servers, including
  /// releases, snapshots, and other experimental versions.
  /// 
  /// Example:
  /// ```dart
  /// final versions = await Dartcraft.getAvailableVersions();
  /// 
  /// print('Available versions:');
  /// for (final version in versions.take(10)) {
  ///   print('${version.id} (${version.type}) - ${version.releaseTime}');
  /// }
  /// ```
  /// 
  /// Returns a list of [MinecraftVersion] objects sorted by release date.
  /// 
  /// Throws [DartcraftException] if the version manifest cannot be fetched.
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

  /// Gets a list of stable Minecraft release versions only
  /// 
  /// Filters the available versions to include only stable releases,
  /// excluding snapshots, alpha, beta, and other experimental versions.
  /// 
  /// Example:
  /// ```dart
  /// final releases = await Dartcraft.getReleaseVersions();
  /// 
  /// print('Stable releases:');
  /// for (final version in releases.take(5)) {
  ///   print('${version.id} - Released: ${version.releaseTime}');
  /// }
  /// 
  /// // Use the latest release
  /// final latest = releases.first;
  /// final launcher = Dartcraft(latest.id, '/minecraft');
  /// ```
  /// 
  /// Returns a list of [MinecraftVersion] objects for stable releases only.
  /// 
  /// Throws [DartcraftException] if the version manifest cannot be fetched.
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

  /// Authenticates with Ely.by using username and password
  /// 
  /// Provides username/password authentication for Ely.by accounts.
  /// For OAuth2 browser-based authentication, use [ElyAuth.authenticateWithOAuth] directly.
  /// 
  /// Parameters:
  /// - [username] - Ely.by username or email address
  /// - [password] - Account password
  /// 
  /// Example:
  /// ```dart
  /// final launcher = Dartcraft('1.20.4', '/minecraft', useElyBy: true);
  /// 
  /// try {
  ///   final auth = await launcher.authenticateWithElyBy('username', 'password');
  ///   
  ///   await launcher.launch(
  ///     username: auth.username,
  ///     uuid: auth.uuid,
  ///     accessToken: auth.accessToken,
  ///   );
  /// } catch (e) {
  ///   print('Authentication failed: $e');
  /// }
  /// ```
  /// 
  /// Returns [AuthenticationResult] with user details and access tokens.
  /// 
  /// Throws [TwoFactorRequiredException] if 2FA is required for the account.
  /// Throws [AuthenticationException] if credentials are invalid.
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

  /// Authenticates with Ely.by using two-factor authentication
  /// 
  /// Use this method when your Ely.by account has two-factor authentication enabled.
  /// 
  /// Parameters:
  /// - [username] - Ely.by username or email address
  /// - [password] - Account password
  /// - [twoFactorCode] - Current 6-digit 2FA code from your authenticator app
  /// 
  /// Example:
  /// ```dart
  /// final launcher = Dartcraft('1.20.4', '/minecraft', useElyBy: true);
  /// 
  /// try {
  ///   final auth = await launcher.authenticateWithElyByTwoFactor(
  ///     'username', 
  ///     'password', 
  ///     '123456'
  ///   );
  ///   
  ///   await launcher.launch(
  ///     username: auth.username,
  ///     uuid: auth.uuid,
  ///     accessToken: auth.accessToken,
  ///   );
  /// } catch (e) {
  ///   print('Authentication failed: $e');
  /// }
  /// ```
  /// 
  /// Returns [AuthenticationResult] with user details and access tokens.
  /// 
  /// Throws [AuthenticationException] if credentials or 2FA code are invalid.
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
        _debug('File already exists and verified: ${path.basename(filePath)}');
        return; // File is already valid
      }
      _debug('File exists but SHA1 mismatch, re-downloading: ${path.basename(filePath)}');
    }

    _debug('Downloading: ${path.basename(filePath)}');

    // Download the file with retry logic
    const maxRetries = 3;
    for (int retry = 0; retry < maxRetries; retry++) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw InstallationException('Failed to download file (HTTP ${response.statusCode}): $url');
        }

        // Verify SHA1
        final actualSha1 = sha1.convert(response.bodyBytes).toString();
        if (actualSha1 != expectedSha1) {
          if (retry == maxRetries - 1) {
            throw InstallationException('File verification failed after $maxRetries attempts: $filePath\nExpected SHA1: $expectedSha1\nActual SHA1: $actualSha1\nURL: $url');
          }
          _debug('SHA1 mismatch, retrying download (${retry + 1}/$maxRetries): ${path.basename(filePath)}');
          continue;
        }

        // Save the file
        await Directory(path.dirname(filePath)).create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
        
        _debug('Successfully downloaded and verified: ${path.basename(filePath)}');
        return;
      } catch (e) {
        if (retry == maxRetries - 1) {
          throw InstallationException('Failed to download file after $maxRetries attempts: $filePath - $e');
        }
        _debug('Download failed, retrying (${retry + 1}/$maxRetries): ${path.basename(filePath)} - $e');
        await Future.delayed(Duration(milliseconds: 500 * (retry + 1))); // Exponential backoff
      }
    }
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
    if (logging == null) {
      _debug('No logging configuration found');
      return;
    }

    final client = logging['client'] as Map<String, dynamic>?;
    if (client == null) {
      _debug('No client logging configuration found');
      return;
    }

    final file = client['file'] as Map<String, dynamic>?;
    if (file == null) {
      _debug('No logging file configuration found');
      return;
    }

    final url = file['url'] as String;
    final sha1Hash = file['sha1'] as String;
    final configPath = path.join(installDirectory, 'assets', 'log_configs', file['id']);

    _debug('Downloading logging config: ${file['id']}');
    await _downloadFileWithVerification(url, configPath, sha1Hash);
    _debug('Logging configuration installed successfully');
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
