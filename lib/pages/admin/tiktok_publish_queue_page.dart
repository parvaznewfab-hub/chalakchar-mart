import 'package:flutter/material.dart';

import '../../services/tiktok_publish_service.dart';
import '../../widgets/admin/tiktok_review_sheet.dart';

class TikTokPublishQueuePage extends StatelessWidget {
  const TikTokPublishQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = TikTokPublishService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('TikTok Publish Queue')),
      body: StreamBuilder<List<TikTokPublishJob>>(
        stream: service.watchPendingReviewJobs(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load the TikTok publish queue.'));
          }

          final jobs = snapshot.data ?? const [];
          if (jobs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No products are waiting for TikTok review.\nProducts with the TikTok channel enabled will appear here after they are published.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _QueueItem(job: jobs[index]),
          );
        },
      ),
    );
  }
}

class _QueueItem extends StatelessWidget {
  final TikTokPublishJob job;

  const _QueueItem({required this.job});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: TikTokPublishService.instance.loadOutboxPreview(job.productId),
      builder: (context, snapshot) {
        final outbox = snapshot.data;
        final productName = (outbox?['productName'] as String?) ?? job.productId;
        final imageUrl = outbox?['imageUrl'] as String?;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(imageUrl, width: 52, height: 52, fit: BoxFit.cover)
                    : Container(width: 52, height: 52, color: Colors.grey.shade200, child: const Icon(Icons.image_outlined)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Awaiting review', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => TikTokReviewSheet.show(context, jobId: job.jobId, productId: job.productId),
                child: const Text('Review'),
              ),
            ],
          ),
        );
      },
    );
  }
}
