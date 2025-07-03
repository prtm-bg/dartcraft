/// Exception specific to Dartcraft operations
class DartcraftException implements Exception {
  final String message;
  final String code;
  final dynamic originalError;
  
  DartcraftException(this.message, {this.code = 'unknown', this.originalError});
  
  @override
  String toString() => 'DartcraftException: $message (code: $code)';
}

/// Specific exception types
class InstallationException extends DartcraftException {
  InstallationException(String message, {dynamic originalError}) 
      : super(message, code: 'installation_error', originalError: originalError);
}

class LaunchException extends DartcraftException {
  LaunchException(String message, {dynamic originalError}) 
      : super(message, code: 'launch_error', originalError: originalError);
}

class AuthenticationException extends DartcraftException {
  AuthenticationException(String message, {dynamic originalError}) 
      : super(message, code: 'auth_error', originalError: originalError);
}

class NativeLibraryException extends DartcraftException {
  NativeLibraryException(String message, {dynamic originalError}) 
      : super(message, code: 'native_library_error', originalError: originalError);
}

class VersionException extends DartcraftException {
  VersionException(String message, {dynamic originalError}) 
      : super(message, code: 'version_error', originalError: originalError);
}

class AssetException extends DartcraftException {
  AssetException(String message, {dynamic originalError}) 
      : super(message, code: 'asset_error', originalError: originalError);
}
