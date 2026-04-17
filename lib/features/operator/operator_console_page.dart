import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:template_app_bloc/views/home/printing/lottery_physical_print_renderer.dart';
import 'package:template_app_bloc/views/home/printing/lottery_print_layout.dart';
import 'package:template_app_bloc/views/home/printing/lotto_physical_layout.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_user.dart';
import '../../models/receipt_intake_record.dart';
import '../../repositories/operator_console_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
//import 'dart:html' as html;
// ---------------------------------------------------------------------------
// Page-level state enums
// ---------------------------------------------------------------------------

enum _QueueTab { openQueue, history }

enum _StatusFilter { all, openQueue, matched, failed, needsReview }

enum _SortMode { newestFirst, oldestFirst }

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

class OperatorConsolePage extends StatefulWidget {
  OperatorConsolePage({
    super.key,
    required this.user,
    OperatorConsoleRepository? repository,
  }) : repository = repository ?? OperatorConsoleRepository();

  final AppUser user;
  final OperatorConsoleRepository repository;

  @override
  State<OperatorConsolePage> createState() => _OperatorConsolePageState();
}

class _OperatorConsolePageState extends State<OperatorConsolePage>
    with SingleTickerProviderStateMixin {
  // Tab controller
  late final TabController _tabController;

  // Queue page state
  _QueueTab _selectedTab = _QueueTab.openQueue;
  _StatusFilter _statusFilter = _StatusFilter.all;
  _SortMode _sortMode = _SortMode.newestFirst;

  // Expansion state — keyed by receiptId, not by list index
  final Set<String> _expandedIds = {};
  String? _newestUploadedId;

  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedTab =
              _tabController.index == 0 ? _QueueTab.openQueue : _QueueTab.history;
          // Reset filter when switching tabs so History shows correctly
          _statusFilter = _StatusFilter.all;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121722),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2330),
        foregroundColor: Colors.white,
        title: const Text('Operator Console'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF8A97A8),
          indicatorColor: const Color(0xFF4F8EF7),
          tabs: const [
            Tab(text: 'Open Queue'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildTopSection(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildReceiptQueueTab(isHistory: false),
                _buildReceiptQueueTab(isHistory: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top section: dispatch overview + controls
  // ---------------------------------------------------------------------------

  Widget _buildTopSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildInfoBanner(),
        ),
        const SizedBox(height: 8),
        // Cap dispatch list at 220px — scrollable inside if many items
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: _buildDispatchSection(),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _buildQueueControls(),
        ),
      ],
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2330),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF344156)),
      ),
      child: const Row(
        children: [
          Icon(Icons.admin_panel_settings_outlined,
              color: Color(0xFF4F8EF7), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Operator / Admin Surface — dispatch monitoring and receipt intake only.',
              style: TextStyle(color: Color(0xFFD1D8E3), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDispatchSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C2330),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF344156)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Dispatch Overview',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                  ),
                ),
                Text(
                  'Operator only',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: const Color(0xFFD1D8E3)),
                ),
              ],
            ),
          ),
          Flexible(
            child: StreamBuilder<List<DispatchOverviewItem>>(
              stream: widget.repository.watchDispatchOverview(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorState(
                      text: 'Dispatch Overview failed: ${snapshot.error}');
                }
                final items = snapshot.data ?? const <DispatchOverviewItem>[];
                if (items.isEmpty) {
                  return const _EmptyState(
                      text: 'No submitted tickets waiting for operator handling.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _DispatchListTile(
                    item: items[index],
                    onAdvanceStatus: () =>
                        _advanceDispatchStatus(context, items[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2330),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF344156)),
      ),
      child: Row(
        children: [
          // Upload button
          FilledButton.icon(
            onPressed: _uploading ? null : () => _pickAndUploadReceipt(context),
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file, size: 18),
            label: Text(_uploading ? 'Uploading…' : 'Upload receipt'),
          ),
          const SizedBox(width: 10),
        
      ElevatedButton(
        onPressed: () async {
          await seedTestReceipt();
        },
        child: const Text('SEED RECEIPT'),
      ),
/*           ElevatedButton(
            onPressed: () async {
              final result = await LotteryPhysicalPrintRenderer.renderPdf(
                rows: LotteryPrintLayout.buildDebugSampleRows(),
                layout: const LottoPhysicalLayout(),
                debugMode: true,
              );

              final blob = html.Blob([result.pdfBytes], 'application/pdf');
              final url = html.Url.createObjectUrlFromBlob(blob);

              html.window.open(url, '_blank');
            },
            child: const Text('TEST PRINT'),
          ), */
          // Status filter
          Flexible(
            child: _CompactDropdown<_StatusFilter>(
              value: _statusFilter,
              items: const [
                DropdownMenuItem(
                    value: _StatusFilter.all, child: Text('All statuses')),
                DropdownMenuItem(
                    value: _StatusFilter.openQueue,
                    child: Text('Open queue')),
                DropdownMenuItem(
                    value: _StatusFilter.matched, child: Text('Matched')),
                DropdownMenuItem(
                    value: _StatusFilter.failed, child: Text('Failed')),
                DropdownMenuItem(
                    value: _StatusFilter.needsReview,
                    child: Text('Needs review')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _statusFilter = v);
              },
            ),
          ),
          const SizedBox(width: 8),

          // Sort mode
          Flexible(
            child: _CompactDropdown<_SortMode>(
              value: _sortMode,
              items: const [
                DropdownMenuItem(
                    value: _SortMode.newestFirst,
                    child: Text('Newest first')),
                DropdownMenuItem(
                    value: _SortMode.oldestFirst,
                    child: Text('Oldest first')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _sortMode = v);
              },
            ),
          ),
          const SizedBox(width: 8),

          // Collapse all
          OutlinedButton.icon(
            onPressed: () => setState(() => _expandedIds.clear()),
            icon: const Icon(Icons.unfold_less, size: 16),
            label: const Text('Collapse all'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD1D8E3),
              side: const BorderSide(color: Color(0xFF344156)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Receipt queue tab (shared for Open Queue + History)
  // ---------------------------------------------------------------------------

  Widget _buildReceiptQueueTab({required bool isHistory}) {
    return StreamBuilder<List<ReceiptIntakeRecord>>(
      stream: widget.repository.watchReceiptIntakeQueue(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
              text: 'Receipt queue failed to load: ${snapshot.error}');
        }
        final allItems = snapshot.data ?? const <ReceiptIntakeRecord>[];

        return StreamBuilder<List<DispatchOverviewItem>>(
          stream: widget.repository.watchSubmittedFormCandidates(),
          builder: (context, candidatesSnapshot) {
            final candidates =
                candidatesSnapshot.data ?? const <DispatchOverviewItem>[];

            final filtered =
                _applyFilters(allItems, isHistory: isHistory);

            if (filtered.isEmpty) {
              return const Center(
                child: _EmptyState(text: 'No receipts match the current filter.'),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: filtered.length,
              // Stable keys prevent scroll jumps when items update
              itemBuilder: (context, index) {
                final item = filtered[index];
                final isExpanded = _expandedIds.contains(item.receiptId);
                return Padding(
                  key: ValueKey(item.receiptId),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ReceiptQueueCard(
                    item: item,
                    isExpanded: isExpanded,
                    suggestedCandidates:
                        _suggestedCandidatesForReceipt(item, candidates),
                    onToggleExpand: () => _toggleExpanded(item.receiptId),
                    onMatch: () => _openMatchDialog(context, item),
                    onSuggestedMatch: (candidate) =>
                        _matchReceiptToCandidate(context,
                            receipt: item, candidate: candidate),
                    onUnmatch: item.matchedFormId == null
                        ? null
                        : () => _unmatchReceipt(context, item),
                    onArchive: () => _archiveReceipt(context, item),
                    onDelete: () => _deleteReceipt(context, item),
                    onCopyFingerprint: () =>
                        _copyFingerprint(context, item.receiptFingerprint),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Filtering + sorting
  // ---------------------------------------------------------------------------

  List<ReceiptIntakeRecord> _applyFilters(
    List<ReceiptIntakeRecord> items, {
    required bool isHistory,
  }) {
    // Tab split
    List<ReceiptIntakeRecord> result = items.where((item) {
      final archived = item.isArchived ?? false;
      final matched =
          item.intakeStatus == OperatorConsoleRepository.intakeStatusMatched;

      if (isHistory) {
        return matched || archived;
      } else {
        return !matched && !archived;
      }
    }).toList();

    // Status filter
    if (_statusFilter != _StatusFilter.all) {
      result = result.where((item) {
        switch (_statusFilter) {
          case _StatusFilter.matched:
            return item.intakeStatus ==
                OperatorConsoleRepository.intakeStatusMatched;
          case _StatusFilter.failed:
            return item.receiptParsingStatus ==
                OperatorConsoleRepository.receiptParsingStatusFailed;
          case _StatusFilter.needsReview:
            return item.intakeStatus ==
                OperatorConsoleRepository.intakeStatusNeedsManualReview;
          case _StatusFilter.openQueue:
            return item.intakeStatus ==
                    OperatorConsoleRepository.intakeStatusUploaded ||
                item.intakeStatus ==
                    OperatorConsoleRepository.intakeStatusUnmatched;
          case _StatusFilter.all:
            return true;
        }
      }).toList();
    }

    // Sort
    result.sort((a, b) {
      final aTime = a.uploadedAt ?? DateTime(0);
      final bTime = b.uploadedAt ?? DateTime(0);
      return _sortMode == _SortMode.newestFirst
          ? bTime.compareTo(aTime)
          : aTime.compareTo(bTime);
    });

    return result;
  }

  // ---------------------------------------------------------------------------
  // Expansion management
  // ---------------------------------------------------------------------------

  void _toggleExpanded(String receiptId) {
    setState(() {
      if (_expandedIds.contains(receiptId)) {
        _expandedIds.remove(receiptId);
      } else {
        _expandedIds.add(receiptId);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _pickAndUploadReceipt(BuildContext context) async {
    setState(() => _uploading = true);
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        withData: true,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (result == null || result.files.isEmpty) return;

      final newRecord = await widget.repository.uploadReceipt(
        operator: widget.user,
        file: result.files.single,
      );

      // Auto-expand only the newest upload
      if (newRecord != null) {
        setState(() {
          _newestUploadedId = newRecord.receiptId;
          _expandedIds.add(newRecord.receiptId);
        });
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Receipt uploaded to the intake queue. Matching can happen later.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
  Future<void> seedTestReceipt() async {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No authenticated user.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('forms')
          .doc('test-receipt-3890')
          .set({
        'formId': 'test-receipt-3890',
        'userId': uid,
        'status': 'submitted',
        'submissionType': 'personal',
        'dispatchStatus': 'submitted_to_station',
        'lotteryId': 3890,
        'ticketFingerprint': ' ',
        'ticketFingerprintSource': '3890-2-030809111925-5-021112152326-1',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'submittedAt': FieldValue.serverTimestamp(),
        'printedAt': FieldValue.serverTimestamp(),
        'submittedToStationAt': FieldValue.serverTimestamp(),
        'isComplete': true,
        'isEditable': false,
        'source': 'manual_seed',
        'resultStatus': 'waiting_for_results',
        'checkedAt': null,
        'winAmount': 0,
        'balanceApplied': false,
        'tables': [
          {
            'tableIndex': 1,
            'isComplete': true,
            'regularNumbers': [3, 8, 9, 11, 19, 25],
            'strongNumber': 5,
          },
          {
            'tableIndex': 2,
            'isComplete': true,
            'regularNumbers': [1, 19, 32, 34, 35, 37],
            'strongNumber': 4,
          },
        ],
      }, SetOptions(merge: true));

      debugPrint('[SeedTestReceipt] seeded test-receipt-3890 for uid=$uid');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test receipt form seeded successfully.')),
      );
    } catch (e, st) {
      debugPrint('[SeedTestReceipt] ERROR: $e');
      debugPrint('$st');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seed failed: $e')),
      );
    }
  }
  Future<void> _advanceDispatchStatus(
    BuildContext context,
    DispatchOverviewItem item,
  ) async {
    final String? nextStatus = _nextDispatchStatus(item.dispatchStatus);
    if (nextStatus == null) return;

    try {
      debugPrint(
        '[Dispatch] advance clicked formId=${item.formId} '
        'ownerUserId=${item.formOwnerUserId} '
        'currentStatus=${item.dispatchStatus} '
        'nextStatus=$nextStatus',
      );

      await widget.repository.updateDispatchStatus(
        item: item,
        dispatchStatus: nextStatus,
      );

      debugPrint('[Dispatch] updateDispatchStatus completed successfully');

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Dispatch state updated to ${_dispatchStatusLabel(nextStatus)}.',
          ),
        ),
      );
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[Dispatch] FIREBASE ERROR '
        'code=${e.code} message=${e.message}',
      );
      debugPrint('$st');

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Firebase error: ${e.code} ${e.message ?? ''}',
          ),
        ),
      );
    } catch (error, st) {
      debugPrint('[Dispatch] GENERIC ERROR: $error');
      debugPrint('$st');

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _openMatchDialog(
      BuildContext context, ReceiptIntakeRecord receipt) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ReceiptMatchDialog(
        receipt: receipt,
        repository: widget.repository,
        onMatch: (candidate) => _matchReceiptToCandidate(context,
            receipt: receipt,
            candidate: candidate,
            showSuccessSnackBar: false),
      ),
    );
  }

  Future<void> _matchReceiptToCandidate(
    BuildContext context, {
    required ReceiptIntakeRecord receipt,
    required DispatchOverviewItem candidate,
    bool showSuccessSnackBar = true,
  }) async {
    try {
      await widget.repository.matchReceiptToSubmittedForm(
          receipt: receipt, candidate: candidate);
      if (!context.mounted || !showSuccessSnackBar) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Receipt matched to submitted form ${candidate.formId}.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
      rethrow;
    }
  }

  Future<void> _unmatchReceipt(
      BuildContext context, ReceiptIntakeRecord receipt) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unmatch receipt?'),
            content: const Text(
                'This will remove the receipt link from the submitted form and move it back to unmatched.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Unmatch')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await widget.repository.unmatchReceipt(receipt: receipt);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt unmatched successfully.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _archiveReceipt(
      BuildContext context, ReceiptIntakeRecord receipt) async {
    try {
      await widget.repository.archiveReceipt(receipt: receipt);
      if (!context.mounted) return;
      setState(() => _expandedIds.remove(receipt.receiptId));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt archived.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteReceipt(
      BuildContext context, ReceiptIntakeRecord receipt) async {
    final isMatched =
        receipt.matchedFormId != null;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete receipt?'),
            content: Text(
              isMatched
                  ? 'This receipt is already matched to form ${receipt.matchedFormId}. '
                      'Deleting it will remove the match. This cannot be undone. '
                      'Are you sure?'
                  : 'This will permanently delete the receipt. This cannot be undone.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935)),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await widget.repository.deleteReceipt(receipt: receipt);
      if (!context.mounted) return;
      setState(() => _expandedIds.remove(receipt.receiptId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Receipt deleted.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _copyFingerprint(
      BuildContext context, String? fingerprint) async {
    if (fingerprint == null || fingerprint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No fingerprint available.')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: fingerprint));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Fingerprint copied.')));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String? _nextDispatchStatus(String currentStatus) {
    switch (currentStatus) {
      case OperatorConsoleRepository.dispatchStatusQueuedForPrint:
        return OperatorConsoleRepository.dispatchStatusPrinted;
      case OperatorConsoleRepository.dispatchStatusPrinted:
        return OperatorConsoleRepository.dispatchStatusSubmittedToStation;
      default:
        return null;
    }
  }

  static String _dispatchStatusLabel(String status) {
    switch (status) {
      case OperatorConsoleRepository.dispatchStatusPrinted:
        return 'הודפס';
      case OperatorConsoleRepository.dispatchStatusSubmittedToStation:
        return 'נמסר לתחנה';
      case OperatorConsoleRepository.dispatchStatusQueuedForPrint:
      default:
        return 'ממתין להדפסה';
    }
  }

  List<_SuggestedMatchItem> _suggestedCandidatesForReceipt(
    ReceiptIntakeRecord receipt,
    List<DispatchOverviewItem> candidates,
  ) {
    if (receipt.suggestedFormIds.isEmpty) return const [];
    final byFormId = {
      for (final c in candidates) c.formId: c,
    };
    return receipt.suggestedFormIds
        .map((formId) {
          final candidate = byFormId[formId];
          if (candidate == null) return null;
          return _SuggestedMatchItem(
            candidate: candidate,
            score: receipt.suggestionScores[formId] ?? 0,
            reasons: widget.repository.buildSuggestionReasons(
              receipt: receipt,
              candidate: candidate,
              uploadedAt: receipt.uploadedAt ?? DateTime.now(),
            ),
          );
        })
        .whereType<_SuggestedMatchItem>()
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Receipt queue card (collapsed / expanded)
// ---------------------------------------------------------------------------

class _ReceiptQueueCard extends StatelessWidget {
  const _ReceiptQueueCard({
    required this.item,
    required this.isExpanded,
    required this.suggestedCandidates,
    required this.onToggleExpand,
    required this.onMatch,
    required this.onSuggestedMatch,
    required this.onUnmatch,
    required this.onArchive,
    required this.onDelete,
    required this.onCopyFingerprint,
  });

  final ReceiptIntakeRecord item;
  final bool isExpanded;
  final List<_SuggestedMatchItem> suggestedCandidates;
  final VoidCallback onToggleExpand;
  final VoidCallback onMatch;
  final ValueChanged<DispatchOverviewItem> onSuggestedMatch;
  final VoidCallback? onUnmatch;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onCopyFingerprint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1C2330),
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          // ── Collapsed summary row ──────────────────────────────────────────
          InkWell(
            onTap: onToggleExpand,
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(14))
                : BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF344156)),
                borderRadius: isExpanded
                    ? const BorderRadius.vertical(top: Radius.circular(14))
                    : BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  // Status dot
                  _StatusDot(intakeStatus: item.intakeStatus),
                  const SizedBox(width: 10),

                  // Summary text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        _CollapsedMeta(item: item),
                      ],
                    ),
                  ),

                  // Overflow menu
                  _ItemOverflowMenu(
                    item: item,
                    onMatch: onMatch,
                    onUnmatch: onUnmatch,
                    onArchive: onArchive,
                    onDelete: onDelete,
                    onCopyFingerprint: onCopyFingerprint,
                  ),

                  // Chevron
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more,
                      color: Color(0xFF8A97A8),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded details ───────────────────────────────────────────────
          if (isExpanded)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: const Color(0xFF344156)),
                  right: BorderSide(color: const Color(0xFF344156)),
                  bottom: BorderSide(color: const Color(0xFF344156)),
                ),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: _ExpandedReceiptDetails(
                item: item,
                suggestedCandidates: suggestedCandidates,
                onMatch: onMatch,
                onSuggestedMatch: onSuggestedMatch,
                onUnmatch: onUnmatch,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Collapsed summary meta row
// ---------------------------------------------------------------------------

class _CollapsedMeta extends StatelessWidget {
  const _CollapsedMeta({required this.item});

  final ReceiptIntakeRecord item;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      _formatDate(item.uploadedAt),
      _receiptStatusLabel(item.intakeStatus),
      _parsingLabel(item.receiptParsingStatus),
      if (item.matchedFormId != null) 'Matched' else 'Unmatched',
      if (item.receiptLotteryIdHint != null)
        'Lottery ${item.receiptLotteryIdHint}',
      if (item.receiptTableCountHint != null)
        '${item.receiptTableCountHint} tables',
      item.receiptFingerprint != null ? 'FP ready' : 'FP missing',
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips
          .map(
            (c) => Text(
              c,
              style: const TextStyle(
                color: Color(0xFF8A97A8),
                fontSize: 11,
              ),
            ),
          )
          .expand((w) => [w, const Text('·', style: TextStyle(color: Color(0xFF8A97A8), fontSize: 11))])
          .toList()
          ..removeLast(),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(date.day)}/${p(date.month)}/${date.year} ${p(date.hour)}:${p(date.minute)}';
  }

  static String _receiptStatusLabel(String status) {
    switch (status) {
      case OperatorConsoleRepository.intakeStatusProcessing:
        return 'Processing';
      case OperatorConsoleRepository.intakeStatusMatched:
        return 'Matched';
      case OperatorConsoleRepository.intakeStatusNeedsManualReview:
        return 'Needs review';
      case OperatorConsoleRepository.intakeStatusUnmatched:
        return 'Unmatched';
      default:
        return 'Uploaded';
    }
  }

  static String _parsingLabel(String? status) {
    switch (status) {
      case OperatorConsoleRepository.receiptParsingStatusParsed:
        return 'Parsed';
      case OperatorConsoleRepository.receiptParsingStatusPartial:
        return 'Partial';
      case OperatorConsoleRepository.receiptParsingStatusFailed:
        return 'Parse failed';
      default:
        return 'Pending';
    }
  }
}

// ---------------------------------------------------------------------------
// Status dot indicator
// ---------------------------------------------------------------------------

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.intakeStatus});

  final String intakeStatus;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (intakeStatus) {
      case OperatorConsoleRepository.intakeStatusMatched:
        color = const Color(0xFF4CAF50);
        break;
      case OperatorConsoleRepository.intakeStatusNeedsManualReview:
        color = const Color(0xFFFFA726);
        break;
      case OperatorConsoleRepository.intakeStatusUnmatched:
        color = const Color(0xFFEF5350);
        break;
      default:
        color = const Color(0xFF8A97A8);
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-item overflow menu
// ---------------------------------------------------------------------------

class _ItemOverflowMenu extends StatelessWidget {
  const _ItemOverflowMenu({
    required this.item,
    required this.onMatch,
    required this.onUnmatch,
    required this.onArchive,
    required this.onDelete,
    required this.onCopyFingerprint,
  });

  final ReceiptIntakeRecord item;
  final VoidCallback onMatch;
  final VoidCallback? onUnmatch;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback onCopyFingerprint;

  @override
  Widget build(BuildContext context) {
    final isMatched = item.matchedFormId != null;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Color(0xFF8A97A8), size: 20),
      color: const Color(0xFF232C3A),
      onSelected: (value) {
        switch (value) {
          case 'match':
            onMatch();
            break;
          case 'unmatch':
            onUnmatch?.call();
            break;
          case 'archive':
            onArchive();
            break;
          case 'delete':
            onDelete();
            break;
          case 'open':
            if (item.downloadUrl != null) {
              launchUrl(Uri.parse(item.downloadUrl!));
            }
            break;
          case 'copy_fp':
            onCopyFingerprint();
            break;
        }
      },
      itemBuilder: (context) => [
        if (!isMatched)
          const PopupMenuItem(
            value: 'match',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.link_outlined, size: 18),
              title: Text('Match'),
            ),
          ),
        if (isMatched)
          const PopupMenuItem(
            value: 'unmatch',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.link_off, size: 18),
              title: Text('Unmatch'),
            ),
          ),
        const PopupMenuItem(
          value: 'archive',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.archive_outlined, size: 18),
            title: Text('Archive'),
          ),
        ),
        if (item.downloadUrl != null)
          const PopupMenuItem(
            value: 'open',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.open_in_new, size: 18),
              title: Text('Open file'),
            ),
          ),
        const PopupMenuItem(
          value: 'copy_fp',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.fingerprint, size: 18),
            title: Text('Copy fingerprint'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading:
                const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF5350)),
            title: const Text('Delete',
                style: TextStyle(color: Color(0xFFEF5350))),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Expanded receipt details (existing full view, now shown only when expanded)
// ---------------------------------------------------------------------------

class _ExpandedReceiptDetails extends StatelessWidget {
  const _ExpandedReceiptDetails({
    required this.item,
    required this.suggestedCandidates,
    required this.onMatch,
    required this.onSuggestedMatch,
    required this.onUnmatch,
  });

  final ReceiptIntakeRecord item;
  final List<_SuggestedMatchItem> suggestedCandidates;
  final VoidCallback onMatch;
  final ValueChanged<DispatchOverviewItem> onSuggestedMatch;
  final VoidCallback? onUnmatch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Full detail text
          _detailText(
            'Uploaded: ${_formatDate(item.uploadedAt)}\n'
            'By: ${item.uploadedByDisplayName ?? item.uploadedBy}\n'
            'Type: ${item.contentType}\n'
            'Status: ${_receiptStatusLabel(item.intakeStatus)}\n'
            'Parsing: ${_receiptParsingLabel(item.receiptParsingStatus)}\n'
            'Matched form: ${item.matchedFormId ?? 'Not matched yet'}\n'
            'Lottery ID: ${item.receiptLotteryIdHint?.toString() ?? 'Unknown'}\n'
            'Table count: ${item.receiptTableCountHint?.toString() ?? 'Unknown'}\n'
            'Fingerprint: ${item.receiptFingerprint == null ? 'missing' : 'ready'}\n'
            '${item.matchMessage ?? ''}',
          ),

          // Summary chips
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryChip(
                  label:
                      'Parsed lottery ${item.receiptLotteryIdHint?.toString() ?? 'n/a'}'),
              _SummaryChip(
                  label: 'Ticket type ${item.receiptTicketTypeHint ?? 'unknown'}'),
              _SummaryChip(
                  label:
                      'Parsed tables ${item.receiptTableCountHint?.toString() ?? 'n/a'}'),
              _SummaryChip(
                  label: item.receiptFingerprint == null
                      ? 'Fingerprint missing'
                      : 'Fingerprint ready'),
            ],
          ),

          // Parsing message
          if ((item.receiptParsingMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.receiptParsingMessage!,
              style:
                  const TextStyle(color: Color(0xFFD1D8E3), fontSize: 12),
            ),
          ],

          // Parsing failed banner
          if (item.receiptParsingStatus ==
              OperatorConsoleRepository.receiptParsingStatusFailed) ...[
            const SizedBox(height: 8),
            const Text(
              'Parsing failed — manual match required',
              style: TextStyle(
                  color: Color(0xFFFFB4B4), fontWeight: FontWeight.w700),
            ),
          ],

          // Parsed tables
          if (item.receiptParsedTables.isNotEmpty) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text(
                  'View parsed data',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
                children: item.receiptParsedTables
                    .map(
                      (table) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Table ${table.tableIndex}: ${table.regularNumbers.join(', ')} | strong ${table.strongNumber ?? 'n/a'}',
                            style: const TextStyle(
                              color: Color(0xFFD1D8E3),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],

          // Suggested matches section
          if (item.intakeStatus ==
                  OperatorConsoleRepository.intakeStatusUploaded ||
              item.intakeStatus ==
                  OperatorConsoleRepository.intakeStatusUnmatched) ...[
            const SizedBox(height: 14),
            const Text(
              'Suggested matches',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 10),
            if (suggestedCandidates.isEmpty)
              Text(
                item.suggestionsGeneratedAt == null
                    ? 'Suggestions are being generated.'
                    : 'No strong suggestions found. Manual search is still available.',
                style: const TextStyle(color: Color(0xFFD1D8E3)),
              )
            else
              ...suggestedCandidates.map(
                (suggested) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SuggestedMatchTile(
                    item: suggested,
                    onMatch: () => onSuggestedMatch(suggested.candidate),
                  ),
                ),
              ),
          ],

          // Action buttons
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: item.matchedFormId == null ? onMatch : null,
                icon: const Icon(Icons.link_outlined),
                label: Text(item.matchedFormId == null
                    ? 'Match receipt'
                    : 'Already matched'),
              ),
              if (onUnmatch != null)
                OutlinedButton.icon(
                  onPressed: onUnmatch,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Unmatch'),
                ),
              if (item.matchedFormId != null)
                const Text(
                  'To rematch, unmatch first then select a different form.',
                  style:
                      TextStyle(color: Color(0xFFD1D8E3), fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailText(String text) => Text(
        text,
        style: const TextStyle(color: Color(0xFFD1D8E3), fontSize: 13),
      );

  static String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(date.day)}/${p(date.month)}/${date.year} ${p(date.hour)}:${p(date.minute)}';
  }

  static String _receiptStatusLabel(String status) {
    switch (status) {
      case OperatorConsoleRepository.intakeStatusProcessing:
        return 'בעיבוד';
      case OperatorConsoleRepository.intakeStatusMatched:
        return 'הותאם';
      case OperatorConsoleRepository.intakeStatusNeedsManualReview:
        return 'דורש בדיקה ידנית';
      case OperatorConsoleRepository.intakeStatusUnmatched:
        return 'ללא התאמה';
      default:
        return 'הועלה';
    }
  }

  static String _receiptParsingLabel(String? status) {
    switch (status) {
      case OperatorConsoleRepository.receiptParsingStatusParsed:
        return 'parsed';
      case OperatorConsoleRepository.receiptParsingStatusPartial:
        return 'partial';
      case OperatorConsoleRepository.receiptParsingStatusFailed:
        return 'failed';
      default:
        return 'pending';
    }
  }
}

// ---------------------------------------------------------------------------
// Compact dropdown helper
// ---------------------------------------------------------------------------

class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF232C3A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF344156)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: const Color(0xFF232C3A),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          iconEnabledColor: const Color(0xFF8A97A8),
          isDense: true,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets (unchanged from original)
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2330),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF344156)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DispatchListTile extends StatelessWidget {
  const _DispatchListTile({
    required this.item,
    required this.onAdvanceStatus,
  });

  final DispatchOverviewItem item;
  final VoidCallback? onAdvanceStatus;

  @override
  Widget build(BuildContext context) {
    final bool canAdvance = onAdvanceStatus != null &&
        item.dispatchStatus !=
            OperatorConsoleRepository.dispatchStatusSubmittedToStation;

    return Material(
      color: const Color(0xFF232C3A),
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          item.groupName ?? 'Submitted ticket ${item.formId}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'Creator: ${item.creatorName ?? item.creatorUserId}\n'
          'Lottery ID: ${item.lotteryId ?? 'Unknown'}\n'
          'Submitted: ${_formatDate(item.submittedAt)}\n'
          'Dispatch: ${_dispatchStatusLabel(item.dispatchStatus)}\n'
          'Receipt: ${item.stationReceiptIntakeId == null ? 'Not attached' : 'Attached'}',
          style: const TextStyle(color: Color(0xFFD1D8E3)),
        ),
        trailing: SizedBox(
          width: 130,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.stationReceiptUrl != null)
                IconButton(
                  tooltip: 'Open attached receipt',
                  icon: const Icon(Icons.receipt_long_outlined),
                  onPressed: () =>
                      launchUrl(Uri.parse(item.stationReceiptUrl!)),
                ),
              if (canAdvance)
                Flexible(
                  child: TextButton(
                    onPressed: onAdvanceStatus,
                    child: Text(
                      item.dispatchStatus ==
                              OperatorConsoleRepository
                                  .dispatchStatusQueuedForPrint
                          ? 'סמן כהודפס'
                          : 'סמן כנמסר לתחנה',
                    ),
                  ),
                )
              else
                const Icon(Icons.check_circle_outline),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(date.day)}/${p(date.month)}/${date.year} ${p(date.hour)}:${p(date.minute)}';
  }

  static String _dispatchStatusLabel(String status) {
    switch (status) {
      case OperatorConsoleRepository.dispatchStatusPrinted:
        return 'הודפס';
      case OperatorConsoleRepository.dispatchStatusSubmittedToStation:
        return 'נמסר לתחנה';
      default:
        return 'ממתין להדפסה';
    }
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF18202D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF344156)),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SuggestedMatchTile extends StatelessWidget {
  const _SuggestedMatchTile({
    required this.item,
    required this.onMatch,
  });

  final _SuggestedMatchItem item;
  final VoidCallback onMatch;

  @override
  Widget build(BuildContext context) {
    final candidate = item.candidate;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF18202D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF344156)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  candidate.groupName ?? 'Submitted form ${candidate.formId}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2F3D52),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Score ${item.score.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'formId: ${candidate.formId}\n'
            'creator: ${candidate.creatorName ?? candidate.creatorUserId}\n'
            'lotteryId: ${candidate.lotteryId ?? 'Unknown'}\n'
            'tables: ${candidate.tableCount}\n'
            'fingerprint: ${_shortFingerprint(candidate.ticketFingerprint)}',
            style: const TextStyle(color: Color(0xFFD1D8E3)),
          ),
          if (item.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.reasons
                  .map(
                    (r) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F3D52),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(r,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onMatch,
            icon: const Icon(Icons.recommend_outlined),
            label: const Text('Match (recommended)'),
          ),
        ],
      ),
    );
  }

  String _shortFingerprint(String? fingerprint) {
    if (fingerprint == null || fingerprint.isEmpty) return 'n/a';
    if (fingerprint.length <= 12) return fingerprint;
    return '${fingerprint.substring(0, 8)}…${fingerprint.substring(fingerprint.length - 4)}';
  }
}

// ---------------------------------------------------------------------------
// Match dialog (unchanged logic)
// ---------------------------------------------------------------------------

class _ReceiptMatchDialog extends StatefulWidget {
  const _ReceiptMatchDialog({
    required this.receipt,
    required this.repository,
    required this.onMatch,
  });

  final ReceiptIntakeRecord receipt;
  final OperatorConsoleRepository repository;
  final Future<void> Function(DispatchOverviewItem candidate) onMatch;

  @override
  State<_ReceiptMatchDialog> createState() => _ReceiptMatchDialogState();
}

class _ReceiptMatchDialogState extends State<_ReceiptMatchDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _dispatchFilter = 'all';
  bool _submitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Match receipt to submitted form'),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Receipt: ${widget.receipt.fileName}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText:
                    'Search by formId, lotteryId, creator, group, or fingerprint',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _dispatchFilter,
              onChanged: (value) {
                if (value != null) setState(() => _dispatchFilter = value);
              },
              items: const [
                DropdownMenuItem(
                    value: 'all', child: Text('All dispatch states')),
                DropdownMenuItem(
                  value: OperatorConsoleRepository.dispatchStatusQueuedForPrint,
                  child: Text('Queued for print'),
                ),
                DropdownMenuItem(
                  value: OperatorConsoleRepository.dispatchStatusPrinted,
                  child: Text('Printed'),
                ),
                DropdownMenuItem(
                  value: OperatorConsoleRepository
                      .dispatchStatusSubmittedToStation,
                  child: Text('Submitted to station'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: StreamBuilder<List<DispatchOverviewItem>>(
                stream: widget.repository.watchSubmittedFormCandidates(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorState(
                        text:
                            'Candidate forms failed to load: ${snapshot.error}');
                  }
                  final items =
                      _filterCandidates(snapshot.data ?? const []);
                  if (items.isEmpty) {
                    return const _EmptyState(
                        text:
                            'No submitted form candidates match the current search.');
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Material(
                        color: const Color(0xFFF3F5F9),
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          title: Text(
                            item.groupName ??
                                'Submitted form ${item.formId}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            'formId: ${item.formId}\n'
                            'creator: ${item.creatorName ?? item.creatorUserId}\n'
                            'lotteryId: ${item.lotteryId ?? 'Unknown'}\n'
                            'tables: ${item.tableCount}\n'
                            'fingerprint: ${_shortFingerprint(item.ticketFingerprint)}'
                            '${item.stationReceiptIntakeId == null ? '' : '\nreceipt: already attached'}',
                          ),
                          trailing: FilledButton(
                            onPressed: _submitting
                                ? null
                                : () => _submitMatch(context, item),
                            child: Text(
                                _submitting ? 'Matching…' : 'Match'),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  List<DispatchOverviewItem> _filterCandidates(
      List<DispatchOverviewItem> items) {
    final query = _searchController.text.trim().toLowerCase();
    return items.where((item) {
      final dispatchMatches =
          _dispatchFilter == 'all' || item.dispatchStatus == _dispatchFilter;
      if (!dispatchMatches) return false;
      if (query.isEmpty) return true;
      final haystack = [
        item.formId,
        item.creatorUserId,
        item.creatorName,
        item.groupName,
        item.groupId,
        item.ticketFingerprint,
        item.lotteryId?.toString(),
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _submitMatch(
      BuildContext context, DispatchOverviewItem candidate) async {
    setState(() => _submitting = true);
    try {
      await widget.onMatch(candidate);
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _shortFingerprint(String? fingerprint) {
    if (fingerprint == null || fingerprint.isEmpty) return 'n/a';
    if (fingerprint.length <= 12) return fingerprint;
    return '${fingerprint.substring(0, 8)}…${fingerprint.substring(fingerprint.length - 4)}';
  }
}

// ---------------------------------------------------------------------------
// Empty / error states
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(text, textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8A97A8))),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Color(0xFFFFB4B4), fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting data class
// ---------------------------------------------------------------------------

class _SuggestedMatchItem {
  const _SuggestedMatchItem({
    required this.candidate,
    required this.score,
    required this.reasons,
  });

  final DispatchOverviewItem candidate;
  final double score;
  final List<String> reasons;
}