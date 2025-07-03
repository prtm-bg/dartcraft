# Dartcraft

[![pub package](https://img.shields.io/pub/v/dartcraft.svg)](https://pub.dev/packages/dartcraft)
[![Dart Version](https://badgen.net/badge/Dart/%3E=3.5.3/blue)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A modern, cross-platform Minecraft launcher library for Dart and Flutter applications. Dartcraft provides comprehensive functionality for creating custom Minecraft launchers with support for game installation, version management, user authentication, and launching.

## Features

- 🎮 **Complete Minecraft Support**: Install and launch any Minecraft version (release, snapshot, modded)
- 🔐 **Multiple Authentication**: Microsoft Account and Ely.by authentication with 2FA support
- 🌍 **Cross-Platform**: Full support for Windows, macOS, and Linux
- 🚀 **Modern Architecture**: Built with async/await patterns and comprehensive error handling
- 📦 **Asset Management**: Automatic download and verification of game assets and libraries
- 🔧 **Flexible Configuration**: Customizable launch parameters and Java runtime options
- 🛡️ **Security**: SHA1 verification for all downloads and secure token management
- 💾 **Memory Efficient**: Streaming downloads for large files

## Status

### ✅ Fully Implemented & Tested
- **Ely.by OAuth2 Authentication**: Complete browser-based OAuth2 flow with PKCE security
- **Cross-platform URL launching**: Works on Windows, macOS, and Linux
- **Token management**: Automatic refresh and validation

### ⚠️ Implemented but Not Yet Tested
- **Microsoft Authentication**: OAuth2 flow implementation exists but requires testing
- **Modded Minecraft Support**: Forge, Fabric, and other mod loaders support exists but needs validation
- **Java runtime detection**: Automatic Java detection across platforms

### 🚧 Planned Features
- **Profile management**: Multiple player profiles and configurations
- **Mod management**: Automatic mod installation and updates
- **Offline mode**: Cached authentication for offline play

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  dartcraft: ^1.0.0
```

Then run:

```bash
dart pub get
```

## Quick Start

```dart
import 'package:dartcraft/dartcraft.dart';

void main() async {
  // Create a launcher instance
  final launcher = Dartcraft(
    '1.20.4', // Minecraft version
    '/path/to/minecraft', // Installation directory
  );

  // Install Minecraft if not already installed
  if (!launcher.isInstalled) {
    print('Installing Minecraft...');
    await launcher.install();
  }

  // Launch the game
  final process = await launcher.launch(
    username: 'PlayerName',
    uuid: 'player-uuid-here',
    accessToken: 'access-token-here',
  );

  print('Minecraft launched successfully!');
}
```

## Authentication

### Microsoft Authentication

```dart
import 'package:dartcraft/dartcraft.dart';

void main() async {
  // Configure Microsoft OAuth2 (register your app at https://portal.azure.com)
  MicrosoftAuth.configure(
    clientId: 'your-client-id',
    redirectUri: 'http://localhost:8080/callback',
  );

  // Get authorization URL
  final authUrl = MicrosoftAuth.getAuthorizationUrl();
  print('Open this URL in your browser: $authUrl');

  // After user authorizes, exchange the code for tokens
  final authCode = 'authorization-code-from-callback';
  final result = await Dartcraft.authenticateWithMicrosoft(authCode);
  
  print('Authenticated as: ${result.username}');
}
```

### Ely.by Authentication

```dart
import 'package:dartcraft/dartcraft.dart';

void main() async {
  final launcher = Dartcraft('1.20.4', '/path/to/minecraft', useElyBy: true);

  // Basic authentication
  final result = await launcher.authenticateWithElyBy(
    username: 'your-username',
    password: 'your-password',
  );

  // Two-factor authentication (if enabled)
  try {
    final result = await launcher.authenticateWithElyBy(
      username: 'your-username', 
      password: 'your-password',
    );
  } on TwoFactorRequiredException {
    final result = await launcher.authenticateWithElyByTwoFactor(
      username: 'your-username',
      password: 'your-password',
      totpCode: '123456', // TOTP code from authenticator app
    );
  }
}
```

## Version Management

```dart
// Get all available versions
final versions = await Dartcraft.getAvailableVersions();
for (final version in versions) {
  print('${version.id} (${version.type.name}) - ${version.releaseTime}');
}

// Get only release versions
final releases = await Dartcraft.getReleaseVersions();
print('Latest release: ${releases.first.id}');
```

## Advanced Configuration

### Custom Java Runtime

```dart
final launcher = Dartcraft(
  '1.20.4',
  '/path/to/minecraft',
  javaPath: '/custom/java/bin/java', // Custom Java executable
);
```

### Launch Options

```dart
final process = await launcher.launch(
  username: 'PlayerName',
  uuid: 'player-uuid',
  accessToken: 'access-token',
  
  // JVM arguments for performance
  jvmArguments: ['-Xmx4G', '-Xms2G', '-XX:+UseG1GC'],
  
  // Game arguments
  gameArguments: ['--fullscreen'],
  
  // Custom window size
  windowWidth: 1920,
  windowHeight: 1080,
  
  // Hide output
  showOutput: false,
);
```

### Authlib-Injector Support

For Ely.by authentication with authlib-injector:

```dart
final launcher = Dartcraft(
  '1.20.4',
  '/path/to/minecraft',
  useElyBy: true,
  authlibInjectorPath: '/path/to/authlib-injector.jar',
);
```

## Error Handling

Dartcraft provides comprehensive error handling with specific exception types:

```dart
try {
  await launcher.install();
  final process = await launcher.launch(/* ... */);
} on InstallationException catch (e) {
  print('Installation failed: ${e.message}');
} on LaunchException catch (e) {
  print('Launch failed: ${e.message}');
} on AuthenticationException catch (e) {
  print('Authentication failed: ${e.message}');
} on DartcraftException catch (e) {
  print('General error: ${e.message}');
}
```

## API Reference

### Classes

- **`Dartcraft`**: Main launcher class
- **`MicrosoftAuth`**: Microsoft authentication helper
- **`ElyAuth`**: Ely.by authentication helper  
- **`MinecraftVersion`**: Represents a Minecraft version
- **`AuthenticationResult`**: Authentication result container

### Exceptions

- **`DartcraftException`**: Base exception class
- **`AuthenticationException`**: Authentication failures
- **`InstallationException`**: Installation failures
- **`LaunchException`**: Launch failures
- **`TwoFactorRequiredException`**: 2FA required for Ely.by

## Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| Windows  | ✅        | x64, ARM64 |
| macOS    | ✅        | Intel, Apple Silicon (M1/M2) |
| Linux    | ✅        | x64, ARM64 |

## Requirements

- Dart SDK 3.5.3 or higher
- Java 8 or higher (for running Minecraft)
- Internet connection (for downloads and authentication)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

If you encounter any issues or have questions:

1. Check the [API documentation](https://pub.dev/documentation/dartcraft/latest/)
2. Search [existing issues](https://github.com/yourusername/dartcraft/issues)
3. Create a [new issue](https://github.com/yourusername/dartcraft/issues/new) if needed

## Acknowledgments

- Minecraft is a trademark of Mojang Studios
- Microsoft authentication follows official OAuth2 flow
- Ely.by integration follows their official API documentation
