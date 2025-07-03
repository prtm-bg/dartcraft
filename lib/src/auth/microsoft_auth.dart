import 'dart:convert';
import 'package:http/http.dart' as http;
import '../exceptions/exceptions.dart';
import '../core/launcher.dart' show AuthenticationResult;

/// Microsoft authentication handler for Dartcraft
class MicrosoftAuth {
  // Microsoft OAuth2 endpoints
  static const String _msAuthUrl = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize';
  static const String _msTokenUrl = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';
  static const String _xblAuthUrl = 'https://user.auth.xboxlive.com/user/authenticate';
  static const String _xstsAuthUrl = 'https://xsts.auth.xboxlive.com/xsts/authorize';
  static const String _mcLoginUrl = 'https://api.minecraftservices.com/authentication/login_with_xbox';
  static const String _mcProfileUrl = 'https://api.minecraftservices.com/minecraft/profile';

  // Default OAuth2 configuration (you should use your own)
  static const String _defaultClientId = '00000000-0000-0000-0000-000000000000';
  static const String _defaultRedirectUri = 'http://localhost:8080/callback';

  // Application-specific configuration
  static String? _clientId;
  static String? _redirectUri;

  /// Configure Microsoft authentication with your OAuth2 credentials
  static void configure({required String clientId, required String redirectUri}) {
    _clientId = clientId;
    _redirectUri = redirectUri;
  }

  /// Get the Microsoft authorization URL for OAuth2 flow
  static String getAuthorizationUrl() {
    const scope = 'XboxLive.signin offline_access';
    final clientId = _clientId ?? _defaultClientId;
    final redirectUri = _redirectUri ?? _defaultRedirectUri;
    
    return '$_msAuthUrl?client_id=$clientId&response_type=code&redirect_uri=$redirectUri&scope=$scope&response_mode=query';
  }

  /// Exchange authorization code for Microsoft tokens
  static Future<Map<String, dynamic>> getTokensFromCode(String authCode) async {
    final clientId = _clientId ?? _defaultClientId;
    final redirectUri = _redirectUri ?? _defaultRedirectUri;
    
    final response = await http.post(
      Uri.parse(_msTokenUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'client_id': clientId,
        'code': authCode,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode != 200) {
      throw AuthenticationException('Failed to exchange authorization code: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Authenticate with Xbox Live using Microsoft access token
  static Future<Map<String, dynamic>> authenticateWithXboxLive(String accessToken) async {
    final requestBody = {
      'Properties': {
        'AuthMethod': 'RPS',
        'SiteName': 'user.auth.xboxlive.com',
        'RpsTicket': 'd=$accessToken',
      },
      'RelyingParty': 'http://auth.xboxlive.com',
      'TokenType': 'JWT',
    };

    final response = await http.post(
      Uri.parse(_xblAuthUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode != 200) {
      throw AuthenticationException('Xbox Live authentication failed: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Get XSTS token using Xbox Live token
  static Future<Map<String, dynamic>> getXstsToken(String xblToken) async {
    final requestBody = {
      'Properties': {
        'SandboxId': 'RETAIL',
        'UserTokens': [xblToken],
      },
      'RelyingParty': 'rp://api.minecraftservices.com/',
      'TokenType': 'JWT',
    };

    final response = await http.post(
      Uri.parse(_xstsAuthUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode != 200) {
      throw AuthenticationException('XSTS authentication failed: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Authenticate with Minecraft using XSTS token
  static Future<Map<String, dynamic>> authenticateWithMinecraft(
    String xstsToken,
    String userHash,
  ) async {
    final requestBody = {
      'identityToken': 'XBL3.0 x=$userHash;$xstsToken',
    };

    final response = await http.post(
      Uri.parse(_mcLoginUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode != 200) {
      throw AuthenticationException('Minecraft authentication failed: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Get Minecraft profile information
  static Future<Map<String, dynamic>> getMinecraftProfile(String accessToken) async {
    final response = await http.get(
      Uri.parse(_mcProfileUrl),
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (response.statusCode != 200) {
      throw AuthenticationException('Failed to get Minecraft profile: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Complete the full Microsoft authentication flow
  static Future<Map<String, dynamic>> completeAuthFlow(String authCode) async {
    try {
      // Step 1: Exchange authorization code for Microsoft tokens
      final msTokens = await getTokensFromCode(authCode);
      final msAccessToken = msTokens['access_token'] as String;
      
      // Step 2: Authenticate with Xbox Live
      final xblResponse = await authenticateWithXboxLive(msAccessToken);
      final xblToken = xblResponse['Token'] as String;
      final userHash = (xblResponse['DisplayClaims']['xui'] as List).first['uhs'] as String;
      
      // Step 3: Get XSTS token
      final xstsResponse = await getXstsToken(xblToken);
      final xstsToken = xstsResponse['Token'] as String;
      
      // Step 4: Authenticate with Minecraft
      final mcResponse = await authenticateWithMinecraft(xstsToken, userHash);
      final mcAccessToken = mcResponse['access_token'] as String;
      
      // Step 5: Get Minecraft profile
      final profile = await getMinecraftProfile(mcAccessToken);
      
      return {
        'access_token': mcAccessToken,
        'refresh_token': msTokens['refresh_token'],
        'profile': profile,
      };
    } catch (e) {
      throw AuthenticationException('Authentication flow failed: $e');
    }
  }

  /// Refresh Microsoft access token using refresh token
  static Future<Map<String, dynamic>> refreshMicrosoftToken(String refreshToken) async {
    final clientId = _clientId ?? _defaultClientId;
    
    final response = await http.post(
      Uri.parse(_msTokenUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'client_id': clientId,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode != 200) {
      throw AuthenticationException('Failed to refresh token: ${response.body}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Complete authentication flow from authorization code to AuthenticationResult
  static Future<AuthenticationResult> authenticate(String authCode) async {
    try {
      final result = await completeAuthFlow(authCode);
      final profile = result['profile'] as Map<String, dynamic>;
      
      return AuthenticationResult(
        username: profile['name'] as String,
        uuid: profile['id'] as String,
        accessToken: result['access_token'] as String,
        refreshToken: result['refresh_token'] as String?,
      );
    } catch (e) {
      throw AuthenticationException('Microsoft authentication failed: $e');
    }
  }
}
