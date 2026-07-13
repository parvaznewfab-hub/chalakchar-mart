import 'package:flutter/material.dart';

import '../../services/tiktok_publish_service.dart';

/// The mandatory one-tap TikTok consent screen. Every rule below mirrors
/// TikTok's own Content Sharing Guidelines (see the approved architecture
/// doc) — this is not UX polish, it is the compliance boundary:
///   - creator_info is fetched fresh every time this sheet opens
///   - no privacy option is preselected
///   - comment/duet/stitch all start unchecked
///   - the admin must manually choose privacy and manually tap Publish
///   - an unaudited app's forced-private outcome is shown clearly
class TikTokReviewSheet extends StatefulWidget {
  final String jobId;
  final String productId;

  const TikTokReviewSheet({super.key, required this.jobId, required this.productId});

  static Future<bool?> show(BuildContext context, {required String jobId, required String productId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TikTokReviewSheet(jobId: jobId, productId: productId),
    );
  }

  @override
  State<TikTokReviewSheet> createState() => _TikTokReviewSheetState();
}

class _TikTokReviewSheetState extends State<TikTokReviewSheet> {
  static const _staleAfter = Duration(minutes: 3);

  final _service = TikTokPublishService.instance;
  final DateTime _openedAt = DateTime.now();

  bool _loading = true;
  bool _publishing = false;
  String? _loadError;

  TikTokCreatorInfo? _creatorInfo;
  Map<String, dynamic>? _outboxPreview;

  String? _selectedPrivacyLevel;
  bool _allowComment = false;
  bool _allowDuet = false;
  bool _allowStitch = false;

  bool get _isStale => DateTime.now().difference(_openedAt) > _staleAfter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        _service.fetchCreatorInfo(widget.jobId),
        _service.loadOutboxPreview(widget.productId),
      ]);

      if (!mounted) return;
      setState(() {
        _creatorInfo = results[0] as TikTokCreatorInfo;
        _outboxPreview = results[1] as Map<String, dynamic>?;
        // Selections are always reset on (re)load — a stale review can never
        // carry forward a choice made against outdated account settings.
        _selectedPrivacyLevel = null;
        _allowComment = false;
        _allowDuet = false;
        _allowStitch = false;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load TikTok account information. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => _load();

  Future<void> _publish() async {
    final privacyLevel = _selectedPrivacyLevel;
    if (privacyLevel == null || _isStale) return;

    setState(() => _publishing = true);
    try {
      await _service.confirmPublish(
        jobId: widget.jobId,
        privacyLevel: privacyLevel,
        allowComment: _allowComment,
        allowDuet: _allowDuet,
        allowStitch: _allowStitch,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitted to TikTok — waiting for delivery confirmation.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('no longer offered') || text.contains('changed since')) {
      return 'This review is out of date. Please refresh and try again.';
    }
    return 'Could not publish to TikTok right now. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              Row(
                children: const [
                  Icon(Icons.music_note_rounded),
                  SizedBox(width: 8),
                  Text('Review before posting to TikTok', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading) const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
              if (!_loading && _loadError != null) ...[
                Text(_loadError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _load, child: const Text('Retry')),
              ],
              if (!_loading && _loadError == null && _creatorInfo != null) ..._buildContent(),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildContent() {
    final info = _creatorInfo!;
    final outbox = _outboxPreview ?? const {};
    final caption = (outbox['captions'] is Map ? (outbox['captions']['tiktok'] as String?) : null) ??
        (outbox['productName'] as String?) ??
        '';
    final imageUrl = outbox['imageUrl'] as String?;

    return [
      // Connected account — always the identity backing this specific job.
      Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: info.avatarUrl.isNotEmpty ? NetworkImage(info.avatarUrl) : null,
            child: info.avatarUrl.isEmpty ? const Icon(Icons.person_rounded, size: 18) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              info.displayName.isNotEmpty ? 'Posting as @${info.displayName}' : 'Connected TikTok account',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),

      if (info.auditRestricted)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This TikTok app has not passed audit yet. This post will only be visible to the connected account (SELF_ONLY) — nobody else will see it, regardless of the privacy option chosen below.',
                  style: TextStyle(color: Colors.orange.shade900, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 14),

      if (imageUrl != null && imageUrl.isNotEmpty)
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(imageUrl, height: 160, width: double.infinity, fit: BoxFit.cover),
        ),
      const SizedBox(height: 10),
      Text('Caption', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      Text(caption.isEmpty ? '(no caption prepared)' : caption),
      const SizedBox(height: 18),

      Text('Privacy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: _selectedPrivacyLevel,
        hint: const Text('Choose who can see this post'),
        decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: Colors.white),
        items: info.privacyLevelOptions
            .map((level) => DropdownMenuItem(value: level, child: Text(_privacyLabel(level))))
            .toList(),
        onChanged: _isStale ? null : (value) => setState(() => _selectedPrivacyLevel = value),
      ),
      const SizedBox(height: 10),

      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Allow comments'),
        value: _allowComment,
        onChanged: (info.commentDisabled || _isStale) ? null : (value) => setState(() => _allowComment = value),
        subtitle: info.commentDisabled ? const Text('Disabled by the connected account') : null,
      ),
      if (info.mediaType == 'video') ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow Duet'),
          value: _allowDuet,
          onChanged: (info.duetDisabled || _isStale) ? null : (value) => setState(() => _allowDuet = value),
          subtitle: info.duetDisabled ? const Text('Disabled by the connected account') : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow Stitch'),
          value: _allowStitch,
          onChanged: (info.stitchDisabled || _isStale) ? null : (value) => setState(() => _allowStitch = value),
          subtitle: info.stitchDisabled ? const Text('Disabled by the connected account') : null,
        ),
      ],

      const SizedBox(height: 16),
      if (_isStale)
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Icon(Icons.refresh_rounded, size: 18, color: Colors.red.shade700),
              const SizedBox(width: 8),
              const Expanded(child: Text('This review has expired. Refresh to see current account settings before publishing.')),
              TextButton(onPressed: _refresh, child: const Text('Refresh')),
            ],
          ),
        ),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_selectedPrivacyLevel == null || _isStale || _publishing) ? null : _publish,
          child: _publishing
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Publish to TikTok'),
        ),
      ),
    ];
  }

  String _privacyLabel(String level) {
    switch (level) {
      case 'PUBLIC_TO_EVERYONE':
        return 'Public';
      case 'MUTUAL_FOLLOW_FRIENDS':
        return 'Friends';
      case 'FOLLOWER_OF_CREATOR':
        return 'Followers';
      case 'SELF_ONLY':
        return 'Only me';
      default:
        return level;
    }
  }
}
