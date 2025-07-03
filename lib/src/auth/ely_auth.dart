import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:io';

/// Exception for Ely.by authentication errors
class ElyAuthException implements Exception {
  final String error;
  final String errorMessage;
  
  ElyAuthException(this.error, this.errorMessage);
  
  @override
  String toString() => 'ElyAuthException: $error - $errorMessage';
}

/// Handles Ely.by authentication for Minecraft
class ElyAuth {
  static const String _authServerUrl = 'https://authserver.ely.by';
  static const String _authlibInjectorUrl = 'https://github.com/yushijinhun/authlib-injector/releases/latest/download/authlib-injector.jar';
  
  /// Authenticate with Ely.by using username/email and password
  static Future<Map<String, dynamic>> authenticate(
    String username, 
    String password, {
    String? clientToken,
    bool requestUser = false,
  }) async {
    clientToken ??= _generateClientToken();
    
    Map<String, dynamic> body = {
      'username': username,
      'password': password,
      'clientToken': clientToken,
      'requestUser': requestUser,
    };
    
    var response = await http.post(
      Uri.parse('$_authServerUrl/auth/authenticate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 401) {
      var errorData = json.decode(response.body);
      
      // Check for two-factor authentication
      if (errorData['error'] == 'ForbiddenOperationException' && 
          errorData['errorMessage'] == 'Account protected with two factor auth.') {
        throw ElyAuthException('TwoFactorRequired', 'Please provide a two-factor authentication token');
      }
      
      throw ElyAuthException(
        errorData['error'] ?? 'Unknown error',
        errorData['errorMessage'] ?? 'Authentication failed',
      );
    } else {
      var errorData = json.decode(response.body);
      throw ElyAuthException(
        errorData['error'] ?? 'Unknown error',
        errorData['errorMessage'] ?? 'Authentication failed with status code ${response.statusCode}',
      );
    }
  }
  
  /// Authenticate with Ely.by using username/email, password and two-factor token
  static Future<Map<String, dynamic>> authenticateWithTwoFactor(
    String username, 
    String password, 
    String twoFactorToken, {
    String? clientToken,
    bool requestUser = false,
  }) async {
    // For two-factor auth, the password should be in format "password:token"
    String passwordWithToken = '$password:$twoFactorToken';
    
    return authenticate(
      username, 
      passwordWithToken,
      clientToken: clientToken,
      requestUser: requestUser,
    );
  }
  
  /// Refresh an existing access token
  static Future<Map<String, dynamic>> refresh(
    String accessToken, 
    String clientToken, {
    bool requestUser = false,
  }) async {
    Map<String, dynamic> body = {
      'accessToken': accessToken,
      'clientToken': clientToken,
      'requestUser': requestUser,
    };
    
    var response = await http.post(
      Uri.parse('$_authServerUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      var errorData = json.decode(response.body);
      throw ElyAuthException(
        errorData['error'] ?? 'Unknown error',
        errorData['errorMessage'] ?? 'Token refresh failed',
      );
    }
  }
  
  /// Validate if an access token is valid
  static Future<bool> validate(String accessToken) async {
    Map<String, dynamic> body = {
      'accessToken': accessToken,
    };
    
    var response = await http.post(
      Uri.parse('$_authServerUrl/auth/validate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    
    if (response.statusCode == 200) {
      return true;
    } else {
      var errorData = json.decode(response.body);
      throw ElyAuthException(
        errorData['error'] ?? 'Unknown error',
        errorData['errorMessage'] ?? 'Token validation failed',
      );
    }
  }
  
  /// Invalidate all access tokens for a user
  static Future<void> signout(String username, String password) async {
    Map<String, dynamic> body = {
      'username': username,
      'password': password,
    };
    
    var response = await http.post(
      Uri.parse('$_authServerUrl/auth/signout'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    
    if (response.statusCode != 200) {
      var errorData = json.decode(response.body);
      throw ElyAuthException(
        errorData['error'] ?? 'Unknown error',
        errorData['errorMessage'] ?? 'Signout failed',
      );
    }
  }
  
  /// Invalidate a specific access token
  static Future<void> invalidate(String accessToken, String clientToken) async {
    Map<String, dynamic> body = {
      'accessToken': accessToken,
      'clientToken': clientToken,
    };
    
    var response = await http.post(
      Uri.parse('$_authServerUrl/auth/invalidate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    
    if (response.statusCode != 200) {
      var errorData = json.decode(response.body);
      throw ElyAuthException(
        errorData['error'] ?? 'Unknown error',
        errorData['errorMessage'] ?? 'Token invalidation failed',
      );
    }
  }
  
  /// Download the authlib-injector JAR file to the specified directory
  static Future<String> downloadAuthlibInjector(String destinationDir) async {
    try {
      final Directory directory = Directory(destinationDir);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      
      final String filePath = path.join(destinationDir, 'authlib-injector.jar');
      
      // Skip download if file already exists
      if (File(filePath).existsSync()) {
        return filePath;
      }
      
      var response = await http.get(Uri.parse(_authlibInjectorUrl));
      
      if (response.statusCode == 200) {
        await File(filePath).writeAsBytes(response.bodyBytes);
        return filePath;
      } else {
        throw ElyAuthException(
          'DownloadFailed', 
          'Failed to download authlib-injector: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw ElyAuthException('DownloadFailed', 'Failed to download authlib-injector: $e');
    }
  }
  
  /// Generate JVM arguments to use Ely.by authentication with authlib-injector
  static List<String> getAuthlibJvmArgs(String authlibInjectorPath) {
    return ['-javaagent:$authlibInjectorPath=ely.by'];
  }
  
  /// Generate a random client token
  static String _generateClientToken() {
    var random = DateTime.now().millisecondsSinceEpoch ^ 
                 DateTime.now().microsecondsSinceEpoch;
    return random.toRadixString(16);
  }
}
