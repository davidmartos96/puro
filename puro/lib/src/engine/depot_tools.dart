import 'package:process/process.dart';

import '../command_result.dart';
import '../config.dart';
import '../git.dart';
import '../logger.dart';
import '../provider.dart';

Future<void> installDepotTools({
  required Scope scope,
}) async {
  final log = PuroLogger.of(scope);
  final config = PuroConfig.of(scope);
  final git = GitClient.of(scope);
  final depotToolsDir = config.depotToolsDir;
  if (depotToolsDir.existsSync() &&
      depotToolsDir.childFile('gclient').existsSync()) {
    log.v('depot_tools already installed');
  } else {
    await git.cloneWithProgress(
      remote:
          'https://chromium.googlesource.com/chromium/tools/depot_tools.git',
      repository: depotToolsDir,
    );
  }
  const pm = LocalProcessManager();
  if (!pm.canRun('gclient')) {
    throw CommandError(
      "Can't find gclient, is `${depotToolsDir.path}` in your PATH?",
    );
  }
}
