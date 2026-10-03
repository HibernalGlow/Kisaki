import 'models.dart';

/// The seam between the board UI and whatever answers it.
///
/// The synchronous registry calls mirror the `#[frb(sync)]` bridge functions;
/// `startScan` mirrors the `StreamSink<ScanEvent>` call, so the FRB adapter is
/// a forwarding implementation and the fake engine drives the same code path.
abstract interface class KisakiEngine {
  List<ToolSpec> listTools();

  List<FieldDef> fieldDefs(String tool);

  List<FieldValue> defaultFields(String tool);

  EngineInfo engineInfo();

  Stream<ScanEvent> startScan(ScanRequest request);

  bool requestStop();

  bool isScanning();

  Future<DeleteOutcome> deleteFiles(DeleteRequest request);

  Future<String> exportResults(ExportRequest request);

  Future<RenameOutcome> renameFiles(RenameRequest request);

  Future<MoveOutcome> moveFiles(MoveRequest request);

  Future<SimiuApplyOutcome> applySimiuSet(SimiuApplyRequest request);

  Future<SimiuUndoOutcome> undoSimiuSet(SimiuUndoRequest request);

  Future<ExifOutcome> cleanExif(ExifRequest request);
}
