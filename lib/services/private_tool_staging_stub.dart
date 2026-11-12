import 'private_tool_staging.dart';

PrivateToolStagingStore createPrivateToolStagingStore({
  Future<String> Function()? rootDirectory,
}) => _UnsupportedPrivateToolStagingStore();

class _UnsupportedPrivateToolStagingStore implements PrivateToolStagingStore {
  Never _unsupported() =>
      throw const PrivateStageException(PrivateStageFailure.unsupported);
  @override
  Future<PrivateToolStage> create({required String kind, String? id}) async =>
      _unsupported();
  @override
  Future<PrivateToolStage> open({
    required String kind,
    required String id,
  }) async => _unsupported();
  @override
  Future<List<String>> list(String kind) async => _unsupported();
}
