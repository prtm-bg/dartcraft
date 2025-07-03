import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'dart:io';
import 'minecraft_auth.dart';
import 'dartcraft_exceptions.dart';
// instance class

class Dartcraft{
  String minecraftVersion = '1.20.4';
  String installPath = './';
  String? customJavaPath;

  Dartcraft(this.minecraftVersion, this.installPath, {this.customJavaPath});
  Dartcraft.test() : minecraftVersion = '1.20.4', installPath = '/Users/prtmbg/Downloads/minecraft_test';

  /// Check if the current version is already installed
  bool isInstalled() {
    return isVersionInstalled(minecraftVersion, installPath);
  }

  Future<void> install() async {
    print('Installing Dartcraft for Minecraft version $minecraftVersion at path $installPath');

    // Check if version is already installed
    if (isInstalled()) {
      print('Minecraft version $minecraftVersion is already installed');
      return;
    }

    try {
      String versionManifest_URL = 'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json';
      var response = await http.get(Uri.parse(versionManifest_URL));
      
      if (response.statusCode == 200) {
        print('Version manifest fetched successfully.');

        var versionManifest = json.decode(response.body);
        List versions = versionManifest['versions'];
        bool versionFound = false;
        
        for (var version in versions) {
          if (version['id'] == minecraftVersion) {
            print('Found Minecraft version: ${version['id']}');
            versionFound = true;

            String versionJSON_URL = version['url'];
            String versionSha1 = version['sha1'];
            
            // Create version directory and save version JSON locally
            await downloadAndSaveVersionJson(versionJSON_URL, versionSha1, minecraftVersion, installPath);
            
            // Load version data from local file
            var versionData = await loadLocalVersionData(minecraftVersion, installPath);
            if (versionData != null) {
              // Handle version inheritance (for Forge and other modded versions)
              versionData = await handleVersionInheritance(versionData, installPath);
              
              if (versionData == null) {
                throw VersionException('Failed to process version inheritance');
              }
              
              String clientJarURL = versionData['downloads']['client']['url'];
              
              // Download the client jar
              String clientJarPath = path.join(installPath, 'versions', minecraftVersion, '$minecraftVersion.jar');
              await downloadFileWithSha1(clientJarURL, clientJarPath, versionData['downloads']['client']['sha1']);

              // Install libraries
              await installLibraries(versionData, installPath, minecraftVersion);
              
              // Extract native libraries (important for launch)
              await extractAllNatives(minecraftVersion, installPath);
              
              // Install assets
              await installAssets(versionData, installPath);
              
              // Download logging config if present
              await installLoggingConfig(versionData, installPath);
              
              // Install Java runtime if needed
              if (versionData.containsKey('javaVersion')) {
                String javaComponent = versionData['javaVersion']['component'];
                print('Installing Java runtime: $javaComponent');
                await installRuntime(javaComponent, installPath);
              }
              
              print('Installation completed successfully!');
            } else {
              throw VersionException('Failed to load version data');
            }

            break;
          }
        }

        if (!versionFound) {
          throw VersionException('Minecraft version $minecraftVersion not found in the manifest');
        }

      } else {
        throw InstallationException('Failed to fetch version manifest: ${response.statusCode}');
      }
    } catch (e) {
      if (e is DartcraftException) {
        rethrow;
      }
      throw InstallationException('Error during installation', originalError: e);
    }
  }

  /// Generate Minecraft launch command
  Future<List<String>?> generateLaunchCommand({
    required String username,
    required String uuid,
    required String accessToken,
    String? javaExecutable,
    List<String>? jvmArguments,
    Map<String, String>? additionalOptions,
  }) async {
    try {
      var versionData = await loadLocalVersionData(minecraftVersion, installPath);
      if (versionData == null) {
        print('Version data not found. Make sure the version is installed.');
        return null;
      }
      
      // Handle inheritance
      versionData = await handleVersionInheritance(versionData, installPath);
      if (versionData == null) {
        print('Failed to process version inheritance');
        return null;
      }
      
      List<String> command = [];
      
      // Add Java executable
      if (javaExecutable != null) {
        command.add(javaExecutable);
      } else if (customJavaPath != null) {
        command.add(customJavaPath!);
      } else if (versionData.containsKey('javaVersion')) {
        String? javaPath = getJavaExecutablePath(versionData['javaVersion']['component'], installPath);
        command.add(javaPath ?? 'java');
      } else {
        command.add('java');
      }
      
      // Add platform-specific JVM arguments
      if (Platform.isMacOS) {
        // macOS requires this flag for LWJGL/GLFW to work
        command.add('-XstartOnFirstThread');
      }
      
      // Add user JVM arguments
      if (jvmArguments != null) {
        command.addAll(jvmArguments);
      }
      
      // Add natives directory
      String nativesDir = path.join(installPath, 'versions', minecraftVersion, 'natives');
      command.add('-Djava.library.path=$nativesDir');
      
      // Add classpath
      String classpath = await buildClasspath(versionData, installPath);
      command.addAll(['-cp', classpath]);
      
      // Add main class
      command.add(versionData['mainClass']);
      
      // Add game arguments
      List<String> gameArgs = buildGameArguments(versionData, installPath, {
        'username': username,
        'uuid': uuid,
        'token': accessToken,
        'gameDirectory': installPath,
        'assetsRoot': path.join(installPath, 'assets'),
        'assetsIndex': versionData.containsKey('assets') ? versionData['assets'] : versionData['id'],
        'versionName': versionData['id'],
        'versionType': versionData['type'],
        ...?additionalOptions,
      });
      
      command.addAll(gameArgs);
      
      return command;
      
    } catch (e) {
      print('Error generating launch command: $e');
      return null;
    }
  }

  /// Build classpath string for Minecraft
  Future<String> buildClasspath(Map<String, dynamic> versionData, String installPath) async {
    List<String> classpathEntries = [];
    String separator = Platform.isWindows ? ';' : ':';
    
    // Add libraries to classpath
    if (versionData.containsKey('libraries')) {
      for (var library in versionData['libraries']) {
        if (library.containsKey('rules') && !parseRuleList(library['rules'])) {
          continue;
        }
        
        String libraryPath = getLibraryPath(library['name'], installPath);
        classpathEntries.add(libraryPath);
        
        // Add native classifier if present
        String nativeSuffix = getNativeLibrarySuffix(library);
        if (nativeSuffix.isNotEmpty && library.containsKey('downloads') && 
            library['downloads'].containsKey('classifiers') &&
            library['downloads']['classifiers'].containsKey(nativeSuffix)) {
          var classifier = library['downloads']['classifiers'][nativeSuffix];
          if (classifier.containsKey('path')) {
            String nativePath = path.join(installPath, 'libraries', classifier['path']);
            classpathEntries.add(nativePath);
          }
        }
      }
    }
    
    // Add main jar
    String jarPath;
    if (versionData.containsKey('jar')) {
      jarPath = path.join(installPath, 'versions', versionData['jar'], '${versionData['jar']}.jar');
    } else {
      jarPath = path.join(installPath, 'versions', versionData['id'], '${versionData['id']}.jar');
    }
    classpathEntries.add(jarPath);
    
    return classpathEntries.join(separator);
  }

  /// Build game arguments
  List<String> buildGameArguments(Map<String, dynamic> versionData, String installPath, Map<String, String> options) {
    List<String> args = [];
    
    if (versionData.containsKey('minecraftArguments')) {
      // Old format
      String argsString = versionData['minecraftArguments'];
      args.addAll(argsString.split(' '));
    } else if (versionData.containsKey('arguments') && versionData['arguments'].containsKey('game')) {
      // New format
      for (var arg in versionData['arguments']['game']) {
        if (arg is String) {
          args.add(arg);
        } else if (arg is Map && arg.containsKey('value')) {
          // Handle conditional arguments (simplified)
          if (arg['value'] is String) {
            args.add(arg['value']);
          } else if (arg['value'] is List) {
            args.addAll(List<String>.from(arg['value']));
          }
        }
      }
    }
    
    // Replace placeholders
    for (int i = 0; i < args.length; i++) {
      String arg = args[i];
      options.forEach((key, value) {
        arg = arg.replaceAll('\${$key}', value);
        arg = arg.replaceAll('\${auth_player_name}', options['username'] ?? '{username}');
        arg = arg.replaceAll('\${auth_uuid}', options['uuid'] ?? '{uuid}');
        arg = arg.replaceAll('\${auth_access_token}', options['token'] ?? '{token}');
        arg = arg.replaceAll('\${game_directory}', options['gameDirectory'] ?? installPath);
        arg = arg.replaceAll('\${assets_root}', options['assetsRoot'] ?? path.join(installPath, 'assets'));
        arg = arg.replaceAll('\${assets_index_name}', options['assetsIndex'] ?? versionData['id']);
        arg = arg.replaceAll('\${version_name}', options['versionName'] ?? versionData['id']);
        arg = arg.replaceAll('\${version_type}', options['versionType'] ?? versionData['type']);
        arg = arg.replaceAll('\${user_type}', 'msa');
        arg = arg.replaceAll('\${user_properties}', '{}');
      });
      args[i] = arg;
    }
    
    return args;
  }

  /// Get library path from library name
  String getLibraryPath(String libraryName, String installPath) {
    List<String> parts = libraryName.split(':');
    if (parts.length < 3) return '';
    
    String group = parts[0];
    String artifact = parts[1];
    String version = parts[2];
    String extension = 'jar';
    
    // Handle @extension syntax
    if (version.contains('@')) {
      List<String> versionParts = version.split('@');
      version = versionParts[0];
      extension = versionParts[1];
    }
    
    String libraryPath = path.join(installPath, 'libraries');
    for (String groupPart in group.split('.')) {
      libraryPath = path.join(libraryPath, groupPart);
    }
    
    String fileName = '$artifact-$version.$extension';
    return path.join(libraryPath, artifact, version, fileName);
  }

  /// Launch Minecraft with the specified user details
  Future<Process?> launch({
    required String username,
    required String uuid,
    required String accessToken,
    String? javaExecutable,
    List<String>? jvmArguments,
    Map<String, String>? additionalOptions,
    bool showOutput = true,
  }) async {
    try {
      // First check if the version is installed
      if (!isInstalled()) {
        print('Minecraft version $minecraftVersion is not installed. Installing now...');
        await install();
      } else {
        // Make sure natives are extracted (even for previously installed versions)
        String nativesDir = path.join(installPath, 'versions', minecraftVersion, 'natives');
        if (!Directory(nativesDir).existsSync() || Directory(nativesDir).listSync().isEmpty) {
          print('Native libraries not found or empty, extracting them now...');
          await extractAllNatives(minecraftVersion, installPath);
        }
      }
      
      // Generate the launch command
      List<String>? command = await generateLaunchCommand(
        username: username,
        uuid: uuid,
        accessToken: accessToken,
        javaExecutable: javaExecutable,
        jvmArguments: jvmArguments,
        additionalOptions: additionalOptions,
      );
      
      if (command == null || command.isEmpty) {
        throw LaunchException('Failed to generate launch command');
      }
      
      // Print launch command (helpful for debugging)
      print('Launching Minecraft with command:');
      print(command.join(' '));
      
      // Extract the executable and arguments
      String executable = command.removeAt(0);
      List<String> arguments = command;
      
      // Start the process
      print('Starting Minecraft process...');
      Process process = await Process.start(
        executable,
        arguments,
        workingDirectory: installPath,
        runInShell: true,
        mode: ProcessStartMode.normal,
      );
      
      // Show process output if requested
      if (showOutput) {
        // Handle stdout
        process.stdout.transform(utf8.decoder).listen((data) {
          print('[Minecraft] $data');
        });
        
        // Handle stderr
        process.stderr.transform(utf8.decoder).listen((data) {
          print('[Minecraft ERROR] $data');
        });
        
        // Handle process exit
        process.exitCode.then((exitCode) {
          print('Minecraft process exited with code: $exitCode');
        });
      }
      
      return process;
    } catch (e) {
      if (e is DartcraftException) {
        rethrow;
      }
      throw LaunchException('Error launching Minecraft', originalError: e);
    }
  }
  
  /// Extracts all native libraries for the current version
  /// This needs to be done once before launch to ensure all native libraries
  /// are properly extracted to the natives directory
  Future<void> extractNativeLibraries() async {
    // Make sure the version is installed first
    if (!isInstalled()) {
      throw NativeLibraryException('Cannot extract natives: Minecraft version $minecraftVersion is not installed');
    }
    
    try {
      // Extract all native libraries
      await extractAllNatives(minecraftVersion, installPath);
    } catch (e) {
      if (e is DartcraftException) {
        rethrow;
      }
      throw NativeLibraryException('Failed to extract native libraries', originalError: e);
    }
  }
  
  /// Fetch all available Minecraft versions from Mojang's version manifest
  /// Returns a list of version objects with id, type, and releaseTime
  Future<List<Map<String, dynamic>>> getMinecraftVersions() async {
    try {
      String versionManifestUrl = 'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json';
      var response = await http.get(Uri.parse(versionManifestUrl));
      
      if (response.statusCode == 200) {
        var manifest = json.decode(response.body);
        List<dynamic> versions = manifest['versions'];
        
        // Convert to a more convenient list of maps
        List<Map<String, dynamic>> versionList = [];
        for (var version in versions) {
          versionList.add({
            'id': version['id'],
            'type': version['type'],
            'releaseTime': version['releaseTime'],
            'url': version['url'],
          });
        }
        
        return versionList;
      } else {
        throw Exception('Failed to fetch version manifest: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching Minecraft versions: $e');
      return [];
    }
  }
  
  /// Get a filtered list of release versions (excludes snapshots, etc.)
  Future<List<Map<String, dynamic>>> getReleaseVersions() async {
    var versions = await getMinecraftVersions();
    return versions.where((version) => version['type'] == 'release').toList();
  }
  
  /// Get a filtered list of snapshot versions
  Future<List<Map<String, dynamic>>> getSnapshotVersions() async {
    var versions = await getMinecraftVersions();
    return versions.where((version) => version['type'] == 'snapshot').toList();
  }
  
  /// Get the latest release version
  Future<Map<String, dynamic>?> getLatestReleaseVersion() async {
    try {
      String versionManifestUrl = 'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json';
      var response = await http.get(Uri.parse(versionManifestUrl));
      
      if (response.statusCode == 200) {
        var manifest = json.decode(response.body);
        String latestRelease = manifest['latest']['release'];
        
        // Find the full version details
        List<dynamic> versions = manifest['versions'];
        for (var version in versions) {
          if (version['id'] == latestRelease) {
            return {
              'id': version['id'],
              'type': version['type'],
              'releaseTime': version['releaseTime'],
              'url': version['url'],
            };
          }
        }
      }
      
      return null;
    } catch (e) {
      print('Error getting latest release version: $e');
      return null;
    }
  }
  
  /// Get the Microsoft OAuth authorization URL for user login
  String getAuthorizationUrl() {
    return MinecraftAuth.getAuthorizationUrl();
  }
  
  /// Complete the authentication flow by providing the authorization code
  /// Returns player information including username, UUID, and access token
  Future<Map<String, dynamic>> authenticate(String authCode) async {
    try {
      return await MinecraftAuth.completeAuthFlow(authCode);
    } catch (e) {
      print('Authentication failed: $e');
      rethrow;
    }
  }
  
  /// Refresh the Microsoft access token using a refresh token
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      return await MinecraftAuth.refreshMicrosoftToken(refreshToken);
    } catch (e) {
      print('Token refresh failed: $e');
      rethrow;
    }
  }
}

bool downloadFile(String url, String savePath) {
  try {
    Dio dio = Dio();
    dio.download(url, savePath).then((_) {
      print('File downloaded successfully to $savePath');
      return true;
    }).catchError((error) {
      print('Error downloading file: $error');
      return false;
    });
  } catch (e) {
    print('Exception occurred: $e');
    return false;
  }
  return false; // This line is reached if the download is not successful
}

/// Download and save version JSON locally following Minecraft launcher structure
Future<void> downloadAndSaveVersionJson(String versionUrl, String versionSha1, String versionId, String installPath) async {
  try {
    // Create version directory structure: {installPath}/versions/{versionId}/
    String versionDir = path.join(installPath, 'versions', versionId);
    Directory(versionDir).createSync(recursive: true);
    
    // Path for the version JSON file: {installPath}/versions/{versionId}/{versionId}.json
    String versionJsonPath = path.join(versionDir, '$versionId.json');
    
    // Check if version JSON already exists and has correct hash
    if (File(versionJsonPath).existsSync() && await verifyFileSha1(versionJsonPath, versionSha1)) {
      print('Version JSON for $versionId already exists and is valid');
      return;
    }
    
    print('Downloading version JSON for $versionId...');
    await downloadFileWithSha1(versionUrl, versionJsonPath, versionSha1);
    print('Version JSON saved to $versionJsonPath');
    
  } catch (e) {
    print('Error downloading version JSON: $e');
    rethrow;
  }
}

/// Load version data from local JSON file
Future<Map<String, dynamic>?> loadLocalVersionData(String versionId, String installPath) async {
  try {
    String versionJsonPath = path.join(installPath, 'versions', versionId, '$versionId.json');
    
    if (!File(versionJsonPath).existsSync()) {
      print('Version JSON file not found: $versionJsonPath');
      return null;
    }
    
    String jsonContent = await File(versionJsonPath).readAsString();
    Map<String, dynamic> versionData = json.decode(jsonContent);
    
    print('Version data loaded successfully from $versionJsonPath');
    return versionData;
    
  } catch (e) {
    print('Error loading version data: $e');
    return null;
  }
}

/// Check if a version is already installed locally
bool isVersionInstalled(String versionId, String installPath) {
  String versionJsonPath = path.join(installPath, 'versions', versionId, '$versionId.json');
  String clientJarPath = path.join(installPath, 'versions', versionId, '$versionId.jar');
  
  return File(versionJsonPath).existsSync() && File(clientJarPath).existsSync();
}

/// Install all libraries for the given Minecraft version
Future<void> installLibraries(Map<String, dynamic> versionData, String installPath, String minecraftVersion) async {
  print('Installing libraries...');
  
  if (versionData['libraries'] == null) {
    print('No libraries to install');
    return;
  }
  
  List<dynamic> libraries = versionData['libraries'];
  int total = libraries.length;
  int completed = 0;
  
  // Create natives directory
  String nativesDir = path.join(installPath, 'versions', minecraftVersion, 'natives');
  Directory(nativesDir).createSync(recursive: true);
  
  for (var library in libraries) {
    try {
      // Check if the library should be included based on OS rules
      if (library.containsKey('rules') && !parseRuleList(library['rules'])) {
        continue;
      }
      
      String libraryName = library['name'];
      print('Processing library: $libraryName');
      
      // Parse library name (format: group:artifact:version[@extension])
      List<String> parts = libraryName.split(':');
      if (parts.length < 3) continue;
      
      String group = parts[0];
      String artifact = parts[1];
      String version = parts[2];
      String fileExtension = 'jar';
      
      // Handle @extension syntax
      if (version.contains('@')) {
        List<String> versionParts = version.split('@');
        version = versionParts[0];
        fileExtension = versionParts[1];
      }
      
      // Build library path following maven structure
      String libraryPath = path.join(installPath, 'libraries');
      
      // Add base URL if present
      String baseUrl = 'https://libraries.minecraft.net';
      if (library.containsKey('url')) {
        baseUrl = library['url'];
        if (baseUrl.endsWith('/')) {
          baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        }
      }
      
      // Build group path
      for (String groupPart in group.split('.')) {
        libraryPath = path.join(libraryPath, groupPart);
        baseUrl = '$baseUrl/$groupPart';
      }
      libraryPath = path.join(libraryPath, artifact, version);
      baseUrl = '$baseUrl/$artifact/$version';
      
      // Create directories if they don't exist
      Directory(libraryPath).createSync(recursive: true);
      
      String fileName = '$artifact-$version.$fileExtension';
      String fullPath = path.join(libraryPath, fileName);
      String downloadUrl = '$baseUrl/$fileName';
      
      // Handle native libraries
      String nativeSuffix = getNativeLibrarySuffix(library);
      String? nativeFileName;
      String? nativeFullPath;
      
      if (nativeSuffix.isNotEmpty) {
        nativeFileName = '$artifact-$version-$nativeSuffix.jar';
        nativeFullPath = path.join(libraryPath, nativeFileName);
      }
      
      // Download using modern downloads format if available
      if (library.containsKey('downloads')) {
        // Download main artifact
        if (library['downloads'].containsKey('artifact')) {
          var artifactDownload = library['downloads']['artifact'];
          String artifactUrl = artifactDownload['url'];
          String artifactSha1 = artifactDownload['sha1'];
          String artifactPath = path.join(installPath, 'libraries', artifactDownload['path']);
          
          // Create directory for artifact path
          Directory(path.dirname(artifactPath)).createSync(recursive: true);
          await downloadFileWithSha1(artifactUrl, artifactPath, artifactSha1);
        }
        
        // Download native classifier if present
        if (nativeSuffix.isNotEmpty && 
            library['downloads'].containsKey('classifiers') &&
            library['downloads']['classifiers'].containsKey(nativeSuffix)) {
          var classifier = library['downloads']['classifiers'][nativeSuffix];
          String classifierUrl = classifier['url'];
          String classifierSha1 = classifier['sha1'];
          String classifierPath = path.join(installPath, 'libraries', classifier['path']);
          
          // Create directory for classifier path
          Directory(path.dirname(classifierPath)).createSync(recursive: true);
          await downloadFileWithSha1(classifierUrl, classifierPath, classifierSha1);
          
          // Extract natives immediately during installation
          await extractNatives(classifierPath, nativesDir, library);
        }
      } else {
        // Fallback to URL construction (for older versions)
        try {
          await downloadFileWithSha1(downloadUrl, fullPath, null);
        } catch (e) {
          print('Failed to download library $libraryName from constructed URL: $e');
        }
        
        // Handle native library for old format
        if (nativeSuffix.isNotEmpty) {
          String nativeUrl = '$baseUrl/$nativeFileName';
          try {
            await downloadFileWithSha1(nativeUrl, nativeFullPath!, null);
            // Extract natives immediately
            await extractNatives(nativeFullPath, nativesDir, library);
          } catch (e) {
            print('Failed to download native library $nativeFileName: $e');
          }
        }
      }
      
      completed++;
      print('Library progress: $completed/$total');
      
    } catch (e) {
      print('Error installing library ${library['name']}: $e');
    }
  }
  
  print('Libraries installation completed');
}

/// Install all assets for the given Minecraft version
Future<void> installAssets(Map<String, dynamic> versionData, String installPath) async {
  print('Installing assets...');
  
  // Old versions don't have asset index
  if (!versionData.containsKey('assetIndex')) {
    print('No asset index found, skipping assets installation');
    return;
  }
  
  var assetIndex = versionData['assetIndex'];
  String assetsVersion = versionData['assets'];
  String assetIndexUrl = assetIndex['url'];
  String assetIndexSha1 = assetIndex['sha1'];
  
  // Download asset index
  String indexesPath = path.join(installPath, 'assets', 'indexes');
  Directory(indexesPath).createSync(recursive: true);
  String indexPath = path.join(indexesPath, '$assetsVersion.json');
  
  await downloadFileWithSha1(assetIndexUrl, indexPath, assetIndexSha1);
  
  // Read asset index
  String indexContent = File(indexPath).readAsStringSync();
  Map<String, dynamic> assetData = json.decode(indexContent);
  
  if (!assetData.containsKey('objects')) {
    print('No objects found in asset index');
    return;
  }
  
  Map<String, dynamic> objects = assetData['objects'];
  
  // Create set of unique hashes (like minecraft-launcher-lib does)
  Set<String> assetHashes = objects.values.map((asset) => asset['hash'] as String).toSet();
  int total = assetHashes.length;
  int completed = 0;
  
  print('Found $total unique assets to download');
  
  // Create objects directory
  String objectsPath = path.join(installPath, 'assets', 'objects');
  Directory(objectsPath).createSync(recursive: true);
  
  // Download each unique asset by hash
  for (String hash in assetHashes) {
    try {
      // Assets are stored in subdirectories based on first 2 characters of hash
      String hashPrefix = hash.substring(0, 2);
      String assetDir = path.join(objectsPath, hashPrefix);
      Directory(assetDir).createSync(recursive: true);
      
      String assetPath = path.join(assetDir, hash);
      
      // Skip if file already exists and has correct hash
      if (File(assetPath).existsSync() && await verifyFileSha1(assetPath, hash)) {
        completed++;
        continue;
      }
      
      String downloadUrl = 'https://resources.download.minecraft.net/$hashPrefix/$hash';
      await downloadFileWithSha1(downloadUrl, assetPath, hash);
      
      completed++;
      if (completed % 100 == 0 || completed == total) {
        print('Assets progress: $completed/$total');
      }
      
    } catch (e) {
      print('Error downloading asset with hash $hash: $e');
    }
  }
  
  print('Assets installation completed');
}

/// Download a file with optional SHA1 verification
Future<bool> downloadFileWithSha1(String url, String savePath, String? expectedSha1) async {
  try {
    // Skip download if file exists and has correct hash
    if (File(savePath).existsSync() && expectedSha1 != null) {
      if (await verifyFileSha1(savePath, expectedSha1)) {
        return true;
      }
    }
    
    Dio dio = Dio();
    await dio.download(url, savePath);
    
    // Verify SHA1 if provided
    if (expectedSha1 != null) {
      if (!await verifyFileSha1(savePath, expectedSha1)) {
        print('SHA1 mismatch for $savePath');
        File(savePath).deleteSync();
        return false;
      }
    }
    
    return true;
  } catch (e) {
    print('Error downloading $url: $e');
    return false;
  }
}

/// Verify SHA1 hash of a file
Future<bool> verifyFileSha1(String filePath, String expectedSha1) async {
  try {
    var file = File(filePath);
    if (!file.existsSync()) return false;
    
    var bytes = await file.readAsBytes();
    var digest = sha1.convert(bytes);
    return digest.toString() == expectedSha1.toLowerCase();
  } catch (e) {
    return false;
  }
}

/// Parse rule list to determine if a library should be included
bool parseRuleList(List<dynamic> rules) {
  for (var rule in rules) {
    if (!parseSingleRule(rule)) {
      return false;
    }
  }
  return true;
}

/// Parse a single rule
bool parseSingleRule(Map<String, dynamic> rule) {
  String action = rule['action'];
  bool returnValue = action == 'disallow';
  
  // Check OS rules
  if (rule.containsKey('os')) {
    var osRule = rule['os'];
    if (osRule.containsKey('name')) {
      String osName = osRule['name'];
      String currentOs = Platform.operatingSystem;
      
      if (osName == 'windows' && currentOs != 'windows') {
        return returnValue;
      } else if (osName == 'osx' && currentOs != 'macos') {
        return returnValue;
      } else if (osName == 'linux' && currentOs != 'linux') {
        return returnValue;
      }
    }
    
    if (osRule.containsKey('arch')) {
      String arch = osRule['arch'];
      // Simple arch check - could be enhanced
      if (arch == 'x86' && Platform.version.contains('64')) {
        return returnValue;
      }
    }
  }
  
  // For simplicity, we'll assume features rules are not blocking
  // In a full implementation, you'd check features like customResolution, etc.
  
  return !returnValue;
}

/// Get native library suffix for the current platform
String getNativeLibrarySuffix(Map<String, dynamic> library) {
  if (!library.containsKey('natives')) {
    return '';
  }
  
  var natives = library['natives'];
  String os = Platform.operatingSystem;
  
  // Get the architecture - properly handle different platforms
  String arch;
  if (os == 'windows') {
    arch = Platform.version.contains('64') ? '64' : '32';
  } else if (os == 'macos') {
    arch = '64'; // macOS is always 64-bit these days
  } else {
    // Linux and other platforms
    arch = Platform.version.contains('64') ? '64' : '32';
  }
  
  String? nativeKey;
  if (os == 'windows' && natives.containsKey('windows')) {
    nativeKey = natives['windows'];
  } else if (os == 'macos' && natives.containsKey('osx')) {
    nativeKey = natives['osx'];
  } else if (os == 'linux' && natives.containsKey('linux')) {
    nativeKey = natives['linux'];
  }
  
  if (nativeKey != null) {
    return nativeKey.replaceAll('\${arch}', arch);
  }
  
  return '';
}

/// Extract native libraries from a JAR file
Future<void> extractNatives(String jarPath, String extractPath, Map<String, dynamic> library) async {
  try {
    Directory(extractPath).createSync(recursive: true);
    
    var jarFile = File(jarPath);
    if (!jarFile.existsSync()) {
      print('JAR file not found: $jarPath');
      return;
    }
    
    var bytes = jarFile.readAsBytesSync();
    var archive = ZipDecoder().decodeBytes(bytes);
    
    // Get exclude patterns
    Set<String> excludePatterns = {};
    if (library.containsKey('extract') && library['extract'].containsKey('exclude')) {
      List<dynamic> excludes = library['extract']['exclude'];
      excludePatterns = excludes.map((e) => e.toString()).toSet();
    }
    
    print('Extracting natives from ${path.basename(jarPath)} to $extractPath');
    int extractCount = 0;
    
    for (var file in archive) {
      if (file.isFile) {
        // Check if file should be excluded
        bool shouldExclude = false;
        for (String pattern in excludePatterns) {
          if (file.name.startsWith(pattern)) {
            shouldExclude = true;
            break;
          }
        }
        
        if (!shouldExclude) {
          String fileName = path.basename(file.name);
          String outputPath = path.join(extractPath, fileName);
          
          // Check if the file is a dylib/dll/so (native library)
          if (fileName.endsWith('.dll') || fileName.endsWith('.dylib') || fileName.endsWith('.so')) {
            File(outputPath).writeAsBytesSync(file.content as List<int>);
            extractCount++;
            print('  Extracted native: $fileName');
          }
          // Also extract jnilib files for macOS
          else if (fileName.endsWith('.jnilib')) {
            // On macOS, we need to rename .jnilib to .dylib
            String renamedPath = outputPath.replaceAll('.jnilib', '.dylib');
            File(renamedPath).writeAsBytesSync(file.content as List<int>);
            extractCount++;
            print('  Extracted native (renamed): $fileName -> ${path.basename(renamedPath)}');
          }
        }
      }
    }
    
    print('Extracted $extractCount native libraries from ${path.basename(jarPath)}');
  } catch (e) {
    print('Error extracting natives from $jarPath: $e');
  }
}

/// Extract natives from a JAR file without needing version data
Future<void> extractNativesFromJar(String jarPath, String extractPath) async {
  try {
    Directory(extractPath).createSync(recursive: true);
    
    var jarFile = File(jarPath);
    if (!jarFile.existsSync()) {
      print('JAR file not found: $jarPath');
      return;
    }
    
    var bytes = jarFile.readAsBytesSync();
    var archive = ZipDecoder().decodeBytes(bytes);
    
    print('Extracting all files from ${path.basename(jarPath)} to $extractPath');
    int extractCount = 0;
    
    for (var file in archive) {
      if (file.isFile) {
        String fileName = path.basename(file.name);
        String outputPath = path.join(extractPath, fileName);
        
        // Extract all files (especially native libraries)
        File(outputPath).writeAsBytesSync(file.content as List<int>);
        extractCount++;
        
        // Make all extracted files executable on macOS/Linux
        if (Platform.isLinux || Platform.isMacOS) {
          try {
            await Process.run('chmod', ['+x', outputPath]);
          } catch (e) {
            print('Warning: Could not make file executable: $outputPath');
          }
        }
      }
    }
    
    print('Extracted $extractCount files from ${path.basename(jarPath)}');
  } catch (e) {
    print('Error extracting files from $jarPath: $e');
  }
}

/// Install Java runtime for Minecraft
Future<void> installRuntime(String jvmVersion, String installPath) async {
  print('Installing Java runtime: $jvmVersion');
  
  try {
    // Check if runtime is already installed
    String runtimePath = path.join(installPath, 'runtime', jvmVersion);
    if (Directory(runtimePath).existsSync()) {
      print('Java runtime $jvmVersion already installed');
      return;
    }
    
    // Get JVM manifest
    String manifestUrl = 'https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json';
    var manifestResponse = await http.get(Uri.parse(manifestUrl));
    
    if (manifestResponse.statusCode != 200) {
      print('Failed to fetch JVM manifest: ${manifestResponse.statusCode}');
      return;
    }
    
    Map<String, dynamic> manifestData = json.decode(manifestResponse.body);
    String platformString = getJvmPlatformString();
    
    // Check if the JVM version exists for this platform
    if (!manifestData.containsKey(platformString) || 
        !manifestData[platformString].containsKey(jvmVersion)) {
      print('JVM version $jvmVersion not found for platform $platformString');
      return;
    }
    
    List<dynamic> versionList = manifestData[platformString][jvmVersion];
    if (versionList.isEmpty) {
      print('No runtime manifest available for $jvmVersion on $platformString');
      return;
    }
    
    // Get platform manifest
    String platformManifestUrl = versionList[0]['manifest']['url'];
    var platformResponse = await http.get(Uri.parse(platformManifestUrl));
    
    if (platformResponse.statusCode != 200) {
      print('Failed to fetch platform manifest: ${platformResponse.statusCode}');
      return;
    }
    
    Map<String, dynamic> platformManifest = json.decode(platformResponse.body);
    Map<String, dynamic> files = platformManifest['files'];
    
    String basePath = path.join(installPath, 'runtime', jvmVersion, platformString, jvmVersion);
    Directory(basePath).createSync(recursive: true);
    
    print('Found ${files.length} files to download for Java runtime');
    
    int completed = 0;
    List<String> fileList = [];
    
    // Download all runtime files
    for (String filePath in files.keys) {
      try {
        var fileInfo = files[filePath];
        String fullPath = path.join(basePath, filePath);
        
        if (fileInfo['type'] == 'file') {
          // Create directory if needed
          Directory(path.dirname(fullPath)).createSync(recursive: true);
          
          // Prefer LZMA compressed download if available
          Map<String, dynamic> downloads = fileInfo['downloads'];
          String downloadUrl;
          String expectedSha1 = downloads['raw']['sha1'];
          bool isLzmaCompressed = false;
          
          if (downloads.containsKey('lzma')) {
            downloadUrl = downloads['lzma']['url'];
            isLzmaCompressed = true;
          } else {
            downloadUrl = downloads['raw']['url'];
          }
          
          // Download the file
          await downloadRuntimeFile(downloadUrl, fullPath, expectedSha1, isLzmaCompressed);
          
          // Make file executable if needed (Unix-like systems)
          if (fileInfo['executable'] && (Platform.isLinux || Platform.isMacOS)) {
            await Process.run('chmod', ['+x', fullPath]);
          }
          
          fileList.add(filePath);
          
        } else if (fileInfo['type'] == 'directory') {
          Directory(fullPath).createSync(recursive: true);
          
        } else if (fileInfo['type'] == 'link') {
          // Create symbolic link
          String target = fileInfo['target'];
          String targetPath = path.join(basePath, target);
          
          try {
            if (Platform.isWindows) {
              // On Windows, create a copy instead of symlink
              if (File(targetPath).existsSync()) {
                File(targetPath).copySync(fullPath);
              }
            } else {
              // Create symbolic link on Unix-like systems
              Link(fullPath).createSync(target);
            }
          } catch (e) {
            print('Failed to create link $filePath -> $target: $e');
          }
        }
        
        completed++;
        if (completed % 10 == 0 || completed == files.length) {
          print('Runtime progress: $completed/${files.length}');
        }
        
      } catch (e) {
        print('Error processing runtime file $filePath: $e');
      }
    }
    
    // Create .version file
    String versionPath = path.join(installPath, 'runtime', jvmVersion, platformString, '.version');
    String versionName = versionList[0]['version']['name'];
    File(versionPath).writeAsStringSync(versionName);
    
    // Create .sha1 file
    String sha1Path = path.join(installPath, 'runtime', jvmVersion, platformString, '$jvmVersion.sha1');
    StringBuffer sha1Content = StringBuffer();
    
    for (String filePath in fileList) {
      try {
        String fullPath = path.join(basePath, filePath);
        var file = File(fullPath);
        if (file.existsSync()) {
          var stat = file.statSync();
          var bytes = file.readAsBytesSync();
          var digest = sha1.convert(bytes);
          // Creation time in nanoseconds (approximation)
          int ctimeNs = stat.modified.millisecondsSinceEpoch * 1000000;
          sha1Content.writeln('$filePath /#// ${digest.toString()} $ctimeNs');
        }
      } catch (e) {
        print('Error calculating SHA1 for $filePath: $e');
      }
    }
    
    File(sha1Path).writeAsStringSync(sha1Content.toString());
    
    print('Java runtime $jvmVersion installation completed');
    
  } catch (e) {
    print('Error installing Java runtime: $e');
  }
}

/// Download a runtime file with optional LZMA decompression
Future<void> downloadRuntimeFile(String url, String savePath, String expectedSha1, bool isLzmaCompressed) async {
  try {
    // Skip if file exists and has correct hash
    if (File(savePath).existsSync() && await verifyFileSha1(savePath, expectedSha1)) {
      return;
    }
    
    var response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      List<int> data = response.bodyBytes;
      
      // Decompress LZMA if needed
      if (isLzmaCompressed) {
        // Note: Dart doesn't have built-in LZMA support
        // For simplicity, we'll fall back to raw download
        // In a full implementation, you'd use an LZMA package
        print('LZMA decompression not implemented, falling back to raw download');
        return;
      }
      
      File(savePath).writeAsBytesSync(data);
      
      // Verify SHA1
      if (!await verifyFileSha1(savePath, expectedSha1)) {
        print('SHA1 verification failed for $savePath');
        File(savePath).deleteSync();
      }
    } else {
      print('Failed to download $url: ${response.statusCode}');
    }
  } catch (e) {
    print('Error downloading runtime file $url: $e');
  }
}

/// Get the platform string for JVM runtime
String getJvmPlatformString() {
  if (Platform.isWindows) {
    // Check architecture - simplified approach
    if (Platform.version.contains('32')) {
      return 'windows-x86';
    } else {
      return 'windows-x64';
    }
  } else if (Platform.isLinux) {
    if (Platform.version.contains('32')) {
      return 'linux-i386';
    } else {
      return 'linux';
    }
  } else if (Platform.isMacOS) {
    // Check if it's ARM64 (Apple Silicon)
    if (Platform.version.contains('arm64')) {
      return 'mac-os-arm64';
    } else {
      return 'mac-os';
    }
  } else {
    return 'gamecore'; // Fallback
  }
}

/// Get the path to the Java executable for a runtime
String? getJavaExecutablePath(String jvmVersion, String installPath) {
  String platformString = getJvmPlatformString();
  String basePath = path.join(installPath, 'runtime', jvmVersion, platformString, jvmVersion);
  
  // Standard path
  String javaPath = path.join(basePath, 'bin', 'java');
  if (Platform.isWindows) {
    javaPath += '.exe';
  }
  
  if (File(javaPath).existsSync()) {
    return javaPath;
  }
  
  // macOS bundle path
  if (Platform.isMacOS) {
    String bundlePath = path.join(basePath, 'jre.bundle', 'Contents', 'Home', 'bin', 'java');
    if (File(bundlePath).existsSync()) {
      return bundlePath;
    }
  }
  
  return null;
}

/// Install logging configuration if present
Future<void> installLoggingConfig(Map<String, dynamic> versionData, String installPath) async {
  if (!versionData.containsKey('logging')) {
    return;
  }
  
  var logging = versionData['logging'];
  if (logging.isEmpty) {
    return;
  }
  
  if (!logging.containsKey('client')) {
    return;
  }
  
  var clientLogging = logging['client'];
  if (!clientLogging.containsKey('file')) {
    return;
  }
  
  var logFile = clientLogging['file'];
  String logFileId = logFile['id'];
  String logFileUrl = logFile['url'];
  String logFileSha1 = logFile['sha1'];
  
  // Create log_configs directory
  String logConfigsPath = path.join(installPath, 'assets', 'log_configs');
  Directory(logConfigsPath).createSync(recursive: true);
  
  String logConfigPath = path.join(logConfigsPath, logFileId);
  
  print('Downloading logging configuration: $logFileId');
  await downloadFileWithSha1(logFileUrl, logConfigPath, logFileSha1);
  print('Logging configuration installed');
}

/// Handle version inheritance (for Forge and other modded versions)
Future<Map<String, dynamic>?> handleVersionInheritance(Map<String, dynamic> versionData, String installPath) async {
  if (!versionData.containsKey('inheritsFrom')) {
    return versionData;
  }
  
  String inheritsFrom = versionData['inheritsFrom'];
  print('Version inherits from: $inheritsFrom');
  
  // Try to install the parent version if it doesn't exist
  try {
    if (!isVersionInstalled(inheritsFrom, installPath)) {
      print('Installing parent version: $inheritsFrom');
      var parentDartcraft = Dartcraft(inheritsFrom, installPath);
      await parentDartcraft.install();
    }
  } catch (e) {
    print('Failed to install parent version $inheritsFrom: $e');
  }
  
  // Load parent version data
  var parentData = await loadLocalVersionData(inheritsFrom, installPath);
  if (parentData == null) {
    print('Could not load parent version data for $inheritsFrom');
    return versionData;
  }
  
  // Merge version data (simplified inheritance)
  Map<String, dynamic> mergedData = Map.from(parentData);
  
  // Override with child version data
  versionData.forEach((key, value) {
    if (key == 'libraries') {
      // Merge libraries, avoiding duplicates
      List<dynamic> parentLibs = List.from(mergedData['libraries'] ?? []);
      List<dynamic> childLibs = List.from(value ?? []);
      
      // Create a set of library names from child for quick lookup
      Set<String> childLibNames = childLibs
          .map((lib) => _getLibraryNameWithoutVersion(lib['name']))
          .toSet();
      
      // Add parent libraries that aren't overridden by child
      for (var parentLib in parentLibs) {
        String parentLibName = _getLibraryNameWithoutVersion(parentLib['name']);
        if (!childLibNames.contains(parentLibName)) {
          childLibs.add(parentLib);
        }
      }
      
      mergedData[key] = childLibs;
    } else if (value is List && mergedData[key] is List) {
      // Merge arrays
      mergedData[key] = List.from(value)..addAll(mergedData[key]);
    } else if (value is Map && mergedData[key] is Map) {
      // Merge objects (simplified)
      Map<String, dynamic> merged = Map.from(mergedData[key]);
      (value as Map<String, dynamic>).forEach((k, v) {
        merged[k] = v;
      });
      mergedData[key] = merged;
    } else {
      // Override with child value
      mergedData[key] = value;
    }
  });
  
  return mergedData;
}

/// Get library name without version for inheritance comparison
String _getLibraryNameWithoutVersion(String fullName) {
  List<String> parts = fullName.split(':');
  if (parts.length >= 2) {
    return '${parts[0]}:${parts[1]}';
  }
  return fullName;
}

/// Extract all native libraries needed for a specific version
Future<void> extractAllNatives(String versionId, String installPath) async {
  print('Extracting all native libraries for $versionId...');
  
  try {
    // Check if version exists
    String versionJsonPath = path.join(installPath, 'versions', versionId, '$versionId.json');
    if (!File(versionJsonPath).existsSync()) {
      throw NativeLibraryException('Version JSON not found for $versionId');
    }
    
    // Clean the natives directory first
    String nativesDir = path.join(installPath, 'versions', versionId, 'natives');
    if (Directory(nativesDir).existsSync()) {
      print('Cleaning old natives directory: $nativesDir');
      Directory(nativesDir).deleteSync(recursive: true);
    }
    
    // Create natives directory
    Directory(nativesDir).createSync(recursive: true);
    
    // For LWJGL, we need to manually extract the native libraries
    // Find all LWJGL native JARs
    String os = Platform.operatingSystem;
    String arch = await _getSystemArchitecture();
    
    print('Detected system: $os, architecture: $arch');
    
    String nativeSuffix;
    String nativeSuffixWithArch;
    
    if (os == 'windows') {
      nativeSuffix = 'natives-windows';
      nativeSuffixWithArch = arch == 'arm64' ? 'natives-windows-arm64' : 'natives-windows';
    } else if (os == 'macos') {
      nativeSuffix = 'natives-macos';
      nativeSuffixWithArch = arch == 'arm64' ? 'natives-macos-arm64' : 'natives-macos';
    } else {
      nativeSuffix = 'natives-linux';
      nativeSuffixWithArch = arch == 'arm64' ? 'natives-linux-arm64' : 'natives-linux';
    }
    
    // Find all native libraries in the libraries directory
    String lwjglPath = path.join(installPath, 'libraries', 'org', 'lwjgl');
    if (Directory(lwjglPath).existsSync()) {
      print('Looking for LWJGL native libraries with suffix: $nativeSuffixWithArch');
      
      var lwjglDir = Directory(lwjglPath);
      List<File> nativeJars = [];
      
      // First try to find architecture-specific JARs (arm64 or x64)
      await for (var entity in lwjglDir.list(recursive: true)) {
        if (entity is File && entity.path.contains(nativeSuffixWithArch) && entity.path.endsWith('.jar')) {
          nativeJars.add(entity);
        }
      }
      
      // If no architecture-specific JARs found, fallback to generic ones
      if (nativeJars.isEmpty) {
        print('No architecture-specific native JARs found, using generic natives');
        await for (var entity in lwjglDir.list(recursive: true)) {
          if (entity is File && entity.path.contains(nativeSuffix) && 
              !entity.path.contains('-arm64') && 
              !entity.path.contains('-x86') && 
              entity.path.endsWith('.jar')) {
            nativeJars.add(entity);
          }
        }
      }
      
      // Extract all found native JARs
      for (var jar in nativeJars) {
        print('Found LWJGL native JAR: ${jar.path}');
        await extractNativesFromJar(jar.path, nativesDir);
      }
    } else {
      print('LWJGL libraries not found at $lwjglPath. This may be normal for some versions.');
    }
    
    // Now extract any other native libraries based on the version JSON
    await extractNativesFromJson(versionId, installPath, nativesDir, arch);
    
    print('Native libraries extraction completed');
  } catch (e) {
    if (e is DartcraftException) {
      rethrow;
    }
    throw NativeLibraryException('Error extracting native libraries', originalError: e);
  }
}

/// Get the system architecture (arm64 or x64)
Future<String> _getSystemArchitecture() async {
  try {
    var result = await Process.run('uname', ['-m']);
    if (result.exitCode == 0) {
      String output = result.stdout.toString().trim();
      if (output == 'arm64' || output.contains('aarch64')) {
        return 'arm64';
      }
    }
    
    // Default to x64 if can't determine or not arm64
    return 'x64';
  } catch (e) {
    print('Error determining system architecture: $e');
    // Fallback based on dart's Platform info
    return Platform.version.toLowerCase().contains('arm') ? 'arm64' : 'x64';
  }
}

/// Extract natives based on version JSON data
Future<void> extractNativesFromJson(String versionId, String installPath, String nativesDir, String arch) async {
  try {
    // Load version data
    String versionJsonPath = path.join(installPath, 'versions', versionId, '$versionId.json');
    String jsonContent = await File(versionJsonPath).readAsString();
    Map<String, dynamic> versionData = json.decode(jsonContent);
    
    // Handle inheritance
    if (versionData.containsKey('inheritsFrom')) {
      versionData = await handleVersionInheritance(versionData, installPath) ?? versionData;
    }
    
    // Process each library
    if (versionData.containsKey('libraries')) {
      for (var library in versionData['libraries']) {
        // Check rules
        if (library.containsKey('rules') && !parseRuleList(library['rules'])) {
          continue;
        }
        
        String nativeSuffix = getNativeLibrarySuffix(library);
        if (nativeSuffix.isEmpty) {
          continue; // Not a native library
        }
        
        // Try to get architecture-specific version first
        String nativeSuffixWithArch = nativeSuffix;
        if (arch == 'arm64' && Platform.isMacOS) {
          // For macOS arm64, try to use natives-macos-arm64 if available
          if (nativeSuffix.contains('osx')) {
            nativeSuffixWithArch = nativeSuffix.replaceAll('osx', 'osx-arm64');
          } else if (nativeSuffix.contains('macos')) {
            nativeSuffixWithArch = nativeSuffix.replaceAll('macos', 'macos-arm64');
          }
        }
        
        // Get the native JAR path
        String nativeJarPath = '';
        bool foundJar = false;
        
        // First try with architecture-specific classifier
        if (library.containsKey('downloads') && 
            library['downloads'].containsKey('classifiers') && 
            library['downloads']['classifiers'].containsKey(nativeSuffixWithArch)) {
          var classifier = library['downloads']['classifiers'][nativeSuffixWithArch];
          nativeJarPath = path.join(installPath, 'libraries', classifier['path']);
          foundJar = true;
        } 
        // Fall back to generic classifier
        else if (library.containsKey('downloads') && 
            library['downloads'].containsKey('classifiers') && 
            library['downloads']['classifiers'].containsKey(nativeSuffix)) {
          var classifier = library['downloads']['classifiers'][nativeSuffix];
          nativeJarPath = path.join(installPath, 'libraries', classifier['path']);
          foundJar = true;
        }
        // Legacy format - construct path from library name
        else {
          // Try arch-specific path first
          String archPath = path.join(installPath, 'libraries', _constructLibraryPath(library['name'], nativeSuffixWithArch));
          if (File(archPath).existsSync()) {
            nativeJarPath = archPath;
            foundJar = true;
          } else {
            // Fall back to generic path
            String genericPath = path.join(installPath, 'libraries', _constructLibraryPath(library['name'], nativeSuffix));
            if (File(genericPath).existsSync()) {
              nativeJarPath = genericPath;
              foundJar = true;
            }
          }
        }
        
        // Extract natives if the JAR exists
        if (foundJar && File(nativeJarPath).existsSync()) {
          await extractNativesFromJar(nativeJarPath, nativesDir);
        }
      }
    }
  } catch (e) {
    print('Error extracting natives from JSON: $e');
  }
}

/// Construct library path from name and native suffix for older versions
String _constructLibraryPath(String libraryName, String nativeSuffix) {
  List<String> parts = libraryName.split(':');
  if (parts.length < 3) return '';
  
  String group = parts[0];
  String artifact = parts[1];
  String version = parts[2];
  
  // Handle @extension syntax
  if (version.contains('@')) {
    List<String> versionParts = version.split('@');
    version = versionParts[0];
  }
  
  // Convert group to path
  String groupPath = group.replaceAll('.', '/');
  
  // Construct file name with native suffix
  String fileName = '$artifact-$version-$nativeSuffix.jar';
  
  // Return full path
  return path.join(groupPath, artifact, version, fileName);
}
