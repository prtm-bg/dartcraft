import 'package:dartcraft/dartcraft.dart';

void main() async {
  // Create a Dartcraft instance
  final dartcraft = Dartcraft.testing();
  
  try {
    // PART 1: Show available Minecraft versions
    print('Fetching available Minecraft versions...');
    final versions = await Dartcraft.getReleaseVersions();
    print('Available Minecraft release versions:');
    for (var i = 0; i < 5 && i < versions.length; i++) {
      print('- ${versions[i].id} (${versions[i].releaseTime})');
    }
    print('... and ${versions.length - 5} more');
    
    // PART 2: Install or update Minecraft
    if (!dartcraft.isInstalled) {
      print('\nInstalling Minecraft...');
      await dartcraft.install();
      print('Installation completed: ${dartcraft.isInstalled}');
    } else {
      print('\nMinecraft is already installed');
    }
    
    // PART 3: Launch the game
    print('\nLaunching Minecraft...');
    final process = await dartcraft.launch(
      username: 'Player1',
      uuid: '00000000-0000-0000-0000-000000000000', // Replace with a valid UUID
      accessToken: 'demo_token', // Replace with a valid token for online play
      // Optional: Add JVM arguments to improve performance
      jvmArguments: ['-Xmx2G', '-Xms1G'], // Allocate 1-2GB of RAM
    );
    
    print('Minecraft launched successfully!');
    print('Press Ctrl+C to stop the Minecraft process...');
    
    // Keep the application running until Minecraft exits or user presses Ctrl+C
    await process.exitCode.then((code) => print('Minecraft exited with code: $code'));
  } catch (e) {
    if (e is DartcraftException) {
      print('Dartcraft error: ${e.message}');
      if (e.cause != null) {
        print('Cause: ${e.cause}');
      }
    } else {
      print('Unexpected error: $e');
    }
  }
}

// PART 4: Example of Microsoft authentication
void exampleMicrosoftAuth() async {
  // Configure Microsoft OAuth2 credentials (register at https://portal.azure.com)
  MicrosoftAuth.configure(
    clientId: 'your-client-id-here',
    redirectUri: 'http://localhost:8080/callback',
  );
  
  print('Example: Microsoft Authentication');
  // In your app, you should open this URL in a web browser
  final authUrl = MicrosoftAuth.getAuthorizationUrl();
  print('Open this URL in your browser: $authUrl');
  
  // After the user completes authentication, you'll receive an authorization code
  // For this example, we'll simulate having received one
  const authCode = 'example_auth_code_from_microsoft';
  
  try {
    // Exchange the authorization code for an access token and profile
    final authResult = await Dartcraft.authenticateWithMicrosoft(authCode);
    print('Authentication successful!');
    print('Username: ${authResult.username}');
    print('UUID: ${authResult.uuid}');
    
    // Create launcher instance
    final dartcraft = Dartcraft.testing();
    
    // Now launch Minecraft with the authenticated user
    print('\nLaunching Minecraft with authenticated user...');
    final process = await dartcraft.launch(
      username: authResult.username,
      uuid: authResult.uuid,
      accessToken: authResult.accessToken,
    );
    
    print('Minecraft launched successfully with authenticated user!');
    await process.exitCode.then((code) => print('Minecraft exited with code: $code'));
  } catch (e) {
    print('Authentication failed: $e');
  }
}

// PART 5: Example of Ely.by authentication
void exampleElyByAuth() async {
  final dartcraft = Dartcraft(
    '1.20.4',
    '/path/to/minecraft',
    useElyBy: true,
  );
  
  try {
    // Basic Ely.by authentication
    final authResult = await dartcraft.authenticateWithElyBy(
      'your-username',
      'your-password',
    );
    
    print('Ely.by authentication successful!');
    print('Username: ${authResult.username}');
    
    // Launch with Ely.by authentication
    final process = await dartcraft.launch(
      username: authResult.username,
      uuid: authResult.uuid,
      accessToken: authResult.accessToken,
    );
    
    print('Minecraft launched with Ely.by authentication!');
    await process.exitCode.then((code) => print('Minecraft exited with code: $code'));
  } on TwoFactorRequiredException {
    // Handle 2FA if required
    print('Two-factor authentication required. Enter your TOTP code:');
    const totpCode = '123456'; // Get from user input
    
    final authResult = await dartcraft.authenticateWithElyByTwoFactor(
      'your-username',
      'your-password',
      totpCode,
    );
    
    print('Ely.by 2FA authentication successful!');
    print('Username: ${authResult.username}');
    
    // Launch game with 2FA authenticated user
    final process = await dartcraft.launch(
      username: authResult.username,
      uuid: authResult.uuid,
      accessToken: authResult.accessToken,
    );
    
    print('Minecraft launched with Ely.by 2FA!');
    await process.exitCode.then((code) => print('Minecraft exited with code: $code'));
  } catch (e) {
    print('Ely.by authentication failed: $e');
  }
}
