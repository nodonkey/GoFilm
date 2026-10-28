import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/auth_controller.dart' show friendlyError;
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';
import 'media_card.dart';

class PagedMovieGrid extends StatefulWidget {
  const PagedMovieGrid({
    super.key,
    required this.loader,
    required this.onTap,
    this.emptyMessage = '暂无内容',
    this.autofocusFirst = false,
  });

  final Future<MoviePage> Function(int page) loader;
  final void Function(MovieBasic movie) onTap;
  final String emptyMessage;
  final bool autofocusFirst;

  @override
  State<PagedMovieGrid> createState() => _PagedMovieGridState();
}

class _PagedMovieGridState extends State<PagedMovieGrid> {
  final ScrollController _scroll = ScrollController();
  final List<MovieBasic> _items = [];

  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 400) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore({bool retry = false}) async {
    if (_loading || !_hasMore) return;
    if (_error != null && !retry) return;
    if (mounted) setState(() => _loading = true);
    try {
      final result = await widget.loader(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.list);
        _page = result.page.current > 0 ? result.page.current : _page + 1;
        _hasMore = result.page.hasMore;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) return const LoadingView();
    if (_error != null && _items.isEmpty) {
      return ErrorRetryView(message: _error!, onRetry: _reload);
    }
    if (_items.isEmpty) {
      return EmptyView(message: widget.emptyMessage);
    }
    final isTv = AppConfig.isTv(context);
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(isTv ? 28 : 16, 8, isTv ? 28 : 16, 16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isTv ? 200 : 160,
                mainAxisSpacing: isTv ? 22 : 16,
                crossAxisSpacing: 12,
                childAspectRatio: isTv ? 0.54 : 0.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final movie = _items[index];
                  return PosterCard(
                    movie: movie,
                    fillWidth: true,
                    autofocus: widget.autofocusFirst && index == 0,
                    onTap: () => widget.onTap(movie),
                  );
                },
                childCount: _items.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Center(child: _footer()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    if (_loading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_error != null) {
      return TextButton(
        onPressed: () => _loadMore(retry: true),
        child: const Text('加载失败，点击重试'),
      );
    }
    if (!_hasMore && _items.isNotEmpty) {
      return const Text('没有更多了', style: TextStyle(color: AppTheme.textMuted, fontSize: 12));
    }
    return const SizedBox.shrink();
  }
}
