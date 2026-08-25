import 'package:flutter/material.dart';
import '../../services/admin_api.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/stats_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await AdminApi.get('/admin/stats');
      setState(() {
        _stats = data is Map<String, dynamic> ? data : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      drawer: const AdminDrawer(),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text('Failed to load stats'),
                  const SizedBox(height: 8),
                  Text(_error!, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _loadStats, child: const Text('Retry')),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overview', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      StatsCard(
                        title: 'Total Users',
                        value: '${_stats?['users'] ?? 0}',
                        icon: Icons.people,
                        color: Colors.blue,
                      ),
                      StatsCard(
                        title: 'Live Streams',
                        value: '${_stats?['liveStreams'] ?? 0}',
                        icon: Icons.live_tv,
                        color: Colors.red,
                      ),
                      StatsCard(
                        title: 'Total Streams',
                        value: '${_stats?['streams'] ?? 0}',
                        icon: Icons.video_library,
                        color: Colors.teal,
                      ),
                      StatsCard(
                        title: 'Posts',
                        value: '${_stats?['posts'] ?? 0}',
                        icon: Icons.article,
                        color: Colors.indigo,
                      ),
                      StatsCard(
                        title: 'Pending Reports',
                        value: '${_stats?['pendingReports'] ?? 0}',
                        icon: Icons.report,
                        color: Colors.orange,
                      ),
                      StatsCard(
                        title: 'Revenue (Coins)',
                        value: '${_stats?['totalRevenue'] ?? 0}',
                        icon: Icons.attach_money,
                        color: Colors.purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
