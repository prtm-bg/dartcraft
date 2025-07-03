# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-07-03

### Added
- Initial release of Dartcraft
- Complete Minecraft launcher functionality
- Support for vanilla Minecraft versions
- Cross-platform native library extraction
- Microsoft account authentication
- Ely.by authentication with 2FA support
- Authlib-injector integration for Ely.by
- Automatic Java runtime detection and installation
- Custom JVM arguments support
- Comprehensive error handling
- Full cross-platform support (Windows, macOS, Linux)
- Apple Silicon (M1/M2) compatibility on macOS

### Features
- **Game Installation**: Automatic download and installation of any Minecraft version
- **Version Management**: Support for release, snapshot, and modded versions
- **Authentication**: Multiple authentication providers with secure token management
- **Native Libraries**: Platform-specific library extraction and management
- **Modding Support**: Built-in support for Forge, Fabric, and other mod loaders
- **Flexible Configuration**: Customizable launch parameters and Java runtime options

### Technical Details
- Built with modern Dart features and async/await patterns
- Comprehensive exception handling with custom exception types
- SHA1 verification for all downloaded files
- Automatic version inheritance for modded versions
- Memory-efficient file streaming for large downloads
- Clean separation of concerns with modular architecture
