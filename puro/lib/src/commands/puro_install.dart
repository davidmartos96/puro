import 'dart:io';

import '../command.dart';
import '../config.dart';
import '../install/profile.dart';
import '../version.dart';

class PuroInstallCommand extends PuroCommand {
  @override
  final name = 'install-puro';

  @override
  bool get hidden => true;

  @override
  final description = 'Finishes installation of the puro tool.';

  @override
  Future<CommandResult> run() async {
    final version = await getPuroVersion(scope: scope);
    final config = PuroConfig.of(scope);
    final homeDir = config.homeDir.path;
    final homeVar = Platform.isWindows ? '%HOME%' : '~';
    final scriptPath =
        Platform.script.toFilePath().replaceAll(homeDir, homeVar);
    String? profilePath;
    if (Platform.isLinux || Platform.isMacOS) {
      final profile = await tryUpdateProfile(scope: scope);
      profilePath = profile?.path.replaceAll(homeDir, homeVar);
    }
    final externalMessage =
        await detectExternalFlutterInstallations(scope: scope);
    return BasicMessageResult.list(
      success: true,
      messages: [
        if (profilePath != null)
          CommandMessage(
            (format) => 'Updated PATH in $profilePath',
          ),
        CommandMessage(
          (format) => 'Successfully installed Puro $version to $scriptPath',
        ),
        if (externalMessage != null) externalMessage,
      ],
    );
  }
}
