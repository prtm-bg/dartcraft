/// Base exception class for all Dartcraft-related exceptions
class DartcraftException implements Exception {
  final String message;
  final dynamic cause;

  const DartcraftException(this.message, [this.cause]);

  @override
  String toString() => 'DartcraftException: $message';
}

/// Exception thrown when authentication fails
class AuthenticationException extends DartcraftException {
  const AuthenticationException(String message, [dynamic cause]) : super(message, cause);

  @override
  String toString() => 'AuthenticationException: $message';
}

/// Exception thrown when Minecraft installation fails
class InstallationException extends DartcraftException {
  const InstallationException(String message, [dynamic cause]) : super(message, cause);

  @override
  String toString() => 'InstallationException: $message';
}

/// Exception thrown when Minecraft launch fails
class LaunchException extends DartcraftException {
  const LaunchException(String message, [dynamic cause]) : super(message, cause);

  @override
  String toString() => 'LaunchException: $message';
}

/// Exception thrown when version management fails
class VersionException extends DartcraftException {
  const VersionException(String message, [dynamic cause]) : super(message, cause);

  @override
  String toString() => 'VersionException: $message';
}

/// Exception thrown when profile operations fail
class ProfileException extends DartcraftException {
  const ProfileException(String message, [dynamic cause]) : super(message, cause);

  @override
  String toString() => 'ProfileException: $message';
}

/// Exception thrown when network operations fail
class NetworkException extends DartcraftException {
  const NetworkException(String message, [dynamic cause]) : super(message, cause);

  @override
  String toString() => 'NetworkException: $message';
}

/// Exception thrown when file operations fail
class FileException extends DartcraftException {
  const FileException(String message, [dynamic cause]) : super(message, cause);

  @override
  String toString() => 'FileException: $message';
}
