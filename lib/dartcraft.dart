/// Dartcraft - A modern Minecraft launcher library for Dart
///
/// Provides comprehensive functionality for creating custom Minecraft launchers
/// including game installation, version management, authentication, and launching.
///
/// ## Features
///
/// - **Complete Minecraft Support**: Install and launch any Minecraft version
/// - **Multiple Authentication**: Microsoft Account and Ely.by authentication
/// - **Cross-Platform**: Full support for Windows, macOS, and Linux
/// - **Modern Architecture**: Built with async/await patterns
/// - **Asset Management**: Automatic download and verification
/// - **Flexible Configuration**: Customizable launch parameters
///
/// ## Usage
///
/// ```dart
/// import 'package:dartcraft/dartcraft.dart';
///
/// // Create launcher instance
/// final launcher = Dartcraft('1.20.4', '/path/to/minecraft');
///
/// // Install if needed
/// if (!launcher.isInstalled) {
///   await launcher.install();
/// }
///
/// // Launch the game
/// final process = await launcher.launch(
///   username: 'PlayerName',
///   uuid: 'player-uuid',
///   accessToken: 'access-token',
/// );
/// ```
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
export 'src/auth/ely_auth.dart' show ElyAuth, ElyAuthException;
