// lib/core/storage/session_storage.dart
// セッション情報のJSONファイル保存/読込
// Phase 1はJSONファイルベース。将来SQLiteに移行可能
// 関連: capture_session.dart, evidence_state.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/capture_session.dart';
import '../models/evidence_state.dart';

typedef DocumentsDirectoryProvider = Future<Directory> Function();
typedef BeforeAtomicCommit = Future<void> Function(
  File tempFile,
  File targetFile,
);

/// Session と Evidence はそれぞれ独立したファイルとして原子的に置換する。
///
/// 2ファイルを跨ぐトランザクションではないため、2回の保存の片方だけが失敗した場合は
/// 成功した側だけが新しい版になる。ただし各ファイルは旧版か新版のどちらかであり、
/// 途中まで書かれたJSONを正常データとして公開しない。
class SessionStorage {
  SessionStorage({
    DocumentsDirectoryProvider? documentsDirectoryProvider,
    this.beforeAtomicCommit,
  })  : _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final DocumentsDirectoryProvider _documentsDirectoryProvider;
  @visibleForTesting
  final BeforeAtomicCommit? beforeAtomicCommit;

  Future<String> get _localPath async {
    final directory = await _documentsDirectoryProvider();
    final sessionsDir = Directory('${directory.path}/sessions');
    if (!await sessionsDir.exists()) {
      await sessionsDir.create(recursive: true);
    }
    return sessionsDir.path;
  }

  Future<void> _writeJsonAtomically(
    File target,
    Map<String, dynamic> json,
  ) async {
    final temp = File(
      '${target.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.writeAsString(jsonEncode(json), flush: true);
      await beforeAtomicCommit?.call(temp, target);
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  Future<void> _quarantineCorrupt(File file) async {
    if (!await file.exists()) return;
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    var quarantine = File('${file.path}.corrupt.$stamp');
    var suffix = 0;
    while (await quarantine.exists()) {
      suffix += 1;
      quarantine = File('${file.path}.corrupt.$stamp.$suffix');
    }
    try {
      await file.rename(quarantine.path);
      debugPrint(
        'SessionStorage: quarantined corrupt JSON to ${quarantine.path}',
      );
    } catch (e) {
      debugPrint('SessionStorage: failed to quarantine ${file.path}: $e');
    }
  }

  Future<T?> _loadJson<T>(
    File file,
    String operation,
    T Function(Map<String, dynamic>) decode,
  ) async {
    if (!await file.exists()) return null;

    late final String raw;
    try {
      raw = await file.readAsString();
    } catch (e) {
      debugPrint('SessionStorage.$operation: read failed: $e');
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON root must be an object');
      }
      return decode(decoded);
    } catch (e) {
      debugPrint('SessionStorage.$operation: corrupt JSON: $e');
      await _quarantineCorrupt(file);
      return null;
    }
  }

  Future<void> saveSession(CaptureSession session) async {
    final path = await _localPath;
    final file = File('$path/${session.id}.json');
    await _writeJsonAtomically(file, session.toJson());
  }

  Future<void> saveEvidence(EvidenceState evidence) async {
    final path = await _localPath;
    final file = File('$path/${evidence.sessionId}_evidence.json');
    await _writeJsonAtomically(file, evidence.toJson());
  }

  Future<CaptureSession?> loadSession(String id) async {
    final path = await _localPath;
    final file = File('$path/$id.json');
    return _loadJson(
      file,
      'loadSession',
      CaptureSession.fromJson,
    );
  }

  Future<EvidenceState?> loadEvidence(String sessionId) async {
    final path = await _localPath;
    final file = File('$path/${sessionId}_evidence.json');
    return _loadJson(
      file,
      'loadEvidence',
      EvidenceState.fromJson,
    );
  }

  Future<List<CaptureSession>> listSessions() async {
    try {
      final path = await _localPath;
      final dir = Directory(path);
      if (!await dir.exists()) return [];
      final files = await dir
          .list()
          .where(
            (e) =>
                e is File &&
                e.path.endsWith('.json') &&
                !e.path.endsWith('_evidence.json'),
          )
          .cast<File>()
          .toList();
      final sessions = <CaptureSession>[];
      for (final file in files) {
        final session = await _loadJson(
          file,
          'listSessions',
          CaptureSession.fromJson,
        );
        if (session != null) {
          sessions.add(session);
        }
      }
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (e) {
      debugPrint('SessionStorage.listSessions: $e');
      return [];
    }
  }

  /// 最新の進行中セッションを取得する（なければnull）
  Future<CaptureSession?> findLatestInProgress() async {
    final sessions = await listSessions();
    try {
      return sessions.firstWhere((s) => s.status == 'in_progress');
    } catch (e) {
      debugPrint('SessionStorage.findLatestInProgress: $e');
      return null;
    }
  }

  Future<void> deleteSession(String id) async {
    try {
      final path = await _localPath;
      final sessionFile = File('$path/$id.json');
      if (await sessionFile.exists()) {
        await sessionFile.delete();
      }
      final evidenceFile = File('$path/${id}_evidence.json');
      if (await evidenceFile.exists()) {
        await evidenceFile.delete();
      }
    } catch (e) {
      debugPrint('SessionStorage.deleteSession: $e');
    }
  }
}
