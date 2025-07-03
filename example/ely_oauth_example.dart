import 'package:dartcraft/src/auth/ely_auth.dart';

Future<void> main() async {
  // Configure OAuth2 settings
  // You need to register your application at https://account.ely.by/dev/applications/new
  const config = ElyOAuthConfig(
    clientId: 'your_client_id_here',
    clientSecret: 'your_client_secret_here',
    redirectUri: 'http://localhost:8080/callback',
    scope: 'account_info minecraft_server_session',
  );

  try {
    print('Starting Ely.by OAuth2 authentication...');
    print('Your browser will open for authentication.');
    
    // Perform OAuth2 authentication
    final authResult = await ElyAuth.authenticateWithOAuth(config);
    
    print('\n✅ Authentication successful!');
    print('User: ${authResult.user.username} (${authResult.user.email})');
    print('Minecraft Username: ${authResult.minecraftUsername}');
    print('Minecraft UUID: ${authResult.minecraftUuid}');
    print('Access Token: ${authResult.token.accessToken.substring(0, 20)}...');
    print('Token expires at: ${authResult.token.expiresAt}');
    
    // Example: Check if token needs refresh
    if (authResult.token.isExpired) {
      print('\n🔄 Token is expired, refreshing...');
      final newToken = await ElyAuth.refreshOAuthToken(config, authResult.token.refreshToken);
      print('✅ Token refreshed successfully!');
      print('New access token: ${newToken.accessToken.substring(0, 20)}...');
    } else {
      print('\n✅ Token is still valid for ${authResult.token.expiresAt.difference(DateTime.now()).inMinutes} minutes');
    }
    
    // The authResult contains everything needed to launch Minecraft:
    // - authResult.minecraftAccessToken: Use this as the Minecraft access token
    // - authResult.minecraftUsername: The player's Minecraft username
    // - authResult.minecraftUuid: The player's Minecraft UUID
    
  } catch (e) {
    if (e is ElyAuthException) {
      print('❌ Authentication failed: ${e.error}');
      print('   ${e.errorMessage}');
    } else {
      print('❌ Unexpected error: $e');
    }
  }
}

/// Example of using OAuth2 with token persistence
Future<void> exampleWithTokenStorage() async {
  const config = ElyOAuthConfig(
    clientId: 'your_client_id_here',
    clientSecret: 'your_client_secret_here',
  );

  try {
    // In a real app, you would load saved tokens from storage
    ElyOAuthToken? savedToken = await loadTokenFromStorage();
    
    if (savedToken != null && !savedToken.isExpired) {
      print('✅ Using saved token');
      // Use the saved token
    } else if (savedToken != null && savedToken.isExpired) {
      print('🔄 Refreshing expired token');
      savedToken = await ElyAuth.refreshOAuthToken(config, savedToken.refreshToken);
      await saveTokenToStorage(savedToken);
    } else {
      print('🔐 Starting new authentication flow');
      final authResult = await ElyAuth.authenticateWithOAuth(config);
      await saveTokenToStorage(authResult.token);
      savedToken = authResult.token;
    }
    
    // Get current user info with the valid token
    final user = await ElyAuth.getUserInfo(savedToken);
    print('Logged in as: ${user.username}');
    
  } catch (e) {
    print('❌ Authentication error: $e');
  }
}

// Mock storage functions - implement these based on your storage needs
Future<ElyOAuthToken?> loadTokenFromStorage() async {
  // Implement loading from secure storage, file, database, etc.
  return null;
}

Future<void> saveTokenToStorage(ElyOAuthToken token) async {
  // Implement saving to secure storage, file, database, etc.
  print('💾 Token saved to storage');
}
