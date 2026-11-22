// lib/features/history/history_screen.dart
// 履歴画面：過去の購入結果を一覧表示
// 結果をタップすると詳細を再表示できる
// 関連: purchase_result_storage.dart, home_screen.dart

import 'package:flutter/material.dart';

import '../../core/models/purchase_result.dart';
import '../../core/storage/purchase_result_storage.dart';
import '../../shared/widgets/copyable_text.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.storage});

  final PurchaseResultStorage? storage;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final _storage = widget.storage ?? PurchaseResultStorage();
  List<PurchaseResult> _results = [];
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final results = await _storage.listResults();
      if (!mounted) return;
      setState(() {
        _results = results;
        _loadError = null;
        _loading = false;
      });
    } on PurchaseResultStorageReadException catch (error) {
      if (!mounted) return;
      setState(() {
        _results = error.partialResults;
        _loadError =
            '履歴ファイル「${error.fileName}」を読み込めませんでした。保存ファイルは削除していません。';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _loadError = '履歴を読み込めませんでした。保存ファイルは削除していません。';
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}'
        '/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('履歴')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _loadError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: _results.isEmpty
                      ? Center(
                          child: Text(
                            _loadError == null
                                ? '履歴がありません'
                                : '読み込める履歴がありません',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final result = _results[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ExpansionTile(
                                  title: Text(
                                    result.candidateTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _formatDate(result.createdAt),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      result.confidenceLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[700],
                                      ),
                                    ),
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (result.searchKeywords.isNotEmpty) ...[
                                            const Text(
                                              '検索ワード',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            ...result.searchKeywords.map(
                                              (keyword) => Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 4,
                                                ),
                                                child: CopyableText(
                                                  text: keyword,
                                                ),
                                              ),
                                            ),
                                            const Divider(),
                                          ],
                                          if (result.checkBeforeBuy.isNotEmpty) ...[
                                            const Text(
                                              '買う前チェック',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            ...result.checkBeforeBuy.map(
                                              (check) => Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 4,
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('・'),
                                                    Expanded(
                                                      child: Text(check),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const Divider(),
                                          ],
                                          const Text(
                                            '店員用要約',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            result.shopStaffSummary,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
