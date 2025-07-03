# Ely.by OAuth2 Authentication

This document explains how to use the Ely.by OAuth2 authentication flow in Dartcraft.

## Setup

### 1. Register Your Application

First, you need to register your application with Ely.by:

1. Go to [https://account.ely.by/dev/applications/new](https://account.ely.by/dev/applications/new)
2. Click "Create new application"
3. Fill in the application details:
   - **Name**: Your launcher name
   - **Description**: Description of your launcher
   - **Website**: Your website (optional)
   - **Redirect URI**: `http://localhost:8080/callback` (or your custom URI)
4. Save the **Client ID** and **Client Secret** for your configuration

### 2. Add Dependencies

Make sure your `pubspec.yaml` includes the required dependencies:

```yaml
dependencies:
  http: ^1.4.0
  crypto: ^3.0.3
  shelf: ^1.4.1
```

**Note**: This implementation uses pure Dart and doesn't require Flutter dependencies, making it suitable for both console applications and Flutter apps.

## Usage

### Basic OAuth2 Authentication

```dart
import 'package:dartcraft/dartcraft.dart';

Future<void> authenticateUser() async {
  // Configure OAuth2 settings
  const config = ElyOAuthConfig(
    clientId: 'your_client_id_here',
    clientSecret: 'your_client_secret_here',
    redirectUri: 'http://localhost:8080/callback',
    scope: 'account_info minecraft_server_session',
  );

  try {
    // Start OAuth2 flow - this will open the user's browser
    final authResult = await ElyAuth.authenticateWithOAuth(config);
    
    print('✅ Authentication successful!');
    print('User: ${authResult.user.username}');
    print('Minecraft Username: ${authResult.minecraftUsername}');
    print('Minecraft UUID: ${authResult.minecraftUuid}');
    
    // Use the authentication result to launch Minecraft
    await launchMinecraft(authResult);
    
  } catch (e) {
    if (e is ElyAuthException) {
      print('❌ Authentication failed: ${e.error}');
      print('   ${e.errorMessage}');
    } else {
      print('❌ Unexpected error: $e');
    }
  }
}
```

### With Token Persistence

For a better user experience, you should save and reuse tokens:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:dartcraft/dartcraft.dart';

class TokenManager {
  static const String _tokenFile = 'ely_token.json';
  
  // Save token to file
  static Future<void> saveToken(ElyOAuthToken token) async {
    final tokenData = {
      'access_token': token.accessToken,
      'refresh_token': token.refreshToken,
      'token_type': token.tokenType,
      'expires_in': token.expiresIn,
      'scope': token.scope,
      'expires_at': token.expiresAt.toIso8601String(),
    };
    
    final file = File(_tokenFile);
    await file.writeAsString(json.encode(tokenData));
  }
  
  // Load token from file
  static Future<ElyOAuthToken?> loadToken() async {
    try {
      final file = File(_tokenFile);
      if (!await file.exists()) return null;
      
      final tokenData = json.decode(await file.readAsString());
      return ElyOAuthToken(
        accessToken: tokenData['access_token'],
        refreshToken: tokenData['refresh_token'],
        tokenType: tokenData['token_type'],
        expiresIn: tokenData['expires_in'],
        scope: tokenData['scope'],
      );
    } catch (e) {
      print('Failed to load token: $e');
      return null;
    }
  }
  
  // Delete saved token
  static Future<void> clearToken() async {
    final file = File(_tokenFile);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<ElyOAuthToken> getValidToken(ElyOAuthConfig config) async {
  // Try to load existing token
  ElyOAuthToken? token = await TokenManager.loadToken();
  
  if (token != null && !token.isExpired) {
    print('✅ Using saved token');
    return token;
  } else if (token != null && token.isExpired) {
    try {
      print('🔄 Refreshing expired token');
      token = await ElyAuth.refreshOAuthToken(config, token.refreshToken);
      await TokenManager.saveToken(token);
      return token;
    } catch (e) {
      print('❌ Failed to refresh token: $e');
      // Fall through to new authentication
    }
  }
  
  print('🔐 Starting new authentication flow');
  final authResult = await ElyAuth.authenticateWithOAuth(config);
  await TokenManager.saveToken(authResult.token);
  return authResult.token;
}
```

### Integration with Minecraft Launcher

```dart
Future<void> launchMinecraftWithEly() async {
  const config = ElyOAuthConfig(
    clientId: 'your_client_id_here',
    clientSecret: 'your_client_secret_here',
  );
  
  try {
    // Get valid authentication
    final authResult = await ElyAuth.authenticateWithOAuth(config);
    
    // Create Dartcraft launcher
    final launcher = Dartcraft('1.20.4', '/path/to/minecraft');
    
    // Install if needed
    if (!launcher.isInstalled) {
      print('📦 Installing Minecraft...');
      await launcher.install();
    }
    
    // Launch with Ely.by authentication
    print('🚀 Launching Minecraft...');
    final process = await launcher.launch(
      username: authResult.minecraftUsername,
      uuid: authResult.minecraftUuid,
      accessToken: authResult.minecraftAccessToken,
      // Add Ely.by authlib-injector for full compatibility
      jvmArgs: ElyAuth.getAuthlibJvmArgs(await ElyAuth.downloadAuthlibInjector('/path/to/libs')),
    );
    
    print('✅ Minecraft launched successfully!');
    
  } catch (e) {
    print('❌ Failed to launch Minecraft: $e');
  }
}
```

## Configuration Options

### ElyOAuthConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `clientId` | String | Required | Your application's client ID from Ely.by |
| `clientSecret` | String | Required | Your application's client secret from Ely.by |
| `redirectUri` | String | `http://localhost:8080/callback` | OAuth callback URI |
| `scope` | String | `account_info minecraft_server_session` | OAuth scopes to request |

### Available Scopes

- `account_info`: Access to user's account information
- `minecraft_server_session`: Access to Minecraft session tokens

## Error Handling

The OAuth2 flow can throw `ElyAuthException` with various error types:

```dart
try {
  final authResult = await ElyAuth.authenticateWithOAuth(config);
} on ElyAuthException catch (e) {
  switch (e.error) {
    case 'BrowserLaunchFailed':
      print('Could not open browser for authentication');
      break;
    case 'AuthTimeout':
      print('Authentication timed out');
      break;
    case 'StateMismatch':
      print('Security error: OAuth state mismatch');
      break;
    case 'access_denied':
      print('User denied access');
      break;
    default:
      print('Authentication error: ${e.error} - ${e.errorMessage}');
  }
}
```

## Security Considerations

1. **PKCE**: The implementation uses PKCE (Proof Key for Code Exchange) for enhanced security
2. **State Parameter**: Random state parameters prevent CSRF attacks
3. **Token Storage**: Store tokens securely (consider using encrypted storage for production apps)
4. **HTTPS**: Use HTTPS redirect URIs in production
5. **Token Refresh**: Always refresh expired tokens instead of re-authenticating

## Browser Compatibility

The OAuth2 flow opens the system's default browser. Ensure your users have a modern browser installed. The callback page works with:

- Chrome/Chromium
- Firefox
- Safari
- Edge
- Other modern browsers

## Troubleshooting

### "Failed to open browser"
- Ensure `url_launcher` is properly configured for your platform
- Check if the user has a default browser set

### "Authentication timed out"
- The user has 5 minutes to complete authentication
- Increase timeout if needed by modifying the `_waitForCallback` method

### "Port already in use"
- Change the `redirectUri` port if 8080 is occupied
- Ensure the port matches your registered redirect URI

### "Invalid client"
- Verify your `clientId` and `clientSecret` are correct
- Ensure your application is properly registered on Ely.by

## Advanced Usage

### Custom Redirect URI

If you need to use a different port or host:

```dart
const config = ElyOAuthConfig(
  clientId: 'your_client_id',
  clientSecret: 'your_client_secret',
  redirectUri: 'http://localhost:9999/auth/callback',
);
```

Make sure to register this URI in your Ely.by application settings.

### Token Validation

You can manually validate tokens:

```dart
final isValid = await ElyAuth.validate(token.accessToken);
if (!isValid) {
  // Token is invalid, need to refresh or re-authenticate
}
```

### Getting User Info

Get additional user information:

```dart
final user = await ElyAuth.getUserInfo(token);
print('User email: ${user.email}');
print('Profile link: ${user.profileLink}');
```
