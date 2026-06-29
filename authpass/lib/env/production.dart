import 'package:authpass/env/_base.dart';
import 'package:authpass/env/env.dart';
import 'package:string_literal_finder_annotations/string_literal_finder_annotations.dart';

Future<void> main() async => await Production().start();

class Production extends EnvAppBase {
  Production() : super(EnvType.production);

  @NonNls
  @override
  String get storageNamespace => '${super.storageNamespace ?? ''}production';

  @override
  EnvSecrets? get secrets => EnvSecrets.nullSecrets;
}
