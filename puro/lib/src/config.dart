import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:process/process.dart';

import '../models.dart';
import 'command.dart';
import 'provider.dart';

Directory? findProjectDir(Directory directory, String fileName) {
  while (directory.existsSync()) {
    if (directory.fileSystem
            .statSync(directory.childFile(fileName).path)
            .type !=
        FileSystemEntityType.notFound) {
      return directory;
    }
    final parent = directory.parent;
    if (directory.path == parent.path) break;
    directory = parent;
  }
  return null;
}

class PuroConfig {
  PuroConfig({
    required this.fileSystem,
    required this.gitExecutable,
    required Directory puroRoot,
    required this.projectDir,
    required this.parentProjectDir,
    required this.flutterGitUrl,
    required this.engineGitUrl,
    required this.releasesJsonUrl,
    required this.flutterStorageBaseUrl,
    required this.environmentOverride,
  }) : puroRoot = puroRoot.absolute;

  factory PuroConfig.fromCommandLine({
    required FileSystem fileSystem,
    required String? gitExecutable,
    required String? puroRoot,
    required String? workingDir,
    required String? projectDir,
    required String? flutterGitUrl,
    required String? engineGitUrl,
    required String? releasesJsonUrl,
    required String? flutterStorageBaseUrl,
    required String? environmentOverride,
  }) {
    gitExecutable ??= 'git';
    if (!const LocalProcessManager().canRun(gitExecutable)) {
      throw ArgumentError('Git executable not found');
    }

    final String homeDir;
    if (Platform.isWindows) {
      homeDir = Platform.environment['UserProfile']!;
    } else {
      homeDir = Platform.environment['HOME']!;
    }

    final Directory? resultProjectDir;
    final Directory? parentProjectDir;

    workingDir = projectDir ?? workingDir;

    final currentDir = workingDir == null
        ? fileSystem.currentDirectory
        : fileSystem.directory(workingDir);

    resultProjectDir = findProjectDir(
      currentDir,
      'pubspec.yaml',
    );

    parentProjectDir = projectDir != null
        ? resultProjectDir
        : findProjectDir(
              currentDir,
              dotfileName,
            ) ??
            resultProjectDir;

    return PuroConfig(
      fileSystem: fileSystem,
      gitExecutable: fileSystem.file(gitExecutable),
      puroRoot: puroRoot != null
          ? fileSystem.directory(puroRoot)
          : fileSystem.directory(homeDir).childDirectory('.puro'),
      projectDir: resultProjectDir,
      parentProjectDir: parentProjectDir,
      flutterGitUrl: Uri.parse(
        flutterGitUrl ?? 'https://github.com/flutter/flutter.git',
      ),
      engineGitUrl: Uri.parse(
        engineGitUrl ?? 'https://github.com/flutter/engine.git',
      ),
      releasesJsonUrl: Uri.parse(
        releasesJsonUrl ??
            'https://storage.googleapis.com/flutter_infra_release/releases/releases_${Platform.operatingSystem}.json',
      ),
      flutterStorageBaseUrl: Uri.parse(
        flutterStorageBaseUrl ?? 'https://storage.googleapis.com',
      ),
      environmentOverride: environmentOverride,
    );
  }

  final FileSystem fileSystem;
  final File gitExecutable;
  final Directory puroRoot;
  final Directory? projectDir;
  final Directory? parentProjectDir;
  final Uri flutterGitUrl;
  final Uri engineGitUrl;
  final Uri releasesJsonUrl;
  final Uri flutterStorageBaseUrl;
  final String? environmentOverride;

  static const dotfileName = '.puro.json';

  late final File? pubspecYamlFile = projectDir?.childFile('pubspec.yaml');
  late final File? puroDotfile = projectDir?.childFile(dotfileName);
  late final File? parentPuroDotfile = parentProjectDir?.childFile(dotfileName);
  late final Directory envsDir = puroRoot.childDirectory('envs');
  late final Directory sharedDir = puroRoot.childDirectory('shared');
  late final Directory sharedFlutterDir = sharedDir.childDirectory('flutter');
  late final Directory sharedCachesDir = sharedDir.childDirectory('caches');

  EnvConfig getEnv(String name) {
    ensureValidName(name);
    return EnvConfig(envDir: envsDir.childDirectory(name));
  }

  EnvConfig? tryGetCurrentEnv() {
    if (environmentOverride != null) {
      return getEnv(environmentOverride!)..ensureExists();
    }
    if (parentPuroDotfile?.existsSync() != true) return null;
    final dotfile = readDotfile();
    if (!dotfile.hasEnv()) return null;
    return getEnv(dotfile.env);
  }

  EnvConfig getCurrentEnv() {
    final env = tryGetCurrentEnv();
    if (env == null) {
      if (projectDir == null) {
        throw AssertionError('No project selected.');
      } else {
        throw AssertionError('No environment selected.');
      }
    }
    return env..ensureExists();
  }

  File get dotfileForWriting {
    if (projectDir?.path != parentProjectDir?.path) {
      throw AssertionError(
        'Ambiguous project selection between `$projectDir` and `$parentProjectDir`,'
        ' run this command in parent directory or use --project to disambiguate.',
      );
    }
    if (puroDotfile == null) {
      throw AssertionError('Could not find project root');
    }
    return puroDotfile!;
  }

  PuroDotfileModel readDotfile() {
    final model = PuroDotfileModel.create();
    if (parentPuroDotfile?.existsSync() ?? false) {
      model.mergeFromProto3Json(
        jsonDecode(parentPuroDotfile!.readAsStringSync()),
      );
    }
    return model;
  }

  PuroDotfileModel readDotfileForWriting() {
    final model = PuroDotfileModel.create();
    if (dotfileForWriting.existsSync()) {
      model.mergeFromProto3Json(
        jsonDecode(dotfileForWriting.readAsStringSync()),
      );
    }
    return model;
  }

  void writeDotfile(PuroDotfileModel dotfile) {
    dotfileForWriting.writeAsStringSync(
      prettyJsonEncoder.convert(
        dotfile.toProto3Json(),
      ),
    );
  }

  static final provider = Provider<PuroConfig>.late();
  static PuroConfig of(Scope scope) => scope.read(provider);
}

class EnvConfig {
  EnvConfig({
    required this.envDir,
  });

  final Directory envDir;

  late final String name = envDir.basename;
  late final Directory recipeDir = envDir.childDirectory('recipe');
  late final Directory engineDir = envDir.childDirectory('engine');
  late final Directory dartSdkDir = envDir.childDirectory('dart');
  late final Directory flutterDir = envDir.childDirectory('flutter');
  late final FlutterConfig flutter = FlutterConfig(flutterDir);

  bool get exists => envDir.existsSync();

  void ensureExists() {
    if (!exists) {
      throw ArgumentError('No such environment `$name`');
    }
  }

  // TODO(ping): Maybe support changing this in the future
  String get flutterToolArgs => '';
}

class FlutterConfig {
  FlutterConfig(this.sdkDir);

  final Directory sdkDir;

  late final Directory binDir = sdkDir.childDirectory('bin');
  late final Directory packagesDir = sdkDir.childDirectory('packages');
  late final File flutterScript =
      binDir.childFile(Platform.isWindows ? 'flutter.bat' : 'flutter');
  late final File dartScript =
      binDir.childFile(Platform.isWindows ? 'dart.bat' : 'dart');
  late final Directory binInternalDir = binDir.childDirectory('internal');
  late final Directory cacheDir = binDir.childDirectory('cache');
  late final FlutterCacheConfig cache = FlutterCacheConfig(cacheDir);
  late final File engineVersionFile =
      binInternalDir.childFile('engine.version');
  late final Directory flutterToolsDir =
      packagesDir.childDirectory('flutter_tools');
  late final File flutterToolsScriptFile =
      flutterToolsDir.childDirectory('bin').childFile('flutter_tools.dart');
  late final File flutterToolsPubspecYamlFile =
      flutterToolsDir.childFile('pubspec.yaml');
  late final File flutterToolsPubspecLockFile =
      flutterToolsDir.childFile('pubspec.lock');
  late final File flutterToolsPackageConfigJsonFile = flutterToolsDir
      .childDirectory('.dart_tool')
      .childFile('package_config.json');

  String? get engineVersion => engineVersionFile.existsSync()
      ? engineVersionFile.readAsStringSync().trim()
      : null;
}

class FlutterCacheConfig {
  FlutterCacheConfig(this.cacheDir);

  final Directory cacheDir;

  late final Directory dartSdkDir = cacheDir.childDirectory('dart-sdk');
  late final DartSdkConfig dartSdk = DartSdkConfig(dartSdkDir);

  late final File flutterToolsSnapshotFile =
      cacheDir.childFile('flutter_tools.snapshot');
  late final File flutterToolsStampFile =
      cacheDir.childFile('flutter_tools.stamp');
  late final File engineVersionFile =
      cacheDir.childFile('engine-dart-sdk.stamp');
  String? get engineVersion => engineVersionFile.existsSync()
      ? engineVersionFile.readAsStringSync().trim()
      : null;
  String? get flutterToolsStamp => flutterToolsStampFile.existsSync()
      ? flutterToolsStampFile.readAsStringSync().trim()
      : null;

  bool get exists => cacheDir.existsSync();
}

class DartSdkConfig {
  DartSdkConfig(this.sdkDir);

  final Directory sdkDir;

  late final Directory binDir = sdkDir.childDirectory('bin');
  late final File dartExecutable =
      binDir.childFile(Platform.isWindows ? 'dart.exe' : 'dart');
}

final _nameRegex = RegExp(
  r'^[_\-\p{L}][_\-\p{L}\p{N}]+?$',
  unicode: true,
);
bool isValidName(String name) {
  return _nameRegex.hasMatch(name);
}

void ensureValidName(String name) {
  if (!isValidName(name)) {
    throw ArgumentError('Not a valid name: `$name`');
  }
}