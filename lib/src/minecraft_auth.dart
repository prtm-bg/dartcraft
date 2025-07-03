import 'dart:convert';
import 'package:http/http.dart' as http;

/// Class that handles Microsoft account authentication for Minecraft
class MinecraftAuth {
  // Microsoft OAuth settings
  static const String clientId = 'YOUR_CLIENT_ID'; // Replace with your app's client ID
  static const String redirectUri = 'YOUR_REDIRECT_URI'; // Replace with your app's redirect URI
  
  // Authentication URLs
  static const String msAuthUrl = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize';
  static const String msTokenUrl = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';
  static const String xblAuthUrl = 'https://user.auth.xboxlive.com/user/authenticate';
  static const String xstsAuthUrl = 'https://xsts.auth.xboxlive.com/xsts/authorize';
  static const String mcLoginUrl = 'https://api.minecraftservices.com/authentication/login_with_xbox';
  static const String mcProfileUrl = 'https://api.minecraftservices.com/minecraft/profile';
  
  /// Get the Microsoft OAuth authorization URL
  static String getAuthorizationUrl() {
    const String scope = 'XboxLive.signin offline_access';
    return '$msAuthUrl?client_id=$clientId&response_type=code&redirect_uri=$redirectUri&scope=$scope&response_mode=query';
  }
  
  /// Exchange authorization code for tokens
  static Future<Map<String, dynamic>> getTokensFromCode(String authCode) async {
    Map<String, String> body = {
      'client_id': clientId,
      'code': authCode,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
      'scope': 'XboxLive.signin offline_access',
    };
    
    var response = await http.post(
      Uri.parse(msTokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to get tokens: ${response.body}');
    }
    
    return json.decode(response.body);
  }
  
  /// Authenticate with Xbox Live using Microsoft access token
  static Future<Map<String, dynamic>> authenticateWithXboxLive(String accessToken) async {
    Map<String, dynamic> body = {
      'Properties': {
        'AuthMethod': 'RPS',
        'SiteName': 'user.auth.xboxlive.com',
        'RpsTicket': 'd=$accessToken',
      },
      'RelyingParty': 'http://auth.xboxlive.com',
      'TokenType': 'JWT',
    };
    
    var response = await http.post(
      Uri.parse(xblAuthUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(body),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to authenticate with Xbox Live: ${response.body}');
    }
    
    return json.decode(response.body);
  }
  
  /// Get XSTS token using Xbox Live token
  static Future<Map<String, dynamic>> getXstsToken(String xblToken) async {
    Map<String, dynamic> body = {
      'Properties': {
        'SandboxId': 'RETAIL',
        'UserTokens': [xblToken],
      },
      'RelyingParty': 'rp://api.minecraftservices.com/',
      'TokenType': 'JWT',
    };
    
    var response = await http.post(
      Uri.parse(xstsAuthUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(body),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to get XSTS token: ${response.body}');
    }
    
    return json.decode(response.body);
  }
  
  /// Authenticate with Minecraft services using Xbox tokens
  static Future<Map<String, dynamic>> authenticateWithMinecraft(String userHash, String xstsToken) async {
    Map<String, dynamic> body = {
      'identityToken': 'XBL3.0 x=$userHash;$xstsToken',
    };
    
    var response = await http.post(
      Uri.parse(mcLoginUrl),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(body),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to authenticate with Minecraft: ${response.body}');
    }
    
    return json.decode(response.body);
  }
  
  /// Get Minecraft profile information
  static Future<Map<String, dynamic>> getMinecraftProfile(String accessToken) async {
    var response = await http.get(
      Uri.parse(mcProfileUrl),
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to get Minecraft profile: ${response.body}');
    }
    
    return json.decode(response.body);
  }
  
  /// Complete authentication flow (must be implemented by app with UI flow)
  static Future<Map<String, dynamic>> completeAuthFlow(String authCode) async {
    try {
      // 1. Get Microsoft tokens from auth code
      var msTokens = await getTokensFromCode(authCode);
      String msAccessToken = msTokens['access_token'];
      
      // 2. Authenticate with Xbox Live
      var xblResponse = await authenticateWithXboxLive(msAccessToken);
      String xblToken = xblResponse['Token'];
      String userHash = xblResponse['DisplayClaims']['xui'][0]['uhs'];
      
      // 3. Get XSTS token
      var xstsResponse = await getXstsToken(xblToken);
      String xstsToken = xstsResponse['Token'];
      
      // 4. Authenticate with Minecraft
      var mcResponse = await authenticateWithMinecraft(userHash, xstsToken);
      String mcAccessToken = mcResponse['access_token'];
      
      // 5. Get Minecraft profile
      var profile = await getMinecraftProfile(mcAccessToken);
      
      // Return combined result
      return {
        'username': profile['name'],
        'uuid': profile['id'],
        'accessToken': mcAccessToken,
        'profile': profile,
        'microsoft': {
          'accessToken': msAccessToken,
          'refreshToken': msTokens['refresh_token'],
        },
      };
    } catch (e) {
      print('Authentication flow failed: $e');
      rethrow;
    }
  }
  
  /// Refresh Microsoft access token
  static Future<Map<String, dynamic>> refreshMicrosoftToken(String refreshToken) async {
    Map<String, String> body = {
      'client_id': clientId,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
      'scope': 'XboxLive.signin offline_access',
    };
    
    var response = await http.post(
      Uri.parse(msTokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to refresh token: ${response.body}');
    }
    
    return json.decode(response.body);
  }
}
