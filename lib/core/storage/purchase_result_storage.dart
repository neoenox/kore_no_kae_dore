// lib/core/storage/purchase_result_storage.dart
// 購入結果のJSONファイル保存/読込
// 履歴一覧表示に使う
// 関連: purchase_result.dart, history_screen.dart

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/purchase_result.dart';

typedef DocumentsDirectoryProvider = Future<Directory> Function();

class PurchaseResultStorageReadException implements Exception {
  const PurchaseResultStorageReadException({
    required this.fileName,
    required this.cause,
    this.partialResults = const <PurchaseResult>[],
  });

  final String fileName;
  final Object cause;
  final List<PurchaseResult> partialResults;

  @override
  String toString() => 'Failed to read purchase result file "$fileName": $cause';
}

class PurchaseResultStorage {
  PurchaseResultStorage({
    DocumentsDirectoryProvider? documentsDirectoryProvider,
  }) : _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  final DocumentsDirectoryProvider _documentsDirectoryProvider;

  Future<String> get _localPath async {
    final directory = await _documentsDirectoryProvider();
    final resultsDir = Directory('${directory.path}/results');
    if (!await resultsDir.exists()) {
      await resultsDir.create(recursive: true);
    }
    return resultsDir.path;
  }

  Future<void> saveResult(PurchaseResult result) async {
    final path = await _localPath;
    final file = File('$path/${result.id}.json');
    final encoded = jsonEncode(result.toJson());

    if (await file.exists()) {
      final existing = await file.readAsString();
      if (existing == encoded) return;
      throw StateError('Purchase result id already exists: ${result.id}');
    }

    final temp = File('$path/.${result.id}.json.tmp');
    try {
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  Future<PurchaseResult> _readResult(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      return PurchaseResult.fromJson(decoded);
    } catch (error) {
      throw PurchaseResultStorageReadException(
        fileName: file.uri.pathSegments.last,
        cause: error,
      );
    }
  }

  Future<PurchaseResult?> loadResult(String id) async {
    final path = await _localPath;
    final file = File('$path/$id.json');
    if (!await file.exists()) return null;
    return _readResult(file);
  }

  Future<PurchaseResult?> loadResultForSession(String sessionId) async {
    final results = await listResults();
    for (final result in results) {
      if (result.sessionId == sessionId) return result;
    }
    return null;
  }

  Future<List<PurchaseResult>> listResults() async {
    final path = await _localPath;
    final dir = Directory(path);
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    final results = <PurchaseResult>[];
    for (final file in files) {
      try {
        results.add(await _readResult(file));
      } on PurchaseResultStorageReadException catch (error) {
        throw PurchaseResultStorageReadException(
          fileName: error.fileName,
          cause: error.cause,
          partialResults: List<PurchaseResult>.unmodifiable(results),
        );
      }
    }

    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }
}
