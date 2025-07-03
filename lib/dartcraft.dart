/// Dartcraft - A modern, cross-platform Minecraft launcher library for Dart
///
/// Provides comprehensive functionality for creating custom Minecraft launchers
/// with support for game installation, version management, user authentication,
/// and launching across Windows, macOS, and Linux platforms.
///
/// ## Features
///
/// - **Complete Minecraft Support**: Install and launch any Minecraft version (release, snapshot, modded)
/// - **Multiple Authentication**: Microsoft Account and Ely.by OAuth2 authentication with 2FA support
/// - **Cross-Platform**: Full support for Windows, macOS, and Linux
/// - **Modern Architecture**: Built with async/await patterns and comprehensive error handling
/// - **Asset Management**: Automatic download and verification of game assets and libraries
/// - **Security**: SHA1 verification for downloads, PKCE OAuth2 flow, secure token management
/// - **Authlib Integration**: Automatic authlib-injector download and configuration for Ely.by
///
/// ## Quick Start
///
/// ```dart
/// import 'package:dartcraft/dartcraft.dart';
///
/// void main() async {
///   // Create launcher instance
///   final launcher = Dartcraft('1.20.4', '/path/to/minecraft');
///
///   // Install Minecraft if not already installed
///   if (!launcher.isInstalled) {
///     print('Installing Minecraft...');
///     await launcher.install();
///   }
///
///   // Authenticate with Ely.by (OAuth2 browser flow)
///   const config = ElyOAuthConfig(
///     clientId: 'your-client-id',
///     clientSecret: 'your-client-secret',
///   );
///   
///   final auth = await ElyAuth.authenticateWithOAuth(config);
///
///   // Launch the game
///   final process = await launcher.launch(
///     username: auth.minecraftUsername,
///     uuid: auth.minecraftUuid,
///     accessToken: auth.minecraftAccessToken,
///   );
///   
///   print('Minecraft launched successfully!');
///   await process.exitCode;
/// }
/// ```
///
/// ## Authentication
///
/// ### Ely.by OAuth2 (Recommended)
/// 
/// ```dart
/// const config = ElyOAuthConfig(
///   clientId: 'your-client-id',
///   clientSecret: 'your-client-secret',
/// );
/// 
/// final result = await ElyAuth.authenticateWithOAuth(config);
/// // Browser opens automatically for secure authentication
/// ```
///
/// ### Ely.by Username/Password
/// 
/// ```dart
/// final launcher = Dartcraft('1.20.4', '/minecraft', useElyBy: true);
/// final auth = await launcher.authenticateWithElyBy('username', 'password');
/// ```
///
/// ## Version Management
///
/// ```dart
/// // Get all available versions
/// final versions = await Dartcraft.getAvailableVersions();
/// 
/// // Get stable releases only
/// final releases = await Dartcraft.getReleaseVersions();
/// 
/// // Use latest release
/// final latest = releases.first;
/// final launcher = Dartcraft(latest.id, '/minecraft');
/// ```
///
/// For more examples and detailed documentation, visit:
/// https://github.com/prtm-bg/dartcraft
library dartcraft;

// Core launcher functionality
export 'src/core/launcher.dart' show 
    Dartcraft, 
    MinecraftVersion, 
    VersionType, 
    AuthenticationResult,
    TwoFactorRequiredException;

// Exception types
export 'src/exceptions/exceptions.dart';

// Authentication modules
export 'src/auth/microsoft_auth.dart' show MicrosoftAuth;
export 'src/auth/ely_auth.dart' show 
    ElyAuth, 
    ElyAuthException,
    ElyOAuthConfig,
    ElyOAuthToken,
    ElyUser,
    ElyAuthResult;
