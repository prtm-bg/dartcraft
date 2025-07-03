import 'package:test/test.dart';
import 'package:dartcraft/src/auth/ely_auth.dart';

void main() {
  group('Ely.by OAuth2 Authentication', () {
    test('ElyOAuthConfig creation', () {
      const config = ElyOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
      );
      
      expect(config.clientId, 'test_client_id');
      expect(config.clientSecret, 'test_client_secret');
      expect(config.redirectUri, 'http://localhost:8080/callback');
      expect(config.scope, 'account_info minecraft_server_session');
    });
    
    test('ElyOAuthConfig with custom parameters', () {
      const config = ElyOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
        redirectUri: 'http://localhost:9999/callback',
        scope: 'account_info',
      );
      
      expect(config.redirectUri, 'http://localhost:9999/callback');
      expect(config.scope, 'account_info');
    });
    
    test('ElyOAuthToken creation and expiry check', () {
      final token = ElyOAuthToken(
        accessToken: 'test_access_token',
        refreshToken: 'test_refresh_token',
        tokenType: 'bearer',
        expiresIn: 3600,
        scope: 'account_info',
      );
      
      expect(token.accessToken, 'test_access_token');
      expect(token.refreshToken, 'test_refresh_token');
      expect(token.tokenType, 'bearer');
      expect(token.expiresIn, 3600);
      expect(token.scope, 'account_info');
      expect(token.isExpired, false);
    });
    
    test('ElyOAuthToken from JSON', () {
      final json = {
        'access_token': 'test_access_token',
        'refresh_token': 'test_refresh_token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'scope': 'account_info',
      };
      
      final token = ElyOAuthToken.fromJson(json);
      
      expect(token.accessToken, 'test_access_token');
      expect(token.refreshToken, 'test_refresh_token');
      expect(token.tokenType, 'bearer');
      expect(token.expiresIn, 3600);
      expect(token.scope, 'account_info');
    });
    
    test('ElyUser creation', () {
      final user = ElyUser(
        id: 'test_id',
        username: 'testuser',
        email: 'test@example.com',
        lang: 'en',
      );
      
      expect(user.id, 'test_id');
      expect(user.username, 'testuser');
      expect(user.email, 'test@example.com');
      expect(user.lang, 'en');
    });
    
    test('ElyUser from JSON', () {
      final json = {
        'id': 'test_id',
        'username': 'testuser',
        'email': 'test@example.com',
        'lang': 'en',
        'profileLink': 'https://ely.by/u/testuser',
      };
      
      final user = ElyUser.fromJson(json);
      
      expect(user.id, 'test_id');
      expect(user.username, 'testuser');
      expect(user.email, 'test@example.com');
      expect(user.lang, 'en');
      expect(user.profileLink, 'https://ely.by/u/testuser');
    });
    
    test('ElyAuthResult creation', () {
      final token = ElyOAuthToken(
        accessToken: 'test_access_token',
        refreshToken: 'test_refresh_token',
        tokenType: 'bearer',
        expiresIn: 3600,
        scope: 'account_info',
      );
      
      final user = ElyUser(
        id: 'test_id',
        username: 'testuser',
        email: 'test@example.com',
      );
      
      final result = ElyAuthResult(
        token: token,
        user: user,
        minecraftAccessToken: 'minecraft_token',
        minecraftUsername: 'MinecraftUser',
        minecraftUuid: 'uuid-1234',
      );
      
      expect(result.token, token);
      expect(result.user, user);
      expect(result.minecraftAccessToken, 'minecraft_token');
      expect(result.minecraftUsername, 'MinecraftUser');
      expect(result.minecraftUuid, 'uuid-1234');
    });
    
    test('ElyAuthException creation', () {
      final exception = ElyAuthException('test_error', 'Test error message');
      
      expect(exception.error, 'test_error');
      expect(exception.errorMessage, 'Test error message');
      expect(exception.toString(), 'ElyAuthException: test_error - Test error message');
    });
  });
}
