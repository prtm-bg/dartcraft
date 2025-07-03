import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Exception thrown during Ely.by authentication operations
/// 
/// Contains specific error codes and messages to help diagnose authentication issues.
/// 
/// Common error codes:
/// - `invalid_client` - Invalid client ID or secret
/// - `invalid_grant` - Invalid authorization code or refresh token
/// - `access_denied` - User denied access during OAuth flow
/// - `BrowserLaunchFailed` - Cannot open browser for authentication
/// - `AuthTimeout` - User didn't complete authentication within timeout
/// - `StateMismatch` - OAuth state parameter validation failed
/// - `TwoFactorRequired` - Account requires two-factor authentication
/// 
/// Example:
/// ```dart
/// try {
///   final result = await ElyAuth.authenticateWithOAuth(config);
/// } catch (e) {
///   if (e is ElyAuthException) {
///     switch (e.error) {
///       case 'access_denied':
///         print('User cancelled authentication');
///         break;
///       case 'invalid_client':
///         print('Check your client ID and secret');
///         break;
///       default:
///         print('Authentication error: ${e.errorMessage}');
///     }
///   }
/// }
/// ```
class ElyAuthException implements Exception {
  /// Specific error code identifying the type of authentication failure
  final String error;
  
  /// Human-readable error message describing the failure
  final String errorMessage;
  
  /// Creates an authentication exception with error code and message
  ElyAuthException(this.error, this.errorMessage);
  
  @override
  String toString() => 'ElyAuthException: $error - $errorMessage';
}

/// Configuration for Ely.by OAuth2 authentication
/// 
/// Contains the application credentials and settings required for OAuth2 flow.
/// Register your application at https://account.ely.by/dev/applications/new
/// to get the client ID and secret.
/// 
/// Example:
/// ```dart
/// const config = ElyOAuthConfig(
///   clientId: 'my-launcher-app',
///   clientSecret: 'abc123...',
///   redirectUri: 'http://localhost:8080/callback',
///   scope: 'account_info minecraft_server_session',
/// );
/// ```
class ElyOAuthConfig {
  /// OAuth2 client ID from your registered Ely.by application
  final String clientId;
  
  /// OAuth2 client secret from your registered Ely.by application
  final String clientSecret;
  
  /// Redirect URI where the OAuth callback will be received
  /// Must match the URI registered in your Ely.by application
  final String redirectUri;
  
  /// OAuth2 scopes to request access for
  /// - `account_info`: Access to user profile information
  /// - `minecraft_server_session`: Access to Minecraft session tokens
  final String scope;
  
  /// Creates OAuth2 configuration for Ely.by authentication
  /// 
  /// [clientId] and [clientSecret] are required and obtained from your
  /// registered application at https://account.ely.by/dev/applications/new
  /// 
  /// [redirectUri] defaults to localhost:8080 but can be customized
  /// [scope] defaults to account info and Minecraft session access
  const ElyOAuthConfig({
    required this.clientId,
    required this.clientSecret,
    this.redirectUri = 'http://localhost:8080/callback',
    this.scope = 'account_info minecraft_server_session',
  });
}

/// OAuth2 access token and metadata
/// 
/// Contains the access token, refresh token, and expiration information
/// returned from a successful OAuth2 authentication or token refresh.
/// 
/// Example:
/// ```dart
/// final token = ElyOAuthToken.fromJson(response);
/// 
/// if (token.isExpired) {
///   print('Token expired, need to refresh');
/// } else {
///   print('Token valid for ${token.expiresAt.difference(DateTime.now()).inMinutes} minutes');
/// }
/// ```
class ElyOAuthToken {
  /// The access token used for authenticated API requests
  final String accessToken;
  
  /// The refresh token used to obtain new access tokens
  final String refreshToken;
  
  /// Token type, typically "Bearer"
  final String tokenType;
  
  /// Token lifetime in seconds from when it was issued
  final int expiresIn;
  
  /// OAuth2 scopes granted to this token
  final String scope;
  
  /// Calculated expiration timestamp
  final DateTime expiresAt;
  
  /// Creates an OAuth2 token with the specified values
  ElyOAuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.scope,
  }) : expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
  
  /// Creates an OAuth2 token from a JSON response
  factory ElyOAuthToken.fromJson(Map<String, dynamic> json) {
    return ElyOAuthToken(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      tokenType: json['token_type'],
      expiresIn: json['expires_in'],
      scope: json['scope'],
    );
  }
  
  /// Whether this token has expired and needs to be refreshed
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Ely.by user account information
/// 
/// Contains user profile data retrieved from the Ely.by API after
/// successful OAuth2 authentication.
/// 
/// Example:
/// ```dart
/// final user = await ElyAuth.getUserInfo(token);
/// print('Welcome, ${user.username}!');
/// print('Email: ${user.email}');
/// print('Profile: ${user.profileLink}');
/// ```
class ElyUser {
  /// Unique user identifier on Ely.by
  final String id;
  
  /// User's display name (username)
  final String username;
  
  /// User's email address
  final String email;
  
  /// User's preferred language code (optional)
  final String? lang;
  
  /// URL to user's Ely.by profile page (optional)
  final String? profileLink;
  
  /// User's preferred language for interface (optional)
  final String? preferredLanguage;
  
  /// Additional user properties and metadata (optional)
  final Map<String, dynamic>? properties;
  
  /// Creates an Ely.by user object with the specified information
  ElyUser({
    required this.id,
    required this.username,
    required this.email,
    this.lang,
    this.profileLink,
    this.preferredLanguage,
    this.properties,
  });
  
  /// Creates an Ely.by user from JSON API response
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

/// Complete result of OAuth2 authentication process
/// 
/// Contains all information needed to launch Minecraft with Ely.by authentication,
/// including OAuth tokens, user information, and Minecraft session details.
/// 
/// Example:
/// ```dart
/// final result = await ElyAuth.authenticateWithOAuth(config);
/// 
/// // Access user information
/// print('Authenticated as: ${result.user.username}');
/// print('Email: ${result.user.email}');
/// 
/// // Launch Minecraft with authentication
/// await launcher.launch(
///   username: result.minecraftUsername,
///   uuid: result.minecraftUuid,
///   accessToken: result.minecraftAccessToken,
/// );
/// 
/// // Token management
/// if (result.token.isExpired) {
///   final newToken = await ElyAuth.refreshOAuthToken(config, result.token.refreshToken);
/// }
/// ```
class ElyAuthResult {
  /// OAuth2 token with access and refresh tokens
  final ElyOAuthToken token;
  
  /// User account information from Ely.by
  final ElyUser user;
  
  /// Minecraft access token for game authentication
  final String minecraftAccessToken;
  
  /// Minecraft username for the authenticated user
  final String minecraftUsername;
  
  /// Minecraft UUID for the authenticated user
  final String minecraftUuid;
  
  /// Creates a complete authentication result
  ElyAuthResult({
    required this.token,
    required this.user,
    required this.minecraftAccessToken,
    required this.minecraftUsername,
    required this.minecraftUuid,
  });
}

/// Comprehensive Ely.by authentication handler
/// 
/// Provides multiple authentication methods for Ely.by accounts:
/// - OAuth2 browser-based flow (recommended)
/// - Username/password authentication
/// - Two-factor authentication support
/// - Token management and refresh
/// - Authlib-injector integration
/// 
/// Ely.by is a popular alternative authentication service for Minecraft
/// that allows custom skins and usernames without requiring a Microsoft account.
class ElyAuth {
  static const String _authServerUrl = 'https://authserver.ely.by';
  static const String _authlibInjectorUrl = 'https://github.com/yushijinhun/authlib-injector/releases/latest/download/authlib-injector.jar';
  
  // OAuth2 endpoints
  static const String _oauthBaseUrl = 'https://account.ely.by';
  static const String _oauthAuthorizeUrl = '$_oauthBaseUrl/oauth2/v1/authorize';
  static const String _oauthTokenUrl = '$_oauthBaseUrl/api/oauth2/v1/token';
  static const String _oauthUserInfoUrl = '$_oauthBaseUrl/api/account/v1/info';
  static const String _minecraftSessionUrl = '$_oauthBaseUrl/api/minecraft/session/join';
  
  /// Authenticates a user with Ely.by using OAuth2 browser flow (recommended)
  /// 
  /// Opens the user's default browser for secure authentication and handles
  /// the OAuth2 callback automatically. Uses PKCE (Proof Key for Code Exchange)
  /// for enhanced security.
  /// 
  /// This is the recommended authentication method as it:
  /// - Does not require storing user credentials
  /// - Supports two-factor authentication automatically
  /// - Uses modern OAuth2 security practices
  /// - Provides refresh tokens for long-term authentication
  /// 
  /// Parameters:
  /// - [config] - OAuth2 configuration with your registered application details
  /// 
  /// Example:
  /// ```dart
  /// // First, register your app at https://account.ely.by/dev/applications/new
  /// const config = ElyOAuthConfig(
  ///   clientId: 'your-client-id',
  ///   clientSecret: 'your-client-secret',
  ///   redirectUri: 'http://localhost:8080/callback',
  ///   scope: 'account_info minecraft_server_session',
  /// );
  /// 
  /// try {
  ///   print('Opening browser for authentication...');
  ///   final result = await ElyAuth.authenticateWithOAuth(config);
  ///   
  ///   print('✅ Authenticated as: ${result.user.username}');
  ///   print('Minecraft Username: ${result.minecraftUsername}');
  ///   
  ///   // Use the result for Minecraft launcher
  ///   await launcher.launch(
  ///     username: result.minecraftUsername,
  ///     uuid: result.minecraftUuid,
  ///     accessToken: result.minecraftAccessToken,
  ///   );
  /// } catch (e) {
  ///   print('Authentication failed: $e');
  /// }
  /// ```
  /// 
  /// Returns [ElyAuthResult] containing user information, OAuth tokens,
  /// and Minecraft session details.
  /// 
  /// Throws [ElyAuthException] with specific error codes:
  /// - `BrowserLaunchFailed` - Cannot open browser
  /// - `AuthTimeout` - User didn't complete auth within 5 minutes
  /// - `StateMismatch` - Security validation failed
  /// - `access_denied` - User denied access
  /// - Network-related errors for connection issues
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
  
  /// Refreshes an expired OAuth2 access token using a refresh token
  /// 
  /// Use this to obtain a new access token when the current one expires,
  /// without requiring the user to re-authenticate in the browser.
  /// 
  /// Parameters:
  /// - [config] - OAuth2 configuration with your application credentials
  /// - [refreshToken] - The refresh token from a previous authentication
  /// 
  /// Example:
  /// ```dart
  /// // Check if token is expired and refresh if needed
  /// if (savedToken.isExpired) {
  ///   try {
  ///     final newToken = await ElyAuth.refreshOAuthToken(config, savedToken.refreshToken);
  ///     print('✅ Token refreshed successfully');
  ///     
  ///     // Save the new token for future use
  ///     await saveTokenToStorage(newToken);
  ///     
  ///     return newToken;
  ///   } catch (e) {
  ///     print('❌ Token refresh failed, need to re-authenticate');
  ///     // Fall back to full OAuth flow
  ///     return await ElyAuth.authenticateWithOAuth(config);
  ///   }
  /// }
  /// ```
  /// 
  /// Returns a new [ElyOAuthToken] with updated access token and expiration.
  /// 
  /// Throws [ElyAuthException] if the refresh token is invalid or expired.
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
