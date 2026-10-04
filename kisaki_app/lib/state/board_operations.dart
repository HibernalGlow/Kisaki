part of 'board_controller.dart';

/// The file-changing verbs of the board: each one is gated by the confirm overlay, the
/// dry-run switch and the engine's own answer, so they live apart from the table state.
extension BoardFileOperations on BoardController {
  /// Asks the confirm overlay first; the destructive path only runs from [acceptConfirm].
  void requestDelete() {
    final List<ScanRow> targets = selectedRows;
    if (targets.isEmpty) {
      _setStatus('status_nothing_selected');
      publish();
      return;
    }
    _confirmAction = () => _applyDelete(targets);
    _confirm = ConfirmRequest(
      titleKey: dryRun ? 'label-dry-run' : 'confirm_delete_title',
      bodyKey: dryRun ? 'confirm_dry_run_body' : 'confirm_delete_body',
      args: <String, Object>{
        'count': targets.length,
        'size': humanBytes(
          targets.fold<int>(0, (int sum, ScanRow row) => sum + row.sizeBytes),
        ),
      },
      dryRun: dryRun,
    );
    publish();
  }

  void dismissConfirm() {
    _confirm = null;
    _confirmAction = null;
    publish();
  }

  Future<void> acceptConfirm() async {
    final Future<void> Function()? action = _confirmAction;
    final ConfirmRequest? request = _confirm;
    _confirm = null;
    _confirmAction = null;
    if (action == null) {
      publish();
      return;
    }
    // Every file verb runs through this hook, so the log records both what was asked and what the
    // engine came back with, without each verb having to remember to report itself.
    final Object? asked = request?.args['count'];
    logActivity(
      ActivityKind.operation,
      ActivityLevel.info,
      Labels.of(
        'log-operation-started',
        args: <String, Object>{
          'action': request == null ? '' : Labels.of(request.titleKey),
          'count': asked ?? 0,
        },
      ),
    );
    _operationAffected = null;
    _operationErrors = null;
    final String? before = _critical;
    await action();
    logActivity(
      ActivityKind.operation,
      _critical == null || _critical == before
          ? ActivityLevel.success
          : ActivityLevel.error,
      statusText,
      affectedCount: _operationAffected,
      errorCount: _operationErrors,
    );
  }

  /// The engine decides the corrected names, so the request carries the live scan settings and the
  /// selection; the dry run answers with the same plan the real run would follow.
  void requestRename() {
    final List<ScanRow> targets = selectedRows;
    if (targets.isEmpty) {
      _setStatus('status_nothing_selected');
      publish();
      return;
    }
    _confirmAction = () => _applyRename(targets);
    _confirm = ConfirmRequest(
      titleKey: dryRun ? 'label-dry-run' : 'confirm_rename_title',
      bodyKey: dryRun ? 'confirm_dry_run_body' : 'confirm_rename_body',
      args: <String, Object>{'count': targets.length},
      dryRun: dryRun,
    );
    publish();
  }

  Future<void> _applyRename(List<ScanRow> targets) async {
    _actionRunning = true;
    _setStatus('status_renaming');
    publish();
    try {
      final RenameOutcome outcome = await engine.renameFiles(
        RenameRequest(
          tool: _tool?.id ?? '',
          scan: buildRequest(),
          paths: targets.map((ScanRow row) => row.path).toList(),
          dryRun: dryRun,
        ),
      );
      _messages = outcome.messages;
      _setStatus(
        dryRun ? 'status_rename_planned' : 'status_renamed',
        args: <String, Object>{
          'count': dryRun ? outcome.planned : outcome.renamed,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      publish();
    }
  }

  void requestMove(String destination, MoveAction action) {
    final List<ScanRow> targets = selectedRows;
    final String folder = destination.trim();
    if (targets.isEmpty || folder.isEmpty) {
      _setStatus('status_move_needs_destination');
      publish();
      return;
    }
    _confirmAction = () => _applyMove(targets, folder, action);
    _confirm = ConfirmRequest(
      titleKey: dryRun ? 'label-dry-run' : 'confirm_move_title',
      bodyKey: dryRun ? 'confirm_dry_run_body' : 'confirm_move_body',
      args: <String, Object>{'count': targets.length, 'destination': folder},
      dryRun: dryRun,
    );
    publish();
  }

  Future<void> _applyMove(
    List<ScanRow> targets,
    String destination,
    MoveAction action,
  ) async {
    _actionRunning = true;
    _setStatus('status_moving');
    publish();
    try {
      final MoveOutcome outcome = await engine.moveFiles(
        MoveRequest(
          paths: targets.map((ScanRow row) => row.path).toList(),
          destination: destination,
          action: action,
          conflict: MoveConflictPolicy.skip,
          preserveStructure: false,
          dryRun: dryRun,
        ),
      );
      _messages = outcome.messages;
      final int done = action == MoveAction.copy
          ? outcome.copied
          : outcome.moved;
      _setStatus(
        dryRun ? 'status_move_planned' : 'status_moved',
        args: <String, Object>{
          'count': dryRun ? outcome.planned : done,
          'destination': destination,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      publish();
    }
  }

  Future<void> _applyDelete(List<ScanRow> targets) async {
    _actionRunning = true;
    _setStatus('status_deleting');
    publish();
    try {
      final DeleteOutcome outcome = await engine.deleteFiles(
        DeleteRequest(
          tool: _tool?.id ?? '',
          rows: targets,
          deleteToTrash: moveToTrash,
          dryRun: dryRun,
        ),
      );
      _operationAffected = outcome.affected;
      _operationErrors = outcome.errors;
      _messages = outcome.log.isEmpty
          ? outcome.messages
          : <String>[
              if (outcome.messages.isNotEmpty) outcome.messages,
              ...outcome.log,
            ].join('\n');
      if (dryRun) {
        _setStatus('status_dry_run_only');
      } else if (outcome.errors > 0) {
        // The engine only reports counts, so nothing is dropped from the table: a row that
        // failed to delete would otherwise vanish while the file is still on disk.
        _setStatus(
          'status_removed_partial',
          args: <String, Object>{
            'removed': outcome.affected,
            'failed': outcome.errors,
          },
        );
        _selected.clear();
      } else {
        _setStatus(
          'status_removed_all',
          args: <String, Object>{'count': outcome.affected},
        );
        final Set<String> removed = targets
            .map((ScanRow row) => row.path)
            .toSet();
        _rows = _rows
            .where((ScanRow row) => !removed.contains(row.path))
            .toList();
        _selected.removeAll(removed);
        _recomputeVisible();
      }
    } catch (error) {
      _critical = error.toString();
      _setStatus('empty-error');
    } finally {
      _actionRunning = false;
      publish();
    }
  }

  /// The scope the export card is set to, and the rows it resolves to right now.
  ExportScope get exportScope => _exportScope;

  List<ScanRow> get exportScopeRows => rowsForScope(
    scope: _exportScope,
    all: _rows,
    visible: _visible,
    selected: _selected,
  );

  void setExportScope(ExportScope scope) {
    if (_exportScope == scope) {
      return;
    }
    _exportScope = scope;
    publish();
  }

  Future<void> exportResults(String path, {String format = 'json'}) async {
    final List<ScanRow> scope = exportScopeRows;
    if (scope.isEmpty) {
      _setStatus('status_nothing_to_export');
      publish();
      return;
    }
    _actionRunning = true;
    publish();
    try {
      final String folder = await engine.exportResults(
        ExportRequest(
          tool: _tool?.id ?? '',
          rows: scope,
          path: path,
          format: format,
          grouped: _tool?.grouped ?? false,
        ),
      );
      _setStatus('status_exported', args: <String, Object>{'folder': folder});
    } catch (error) {
      _setStatus(
        'status_export_failed',
        args: <String, Object>{'error': '$error'},
      );
    } finally {
      _actionRunning = false;
      publish();
    }
  }

  void _setStatus(String key, {Map<String, Object>? args}) {
    _statusKey = key;
    _statusArgs = args ?? const <String, Object>{};
  }

  /// Asks the confirm overlay to plan or apply the set moves; the dry-run switch decides which.
  void requestSimiuApply() {
    final List<SimiuOperation> operations = simiuPlan.operations;
    if (operations.isEmpty) {
      _setStatus('status_simiu_nothing');
      publish();
      return;
    }
    _confirmAction = () => _applySimiu(operations);
    _confirm = ConfirmRequest(
      titleKey: dryRun
          ? 'confirm_simiu_plan_title'
          : 'confirm_simiu_apply_title',
      bodyKey: 'confirm_simiu_body',
      args: <String, Object>{'count': operations.length},
      dryRun: dryRun,
    );
    publish();
  }

  /// Replays the newest undo journal, so a set that went wrong can be walked back.
  void requestSimiuUndo() {
    final String journal = _simiu.journal;
    if (journal.isEmpty) {
      _setStatus('status_simiu_no_journal');
      publish();
      return;
    }
    _confirmAction = () => _undoSimiu(journal);
    _confirm = ConfirmRequest(
      titleKey: 'confirm_simiu_undo_title',
      bodyKey: 'confirm_simiu_undo_body',
      args: <String, Object>{'journal': journal},
      dryRun: dryRun,
    );
    publish();
  }

  Future<void> _applySimiu(List<SimiuOperation> operations) async {
    _actionRunning = true;
    _setStatus('status_simiu_applying');
    publish();
    try {
      final SimiuApplyOutcome outcome = await engine.applySimiuSet(
        SimiuApplyRequest(
          mode: _simiu.mode,
          operations: operations,
          dryRun: dryRun,
        ),
      );
      _messages = outcome.messages;
      if (!dryRun) {
        _simiu.recordJournals(outcome.journals);
      }
      _setStatus(
        dryRun ? 'status_simiu_planned' : 'status_simiu_applied',
        args: <String, Object>{
          'count': dryRun ? outcome.planned : outcome.done,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
      _invalidatePlan();
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      publish();
    }
  }

  Future<void> _undoSimiu(String journal) async {
    _actionRunning = true;
    _setStatus('status_simiu_undoing');
    publish();
    try {
      final SimiuUndoOutcome outcome = await engine.undoSimiuSet(
        SimiuUndoRequest(
          journal: journal,
          cleanEmptyDirectories: _simiu.cleanEmptyDirectories,
          dryRun: dryRun,
        ),
      );
      _messages = outcome.messages;
      _setStatus(
        dryRun ? 'status_simiu_undo_planned' : 'status_simiu_undone',
        args: <String, Object>{
          'count': dryRun ? outcome.planned : outcome.done,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
      _invalidatePlan();
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      publish();
    }
  }

  /// A mutation moves files the plan was built from, so the cached plan must not be reused.
  void _invalidatePlan() {
    _simiu.invalidate();
  }

  OrganizeOptions get organize => _organize;

  void updateOrganize(
    OrganizeOptions Function(OrganizeOptions options) change,
  ) {
    _organize = change(_organize);
    publish();
  }

  /// The reference hides the organize card while Simiu sets are being planned, because both move the
  /// same rows into folders.
  bool get supportsGroupOrganize =>
      _tool?.id == 'similar_images' && !_simiu.enabled;

  OrganizePlan get organizePlan =>
      buildGroupOrganizePlan(boardGroups, _selected, _organize);

  void requestOrganize() {
    final OrganizePlan plan = organizePlan;
    if (plan.items.isEmpty) {
      _setStatus('status_organize_nothing');
      publish();
      return;
    }
    _confirmAction = () => _applyOrganize(plan);
    _confirm = ConfirmRequest(
      titleKey: dryRun
          ? 'confirm_organize_plan_title'
          : 'confirm_organize_title',
      bodyKey: 'confirm_organize_body',
      args: <String, Object>{
        'count': plan.items.length,
        'groups': plan.selectedGroupCount,
        'folders': plan.targetFolderCount,
      },
      dryRun: dryRun,
    );
    publish();
  }

  /// The bridge moves one destination at a time, so each target folder becomes its own call and the
  /// answers are accumulated into one report.
  Future<void> _applyOrganize(OrganizePlan plan) async {
    _actionRunning = true;
    _setStatus('status_organizing');
    publish();
    try {
      final Map<String, List<String>> byDestination = <String, List<String>>{};
      for (final OrganizeItem item in plan.items) {
        byDestination
            .putIfAbsent(item.destination, () => <String>[])
            .add(item.path);
      }
      int moved = 0;
      int planned = 0;
      int skipped = 0;
      int failed = 0;
      final StringBuffer messages = StringBuffer();
      for (final MapEntry<String, List<String>> entry
          in byDestination.entries) {
        final MoveOutcome outcome = await engine.moveFiles(
          MoveRequest(
            paths: entry.value,
            destination: entry.key,
            action: MoveAction.move,
            conflict: MoveConflictPolicy.rename,
            preserveStructure: false,
            dryRun: dryRun,
          ),
        );
        moved += outcome.moved;
        planned += outcome.planned;
        skipped += outcome.skipped;
        failed += outcome.failed;
        if (outcome.messages.isNotEmpty) {
          messages.writeln(outcome.messages);
        }
      }
      _messages = messages.toString().trimRight();
      _setStatus(
        dryRun ? 'status_organize_planned' : 'status_organize_done',
        args: <String, Object>{
          'count': dryRun ? planned : moved,
          'skipped': skipped,
        },
      );
      if (failed > 0) {
        _critical = _messages;
      }
      if (!dryRun) {
        // The rows that moved are no longer where the scan saw them, so the result is rebuilt.
        refreshScan();
      }
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      publish();
    }
  }

  VideoOptions get video => _video;

  /// The engine re-derives which videos are worth the work, so the board only ever asks for the
  /// selection and shows the answer it gets back.
  OptimizeOutcome? get videoOutcome => _videoOutcome;

  bool get supportsVideoOptimize => _tool?.id == 'video_optimizer';

  void updateVideo(VideoOptions Function(VideoOptions options) change) {
    _video = change(_video);
    publish();
  }

  void requestOptimizeVideos() {
    final List<String> paths = selectedRows
        .map((ScanRow row) => row.path)
        .toList();
    if (paths.isEmpty) {
      _setStatus('status_nothing_selected');
      publish();
      return;
    }
    _confirmAction = () => _applyOptimize(paths);
    _confirm = ConfirmRequest(
      titleKey: dryRun ? 'confirm_video_plan_title' : 'confirm_video_title',
      bodyKey: 'confirm_video_body',
      args: <String, Object>{'count': paths.length},
      dryRun: dryRun,
    );
    publish();
  }

  Future<void> _applyOptimize(List<String> paths) async {
    _actionRunning = true;
    _setStatus('status_video_running');
    publish();
    try {
      final bool crop = _video.mode == VideoOptimizeMode.crop;
      final OptimizeOutcome outcome = await engine.optimizeVideos(
        OptimizeRequest(
          scan: buildRequest(),
          paths: paths,
          transcode: crop ? null : _video.transcode,
          crop: crop ? _video.crop : null,
          dryRun: dryRun,
        ),
      );
      _videoOutcome = outcome;
      _messages = outcome.messages;
      _setStatus(
        dryRun ? 'status_video_planned' : 'status_video_done',
        args: <String, Object>{
          'count': dryRun
              ? outcome.planned
              : outcome.transcoded + outcome.cropped,
          'skipped': outcome.skipped,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      publish();
    }
  }

  bool get supportsExifClean => _tool?.id == 'exif_remover';

  /// Writing over the original is the engine's opt-in; the default keeps the source untouched.
  bool get exifOverrideFile => _exifOverrideFile;
  void setExifOverrideFile(bool value) {
    _exifOverrideFile = value;
    publish();
  }

  /// The engine answers with the per-file tag counts, so the result list is only known after a run.
  ExifOutcome? get exifOutcome => _exifOutcome;

  void requestCleanExif() {
    final List<String> paths = selectedRows
        .map((ScanRow row) => row.path)
        .toList();
    if (paths.isEmpty) {
      _setStatus('status_nothing_selected');
      publish();
      return;
    }
    _confirmAction = () => _applyCleanExif(paths);
    _confirm = ConfirmRequest(
      titleKey: dryRun ? 'confirm_exif_plan_title' : 'confirm_exif_title',
      bodyKey: dryRun ? 'confirm_dry_run_body' : 'confirm_exif_body',
      args: <String, Object>{'count': paths.length},
      dryRun: dryRun,
    );
    publish();
  }

  Future<void> _applyCleanExif(List<String> paths) async {
    _actionRunning = true;
    _setStatus('status_exif_cleaning');
    publish();
    try {
      final ExifOutcome outcome = await engine.cleanExif(
        ExifRequest(
          scan: buildRequest(),
          paths: paths,
          overrideFile: _exifOverrideFile,
          dryRun: dryRun,
        ),
      );
      _exifOutcome = outcome;
      _messages = outcome.messages;
      _setStatus(
        dryRun ? 'status_exif_planned' : 'status_exif_done',
        args: <String, Object>{
          'count': dryRun
              ? outcome.planned
              : outcome.stripped + outcome.candidates,
          'skipped': outcome.skipped,
        },
      );
      if (outcome.failed > 0) {
        _critical = outcome.messages;
      }
    } catch (error) {
      _critical = error.toString();
      _setStatus('status_operation_failed');
    } finally {
      _actionRunning = false;
      publish();
    }
  }

  SelectionConfig get assistant => _assistant;
  bool get canUndoSelection => _history.canUndo;
  bool get canRedoSelection => _history.canRedo;
  bool get assistantMessageIsError => _assistantMessageIsError;
  String get assistantMessage => _assistantMessageKey.isEmpty
      ? ''
      : Labels.of(_assistantMessageKey, args: _assistantMessageArgs);

  SelectionStats get assistantStats => selectionStats(boardGroups, _selected);

  void setAssistantConfig(SelectionConfig next) {
    _assistant = next;
    publish();
  }
}
