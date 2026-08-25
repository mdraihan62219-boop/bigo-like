import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';
import '../../utils/api_error.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<dynamic> _results = [];
  bool _searching = false;

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final response = await ApiService.get('/users/search', queryParameters: {'q': q});
      setState(() {
        _results = response.data['data'] ?? [];
        _searching = false;
      });
    } catch (e) {
      setState(() => _searching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: ${friendlyError(e)}')),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search users...', border: InputBorder.none),
          onSubmitted: _search,
        ),
      ),
      body: _searching
        ? const Center(child: CircularProgressIndicator())
        : _results.isEmpty
          ? const Center(child: Text('Type and press enter to search'))
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final user = _results[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: CachedNetworkImageProvider(
                      user['avatar_url'] ?? 'https://via.placeholder.com/50',
                    ),
                  ),
                  title: Text(user['display_name'] ?? user['username'] ?? 'Unknown'),
                  subtitle: Text('@${user['username'] ?? ''}'),
                );
              },
            ),
    );
  }
}
