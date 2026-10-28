import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/auth_controller.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/content_service.dart';
import '../widgets/common.dart';
import '../widgets/media_card.dart';
import 'detail_screen.dart';
import 'login_screen.dart';
import 'player_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的影视'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '观看记录'),
              Tab(text: '我的收藏'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _HistoryView(),
            _FavoritesView(),
          ],
        ),
      ),
    );
  }
}

class _HistoryView extends StatefulWidget {
  const _HistoryView();

  @override
  State<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<_HistoryView> {
  late final AuthController _auth;
  late final ContentService _content;

  List<WatchHistory>? _items;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
    _content = ContentService(_auth.api);
    _load();
  }

  Future<void> _load() async {
    if (!_auth.isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = _items == null;
        _error = null;
      });
    }
    try {
      final items = await _content.history(limit: 50);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _continue(WatchHistory item) async {
    final movie = item.movie;
    if (movie == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mid: item.mid,
          title: movie.name,
          playFrom: item.sourceId,
          episode: item.episode,
          initialPosition: item.position,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isLoggedIn) return const _LoginPrompt();
    if (_loading) return const LoadingView();
    final items = _items;
    if (items == null) {
      return ErrorRetryView(message: _error ?? '加载失败', onRetry: _load);
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 160),
            EmptyView(message: '还没有观看记录', icon: Icons.history_rounded),
          ],
        ),
      );
    }
    final isTv = AppConfig.isTv(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isTv ? 28 : 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          final movie = item.movie;
          if (movie == null) return const SizedBox.shrink();
          return _HistoryTile(
            item: item,
            movie: movie,
            onTap: () => _continue(item),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.movie,
    required this.onTap,
  });

  final WatchHistory item;
  final MovieBasic movie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final episode = item.episodeName.isEmpty ? '第${item.episode + 1}集' : item.episodeName;
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 72,
                  height: 104,
                  child: movie.picture.isEmpty
                      ? Container(color: AppTheme.surfaceHigh)
                      : Image.network(
                          movie.picture,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: AppTheme.surfaceHigh),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      episode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: item.progress.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: const Color(0xFF2B3140),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '已看 ${(item.progress * 100).round()}% · ${_formatTime(item.updatedAt)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_circle_outline_rounded, color: AppTheme.accent, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesView extends StatefulWidget {
  const _FavoritesView();

  @override
  State<_FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<_FavoritesView> {
  late final AuthController _auth;
  late final ContentService _content;

  List<FavoriteItem>? _items;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
    _content = ContentService(_auth.api);
    _load();
  }

  Future<void> _load() async {
    if (!_auth.isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = _items == null;
        _error = null;
      });
    }
    try {
      final items = await _content.favorites(limit: 200);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _remove(FavoriteItem item) async {
    final movie = item.movie;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('将「${movie?.name ?? '该影片'}」从收藏中移除？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _content.setFavorite(item.mid, favorite: false);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isLoggedIn) return const _LoginPrompt();
    if (_loading) return const LoadingView();
    final items = _items;
    if (items == null) {
      return ErrorRetryView(message: _error ?? '加载失败', onRetry: _load);
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 160),
            EmptyView(message: '还没有收藏影片', icon: Icons.favorite_border_rounded),
          ],
        ),
      );
    }
    final isTv = AppConfig.isTv(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                '长按海报可取消收藏',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(isTv ? 28 : 16, 8, isTv ? 28 : 16, 28),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isTv ? 190 : 150,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: isTv ? 0.54 : 0.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = items[i];
                  final movie = item.movie;
                  if (movie == null) return const SizedBox.shrink();
                  return GestureDetector(
                    onLongPress: () => _remove(item),
                    child: PosterCard(
                      movie: movie,
                      fillWidth: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DetailScreen(
                            mid: movie.id,
                            initialTitle: movie.name,
                          ),
                        ),
                      ).then((_) => _load()),
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            const Text('登录后查看观看记录与收藏'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: const Text('登录 / 注册'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(int milliseconds) {
  if (milliseconds <= 0) return '';
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return '今天 ${two(time.hour)}:${two(time.minute)}';
  }
  if (time.year == now.year) {
    return '${time.month}月${time.day}日';
  }
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}
