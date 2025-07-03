<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

# Dartcraft - A Minecraft Launcher Library for Dart

Dartcraft is a comprehensive Minecraft launcher library for Dart, inspired by Python's `minecraft-launcher-lib`. It provides functionality to install and launch Minecraft with support for vanilla installations, native libraries, and Microsoft authentication.

## How `minecraft-launcher-lib` Works

The core of this project's functionality relies on the `minecraft-launcher-lib` Python library. Understanding how it works is crucial to understanding Dartcraft.

### Core Functionality

The library is designed to programmatically install and launch Minecraft. It achieves this by interacting with Mojang's APIs to fetch version manifests, download game files, and construct the necessary commands to start the game.

At its heart, `minecraft-launcher-lib` is a Python library that automates the process of setting up and running Minecraft. It's composed of several modules, each responsible for a specific part of the process.

### Installation Process

The installation process is primarily handled by the `install` module. The `install_minecraft_version` function is the main entry point for this process. Here's a breakdown of how it works:

```
function install_minecraft_version(version_id, minecraft_directory):
  version_manifest = fetch("https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")
  version_info = find_version_in_manifest(version_manifest, version_id)
  version_json = fetch(version_info.url)

  if version_json.inheritsFrom:
    install_minecraft_version(version_json.inheritsFrom, minecraft_directory)
    version_json = merge_with_parent(version_json, minecraft_directory)

  install_libraries(version_json.libraries, minecraft_directory)
  install_assets(version_json.assetIndex, minecraft_directory)
  download_client_jar(version_json.downloads.client, minecraft_directory)

  if version_json.javaVersion:
    install_jvm_runtime(version_json.javaVersion.component, minecraft_directory)
```

1.  **Version Manifest**: It starts by fetching the version manifest from Mojang's servers. This manifest contains a list of all available Minecraft versions, along with URLs to their respective JSON files.

2.  **Version JSON**: Once the desired version is found in the manifest, it downloads the corresponding JSON file. This file contains detailed information about the version, including:
    *   **Libraries**: A list of libraries that the game depends on, such as LWJGL, GSON, etc.
    *   **Assets**: Information about the game's assets (textures, sounds, etc.).
    *   **Main Class**: The main Java class to execute.
    *   **Arguments**: Arguments to be passed to the Java Virtual Machine (JVM) and the game itself.

3.  **Inheritance**: Some versions, particularly modded ones like Forge, inherit from a base vanilla version. The library handles this by recursively installing the base version first and then merging the JSON data.

4.  **Library Installation**: The `install_libraries` function iterates through the list of libraries in the version JSON. For each library, it:
    *   Checks the rules to see if the library is required for the current operating system.
    *   Constructs the download URL and path for the library.
    *   Downloads the library JAR file.
    *   Handles native libraries by extracting them to the appropriate directory.

```
function install_libraries(libraries, minecraft_directory):
  for library in libraries:
    if rules_allow(library.rules):
      path = build_library_path(library.name)
      download(library.downloads.artifact.url, path)
      if library.natives:
        native_jar_path = download(library.downloads.classifiers[native].url)
        extract_natives(native_jar_path, natives_directory)
```

5.  **Asset Installation**: The `install_assets` function is responsible for downloading all the game's assets. It:
    *   Downloads the asset index file, which contains a list of all assets and their hashes.
    *   Iterates through the asset list and downloads each asset from `resources.download.minecraft.net`.
    *   Saves the assets in the `assets/objects` directory, using the hash to create a directory structure.

```
function install_assets(asset_index, minecraft_directory):
  asset_index_json = fetch(asset_index.url)
  for asset in asset_index_json.objects:
    hash = asset.hash
    path = "assets/objects/" + hash[:2] + "/" + hash
    download("https://resources.download.minecraft.net/" + hash[:2] + "/" + hash, path)
```

6.  **Client JAR**: It downloads the main client JAR file for the specified version (e.g., `1.19.4.jar`).

7.  **Java Runtime**: If the version requires a specific Java runtime, the `runtime` module is used to download and install it.

### Launching the Game

Once a version is installed, the `command` module is used to construct the command to launch the game. The `get_minecraft_command` function is the key function here. It takes the version ID, Minecraft directory, and other options as input and returns a list of strings representing the command to be executed.

```
function get_minecraft_command(version_id, minecraft_directory, options):
  version_json = read_version_json(version_id, minecraft_directory)
  classpath = build_classpath(version_json.libraries, minecraft_directory)
  main_class = version_json.mainClass
  jvm_args = replace_placeholders(version_json.arguments.jvm, options)
  game_args = replace_placeholders(version_json.arguments.game, options)

  return [
    "java",
    "-Djava.library.path=<natives_directory>",
    "-cp",
    classpath,
    main_class
  ] + jvm_args + game_args
```

Here's how it works:

1.  **Read Version JSON**: It reads the version JSON file for the specified version.

2.  **Build Classpath**: It constructs the Java classpath by gathering all the required library JARs and the client JAR.

3.  **Get Arguments**: It gets the JVM and game arguments from the version JSON. These arguments can be simple strings or complex objects with rules for different operating systems and features.

4.  **Replace Placeholders**: The arguments contain placeholders like `${auth_player_name}`, `${version_name}`, etc. The library replaces these placeholders with the actual values.

5.  **Natives**: It sets the `java.library.path` system property to the directory where the native libraries were extracted.

6.  **Main Class**: It gets the main class from the version JSON.

7.  **Construct Command**: Finally, it assembles the complete command, which typically looks something like this:

```
<path_to_java> -Djava.library.path=<natives_directory> -cp <classpath> <main_class> <game_arguments>
```

### Mod Support

`minecraft-launcher-lib` also has excellent support for modded versions of Minecraft, including Forge, Fabric, and Quilt. The `forge`, `fabric`, and `quilt` modules provide functions to install and launch these mod loaders.

The process is similar to installing a vanilla version, but with some extra steps:

*   **Forge**: Forge has an installer that needs to be run. The `forge.install_forge_version` function downloads the Forge installer, runs it, and then installs the version.

```
function install_forge_version(version_id, minecraft_directory):
    forge_installer_url = get_forge_installer_url(version_id)
    installer_path = download(forge_installer_url)
    run_java_installer(installer_path)
```

*   **Fabric**: Fabric is installed by downloading the Fabric loader JSON file and merging it with the vanilla version JSON. The `fabric.install_fabric` function handles this.

```
function install_fabric(version_id, minecraft_directory):
    fabric_loader_json_url = get_fabric_loader_json_url(version_id)
    fabric_loader_json = fetch(fabric_loader_json_url)
    # fabric_loader_json is then used to find the main class and add to the arguments
    # It inherits from a vanilla version
    install_minecraft_version(fabric_loader_json.inheritsFrom, minecraft_directory)
```

*   **Quilt**: Quilt installation is very similar to Fabric's.

### Microsoft Account Authentication

The `microsoft_account` module handles authentication with Microsoft accounts, which is now the standard for Minecraft. It provides functions to:

*   Get the login URL for Microsoft accounts.
*   Get the refresh and access tokens after the user logs in.
*   Refresh the tokens when they expire.

```
function login():
    login_url = get_microsoft_login_url()
    # User opens this URL in a browser and logs in
    # After login, the browser is redirected to a URL with a code
    auth_code = extract_code_from_redirect_url()
    access_token, refresh_token = get_tokens_from_code(auth_code)
    return access_token, refresh_token
```

This allows the library to get the necessary authentication information to launch the game.

### Other Modules

*   **`utils`**: Provides various utility functions, such as getting the default Minecraft directory, validating file hashes, and more.
*   **`java_utils`**: Provides functions for finding and validating Java installations.
*   **`news`**: Fetches the latest Minecraft news from Mojang's API.
*   **`mrpack`**: Provides support for installing modpacks in the `.mrpack` format.
*   **`exceptions`**: Defines custom exceptions for the library.
*   **`types` and `microsoft_types`**: Define TypedDicts for the various JSON structures used by the library, providing type safety and better editor support.

In summary, `minecraft-launcher-lib` is a comprehensive and well-structured library that provides all the necessary tools to create a custom Minecraft launcher. It's a powerful tool for developers who want to build applications that interact with Minecraft.

## Features

TODO: List what your package can do. Maybe include images, gifs, or videos.

## Getting started

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder.

```dart
const like = 'sample';
```

## Additional information

TODO: Tell users more about the package: where to find more information, how to
contribute to the package, how to file issues, what response they can expect
from the package authors, and more.
