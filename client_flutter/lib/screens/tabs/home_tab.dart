import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/auth_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/content_service.dart';
import '../../widgets/common.dart';
import '../../widgets/media_card.dart';
import '../category_screen.dart';
import '../detail_screen.dart';
import '../login_screen.dart';
import '../player_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.content,
    required this.onOpenSearch,
    required this.onOpenProfile,
  });

  final ContentService content;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenProfile;

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  late final AuthController _auth;
  final PageController _bannerController = PageController(viewportFraction: 0.92);
  final FocusNode _bannerNode = FocusNode(debugLabel: 'home-banner');

  IndexBundle? _index;
  List<WatchHistory> _history = const [];
  bool _loading = true;
  String? _error;
  int _bannerPage = 0;
  int? _bannerFocus;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
    _load();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _bannerNode.dispose();
    super.dispose();
  }

  void focusFirst() {
    if (!mounted) return;
    _bannerNode.requestFocus();
  }

  bool get isBannerFocused => _bannerNode.hasFocus;

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = _index == null;
        _error = null;
      });
    }
    try {
      final index = await widget.content.index();
      final history = await _fetchHistory();
      if (!mounted) return;
      setState(() {
        _index = index;
        _history = history;
        _loading = false;
      });
      _startBannerTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<List<WatchHistory>> _fetchHistory() async {
    if (!_auth.isLoggedIn) return const [];
    try {
      return await widget.content.history(limit: 12);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _refreshHistory() async {
    final history = await _fetchHistory();
    if (!mounted) return;
    setState(() => _history = history);
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    final banners = _index?.banners ?? const <BannerItem>[];
    if (banners.length < 2) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      if (_bannerFocus != null) return;
      final next = (_bannerPage + 1) % banners.length;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _openDetail(int mid, String name) async {
    if (mid <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该推荐暂未绑定片源')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailScreen(mid: mid, initialTitle: name)),
    );
    if (mounted) await _refreshHistory();
  }

  Future<void> _openCategory(CategoryNode node) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CategoryScreen(category: node)),
    );
    if (mounted) await _refreshHistory();
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
    if (mounted) await _refreshHistory();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: LoadingView());
    }
    final index = _index;
    if (index == null) {
      return Scaffold(
        body: ErrorRetryView(message: _error ?? '加载失败', onRetry: _load),
      );
    }
    final isTv = AppConfig.isTv(context);
    final posterWidth = isTv ? 172.0 : 138.0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: isTv ? 28 : 20,
        title: const Text(
          'GoFilm',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: widget.onOpenSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          Consumer<AuthController>(
            builder: (context, auth, _) {
              if (!auth.isLoggedIn) {
                return TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: const Text('登录'),
                );
              }
              return IconButton(
                tooltip: '我的',
                onPressed: widget.onOpenProfile,
                icon: const Icon(Icons.person_outline_rounded),
              );
            },
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (index.banners.isNotEmpty)
              SliverToBoxAdapter(child: _buildBanner(index.banners, isTv)),
            if (_history.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader(title: '继续观看')),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: isTv ? 28 : 20),
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final item = _history[i];
                      final movie = item.movie;
                      if (movie == null) return const SizedBox.shrink();
                      final episode = item.episodeName.isEmpty
                          ? '第${item.episode + 1}集'
                          : item.episodeName;
                      return ContinueCard(
                        movie: movie,
                        subtitle: '$episode · 已看 ${(item.progress * 100).round()}%',
                        progress: item.progress,
                        onTap: () => _continue(item),
                      );
                    },
                  ),
                ),
              ),
            ],
            for (final section in index.sections) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: section.nav.name,
                  actionText: '更多',
                  onAction: () => _openCategory(section.nav),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: posterWidth * 1.5 + 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: isTv ? 28 : 20),
                    itemCount: section.movies.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final movie = section.movies[i];
                      return PosterCard(
                        movie: movie,
                        width: posterWidth,
                        onTap: () => _openDetail(movie.id, movie.name),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner(List<BannerItem> banners, bool isTv) {
    final height = isTv ? 330.0 : 192.0;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _bannerController,
            itemCount: banners.length,
            onPageChanged: (i) => setState(() => _bannerPage = i),
            itemBuilder: (context, i) {
              final banner = banners[i];
              final image = banner.picture.isNotEmpty ? banner.picture : banner.poster;
              return Padding(
                padding: EdgeInsets.fromLTRB(i == 0 ? (isTv ? 28 : 20) : 8, 8, 8, 8),
                child: FocusableActionDetector(
                  autofocus: isTv && i == 0,
                  focusNode: i == 0 ? _bannerNode : null,
                  onShowFocusHighlight: (value) {
                    if (value && _bannerFocus != i) {
                      setState(() => _bannerFocus = i);
                    } else if (!value && _bannerFocus == i) {
                      setState(() => _bannerFocus = null);
                    }
                  },
                  actions: {
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        _openDetail(banner.mid, banner.name);
                        return null;
                      },
                    ),
                  },
                  child: GestureDetector(
                    onTap: () => _openDetail(banner.mid, banner.name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _bannerFocus == i ? AppTheme.accent : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image.isEmpty)
                          Container(color: AppTheme.surfaceHigh)
                        else
                          Image.network(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: AppTheme.surfaceHigh),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xCC0D0F14)],
                              stops: [0.35, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                banner.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: isTv ? 26 : 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (banner.remark.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  banner.remark,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            );
            },
          ),
          if (banners.length > 1)
            Positioned(
              right: 24,
              bottom: 18,
              child: IgnorePointer(
                child: Row(
                  children: [
                    for (var i = 0; i < banners.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(left: 5),
                        width: i == _bannerPage ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _bannerPage ? AppTheme.accent : Colors.white38,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
