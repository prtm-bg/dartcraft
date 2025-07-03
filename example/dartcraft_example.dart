import 'package:dartcraft/dartcraft.dart';
import 'dart:io';

void main() async {
  // Create a Dartcraft instance
  Dartcraft dartcraft = Dartcraft.test();
  
  try {
    // PART 1: Show available Minecraft versions
    print('Fetching available Minecraft versions...');
    var versions = await dartcraft.getReleaseVersions();
    print('Available Minecraft release versions:');
    for (var i = 0; i < 5 && i < versions.length; i++) {
      print('- ${versions[i]['id']} (${versions[i]['releaseTime']})');
    }
    print('... and ${versions.length - 5} more');
    
    // PART 2: Install or update Minecraft
    if (!dartcraft.isInstalled()) {
      print('\nInstalling Minecraft...');
      await dartcraft.install();
      print('Installation completed: ${dartcraft.isInstalled()}');
    } else {
      print('\nMinecraft is already installed');
      
      // If the game is already installed, make sure natives are extracted properly
      print('Ensuring native libraries are properly extracted...');
      await dartcraft.extractNativeLibraries();
    }
    
    // PART 3: Launch the game
    print('\nLaunching Minecraft...');
    Process? process = await dartcraft.launch(
      username: 'Player1',
      uuid: '00000000-0000-0000-0000-000000000000', // Replace with a valid UUID
      accessToken: 'demo_token', // Replace with a valid token for online play
      // Optional: Add JVM arguments to improve performance
      jvmArguments: ['-Xmx2G', '-Xms1G'], // Allocate 1-2GB of RAM
    );
    
    if (process != null) {
      print('Minecraft launched successfully!');
      print('Press Ctrl+C to stop the Minecraft process...');
      
      // Keep the application running until Minecraft exits or user presses Ctrl+C
      await process.exitCode.then((code) => print('Minecraft exited with code: $code'));
    }
  } catch (e) {
    if (e is DartcraftException) {
      print('Dartcraft error: ${e.message} (code: ${e.code})');
      if (e.originalError != null) {
        print('Original error: ${e.originalError}');
      }
    } else {
      print('Error: $e');
    }
  }
}

/// This is a more advanced example showing how to use Microsoft authentication
/// Note: You need to set up an OAuth application in Azure Portal to use this
void microsoftAuthExample() async {
  Dartcraft dartcraft = Dartcraft('1.20.4', './minecraft');
  
  // 1. First step is to get the authorization URL for the user to sign in
  String authUrl = dartcraft.getAuthorizationUrl();
  print('Please open this URL in a browser and sign in:');
  print(authUrl);
  
  // 2. After user signs in, they'll be redirected to your redirect URI with a code
  print('Enter the authorization code from the redirect URL:');
  String authCode = stdin.readLineSync() ?? '';
  
  try {
    // 3. Complete the authentication flow
    var authResult = await dartcraft.authenticate(authCode);
    
    // 4. Now we have the Minecraft username, UUID, and access token
    String username = authResult['username'];
    String uuid = authResult['uuid'];
    String accessToken = authResult['accessToken'];
    
    print('Authentication successful for $username!');
    
    // 5. Use these credentials to launch Minecraft
    Process? process = await dartcraft.launch(
      username: username,
      uuid: uuid,
      accessToken: accessToken,
    );
    
    if (process != null) {
      print('Minecraft launched successfully!');
      await process.exitCode.then((code) => print('Minecraft exited with code: $code'));
    }
  } catch (e) {
    print('Authentication failed: $e');
  }
}
