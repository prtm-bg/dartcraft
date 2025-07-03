import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Exception for Ely.by authentication errors
class ElyAuthException implements Exception {
  final String error;
  final String errorMessage;
  
  ElyAuthException(this.error, this.errorMessage);
  
  @override
  String toString() => 'ElyAuthException: $error - $errorMessage';
}

/// Configuration for Ely.by OAuth2 authentication
class ElyOAuthConfig {
  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final String scope;
  
  const ElyOAuthConfig({
    required this.clientId,
    required this.clientSecret,
    this.redirectUri = 'http://localhost:8080/callback',
    this.scope = 'account_info minecraft_server_session',
  });
}

/// OAuth2 access token response
class ElyOAuthToken {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final String scope;
  final DateTime expiresAt;
  
  ElyOAuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.scope,
  }) : expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
  
  factory ElyOAuthToken.fromJson(Map<String, dynamic> json) {
    return ElyOAuthToken(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      tokenType: json['token_type'],
      expiresIn: json['expires_in'],
      scope: json['scope'],
    );
  }
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Ely.by user information
class ElyUser {
  final String id;
  final String username;
  final String email;
  final String? lang;
  final String? profileLink;
  final String? preferredLanguage;
  final Map<String, dynamic>? properties;
  
  ElyUser({
    required this.id,
    required this.username,
    required this.email,
    this.lang,
    this.profileLink,
    this.preferredLanguage,
    this.properties,
  });
  
  factory ElyUser.fromJson(Map<String, dynamic> json) {
    return ElyUser(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      lang: json['lang'],
      profileLink: json['profileLink'],
      preferredLanguage: json['preferredLanguage'],
      properties: json['properties'],
    );
  }
}

/// Result of OAuth2 authentication process
class ElyAuthResult {
  final ElyOAuthToken token;
  final ElyUser user;
  final String minecraftAccessToken;
  final String minecraftUsername;
  final String minecraftUuid;
  
  ElyAuthResult({
    required this.token,
    required this.user,
    required this.minecraftAccessToken,
    required this.minecraftUsername,
    required this.minecraftUuid,
  });
}

/// Handles Ely.by authentication for Minecraft
class ElyAuth {
  static const String _authServerUrl = 'https://authserver.ely.by';
  static const String _authlibInjectorUrl = 'https://github.com/yushijinhun/authlib-injector/releases/latest/download/authlib-injector.jar';
  
  // OAuth2 endpoints
  static const String _oauthBaseUrl = 'https://account.ely.by';
  static const String _oauthAuthorizeUrl = '$_oauthBaseUrl/oauth2/v1/authorize';
  static const String _oauthTokenUrl = '$_oauthBaseUrl/api/oauth2/v1/token';
  static const String _oauthUserInfoUrl = '$_oauthBaseUrl/api/account/v1/info';
  static const String _minecraftSessionUrl = '$_oauthBaseUrl/api/minecraft/session/join';
  
  /// Authenticate using OAuth2 browser flow
  static Future<ElyAuthResult> authenticateWithOAuth(ElyOAuthConfig config) async {
    // Generate PKCE parameters for security
    final String codeVerifier = _generateCodeVerifier();
    final String codeChallenge = _generateCodeChallenge(codeVerifier);
    final String state = _generateState();
    
    // Start local HTTP server to receive callback
    final server = await _startCallbackServer(config.redirectUri);
    
    try {
      // Build authorization URL
      final authUrl = Uri.parse(_oauthAuthorizeUrl).replace(queryParameters: {
        'response_type': 'code',
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri,
        'scope': config.scope,
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      });
      
      // Open browser for user authentication
      if (!await _launchUrl(authUrl.toString())) {
        throw ElyAuthException('BrowserLaunchFailed', 'Failed to open browser for authentication');
      }
      
      // Wait for callback with authorization code
      final authCode = await _waitForCallback(server, state);
      
      // Exchange authorization code for access token
      final token = await _exchangeCodeForToken(config, authCode, codeVerifier);
      
      // Get user information
      final user = await _getUserInfo(token);
      
      // Get Minecraft session token
      final minecraftSession = await _getMinecraftSession(token);
      
      return ElyAuthResult(
        token: token,
        user: user,
        minecraftAccessToken: minecraftSession['accessToken'],
        minecraftUsername: minecraftSession['selectedProfile']['name'],
        minecraftUuid: minecraftSession['selectedProfile']['id'],
      );
    } finally {
      await server.close();
    }
  }
  
  /// Refresh OAuth2 token
  static Future<ElyOAuthToken> refreshOAuthToken(ElyOAuthConfig config, String refreshToken) async {
    final response = await http.post(
      Uri.parse(_oauthTokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
      },
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return ElyOAuthToken.fromJson(data);
    } else {
      final errorData = json.decode(response.body);
      throw ElyAuthException(
        errorData['error'] ?? 'RefreshTokenFailed',
        errorData['error_description'] ?? 'Failed to refresh token',
      );
    }
  }
  
  /// Get user information using OAuth2 token
  static Future<ElyUser> getUserInfo(ElyOAuthToken token) async {
    return _getUserInfo(token);
  }
  
  /// Get user information using OAuth2 token (internal)
  static Future<ElyUser> _getUserInfo(ElyOAuthToken token) async {
    final response = await http.get(
      Uri.parse(_oauthUserInfoUrl),
      headers: {'Authorization': 'Bearer ${token.accessToken}'},
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return ElyUser.fromJson(data);
    } else {
      final errorData = json.decode(response.body);
      throw ElyAuthException(
        errorData['error'] ?? 'UserInfoFailed',
        errorData['message'] ?? 'Failed to get user information',
      );
    }
  }
  
  /// Get Minecraft session token using OAuth2 token
  static Future<Map<String, dynamic>> _getMinecraftSession(ElyOAuthToken token) async {
    final response = await http.post(
      Uri.parse(_minecraftSessionUrl),
      headers: {
        'Authorization': 'Bearer ${token.accessToken}',
        'Content-Type': 'application/json',
      },
      body: json.encode({}),
    );
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      final errorData = json.decode(response.body);
      throw ElyAuthException(
        errorData['error'] ?? 'MinecraftSessionFailed',
        errorData['message'] ?? 'Failed to get Minecraft session',
      );
    }
  }
  
  /// Start local HTTP server to receive OAuth callback
  static Future<HttpServer> _startCallbackServer(String redirectUri) async {
    final uri = Uri.parse(redirectUri);
    final handler = shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_handleCallback);
    
    return await shelf_io.serve(handler, uri.host, uri.port);
  }
  
  /// Handle OAuth callback request
  static shelf.Response _handleCallback(shelf.Request request) {
    final queryParams = request.requestedUri.queryParameters;
    
    if (queryParams.containsKey('code')) {
      // Success - store the code for retrieval
      _authorizationCode = queryParams['code'];
      _authorizationState = queryParams['state'];
      
      return shelf.Response.ok('''
        <!DOCTYPE html>
        <html>
        <head><title>Authentication Successful</title></head>
        <body>
          <h1>Authentication Successful!</h1>
          <p>You can now close this window and return to the application.</p>
          <script>window.close();</script>
        </body>
        </html>
      ''', headers: {'Content-Type': 'text/html'});
    } else if (queryParams.containsKey('error')) {
      // Error case
      _authorizationError = queryParams['error'];
      _authorizationErrorDescription = queryParams['error_description'];
      
      return shelf.Response.ok('''
        <!DOCTYPE html>
        <html>
        <head><title>Authentication Error</title></head>
        <body>
          <h1>Authentication Error</h1>
          <p>Error: ${queryParams['error']}</p>
          <p>Description: ${queryParams['error_description'] ?? 'Unknown error'}</p>
          <p>You can close this window and try again.</p>
        </body>
        </html>
      ''', headers: {'Content-Type': 'text/html'});
    } else {
      return shelf.Response(400, body: 'Invalid callback request');
    }
  }
  
  // Static variables to store callback results
  static String? _authorizationCode;
  static String? _authorizationState;
  static String? _authorizationError;
  static String? _authorizationErrorDescription;
  
  /// Wait for OAuth callback with authorization code
  static Future<String> _waitForCallback(HttpServer server, String expectedState) async {
    // Reset callback variables
    _authorizationCode = null;
    _authorizationState = null;
    _authorizationError = null;
    _authorizationErrorDescription = null;
    
    // Wait for callback (with timeout)
    final timeout = Duration(minutes: 5);
    final startTime = DateTime.now();
    
    while (DateTime.now().difference(startTime) < timeout) {
      await Future.delayed(Duration(milliseconds: 100));
      
      if (_authorizationError != null) {
        throw ElyAuthException(_authorizationError!, _authorizationErrorDescription ?? 'Authentication failed');
      }
      
      if (_authorizationCode != null) {
        if (_authorizationState != expectedState) {
          throw ElyAuthException('StateMismatch', 'OAuth state parameter mismatch');
        }
        return _authorizationCode!;
      }
    }
    
    throw ElyAuthException('AuthTimeout', 'Authentication timed out');
  }
  
  /// Exchange authorization code for access token
  static Future<ElyOAuthToken> _exchangeCodeForToken(
    ElyOAuthConfig config, 
    String authCode, 
    String codeVerifier,
  ) async {
    final response = await http.post(
      Uri.parse(_oauthTokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': authCode,
        'redirect_uri': config.redirectUri,
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'code_verifier': codeVerifier,
      },
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return ElyOAuthToken.fromJson(data);
    } else {
      final errorData = json.decode(response.body);
      throw ElyAuthException(
        errorData['error'] ?? 'TokenExchangeFailed',
        errorData['error_description'] ?? 'Failed to exchange authorization code for token',
      );
    }
  }
  
  /// Generate PKCE code verifier
  static String _generateCodeVerifier() {
    const String chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final Random random = Random.secure();
    return List.generate(128, (index) => chars[random.nextInt(chars.length)]).join();
  }
  
  /// Generate PKCE code challenge
  static String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
  
  /// Generate random state parameter
  static String _generateState() {
    final Random random = Random.secure();
    return base64Url.encode(List.generate(32, (index) => random.nextInt(256)));
  }
  
  /// Launch URL in default browser (cross-platform)
  static Future<bool> _launchUrl(String url) async {
    try {
      ProcessResult result;
      
      if (Platform.isWindows) {
        result = await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        result = await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        result = await Process.run('xdg-open', [url]);
      } else {
        return false;
      }
      
      return result.exitCode == 0;
    } catch (e) {
      print('Failed to launch URL: $e');
      return false;
    }
  }
  
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
