import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/auth_controller.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/content_service.dart';
import '../widgets/common.dart';
import '../widgets/media_card.dart';
import 'login_screen.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.mid, this.initialTitle});

  final int mid;
  final String? initialTitle;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final AuthController _auth;
  late final ContentService _content;

  DetailBundle? _bundle;
  WatchHistory? _resume;
  bool _favorite = false;
  bool _loading = true;
  bool _favBusy = false;
  bool _descExpanded = false;
  String? _error;
  final Set<String> _expandedSources = {};

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
    _content = ContentService(_auth.api);
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = _bundle == null;
        _error = null;
      });
    }
    try {
      final bundle = await _content.detail(widget.mid);
      var favorite = false;
      WatchHistory? resume;
      if (_auth.isLoggedIn) {
        try {
          final favorites = await _content.favorites(limit: 200);
          favorite = favorites.any((e) => e.mid == widget.mid);
        } catch (_) {
          // 收藏状态失败不影响详情展示
        }
        try {
          final history = await _content.history(limit: 100);
          for (final item in history) {
            if (item.mid == widget.mid) {
              resume = item;
              break;
            }
          }
        } catch (_) {
          // 进度获取失败时从第一集开始
        }
      }
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _favorite = favorite;
        _resume = resume;
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

  PlaySource? _sourceById(MovieDetail detail, String id) {
    for (final source in detail.sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  PlaySource? _firstPlayable(MovieDetail detail) {
    for (final source in detail.sources) {
      if (source.items.isNotEmpty) return source;
    }
    return null;
  }

  Future<void> _play({PlaySource? source, int episode = 0, int position = 0}) async {
    final detail = _bundle?.detail;
    if (detail == null) return;
    final target = source ?? _firstPlayable(detail);
    if (target == null || target.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可播放资源')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mid: detail.mid,
          title: detail.name,
          playFrom: target.id,
          episode: episode,
          initialPosition: position,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _playResume() async {
    final detail = _bundle?.detail;
    if (detail == null) return;
    final resume = _resume;
    if (resume != null) {
      final source = _sourceById(detail, resume.sourceId);
      if (source != null && resume.episode >= 0 && resume.episode < source.items.length) {
        return _play(source: source, episode: resume.episode, position: resume.position);
      }
    }
    return _play();
  }

  Future<void> _toggleFavorite() async {
    if (!_auth.isLoggedIn) {
      _promptLogin();
      return;
    }
    setState(() => _favBusy = true);
    try {
      await _content.setFavorite(widget.mid, favorite: !_favorite);
      if (!mounted) return;
      setState(() => _favorite = !_favorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_favorite ? '已加入收藏' : '已取消收藏')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  void _promptLogin() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('登录后可以收藏影片'),
        action: SnackBarAction(
          label: '去登录',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.initialTitle ?? '影片详情')),
        body: const LoadingView(),
      );
    }
    if (bundle == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.initialTitle ?? '影片详情')),
        body: ErrorRetryView(message: _error ?? '加载失败', onRetry: _load),
      );
    }

    final detail = bundle.detail;
    final isTv = AppConfig.isTv(context);
    final playable = _firstPlayable(detail);
    final maxWidth = isTv ? 1100.0 : 720.0;
    final relatedWidth = isTv ? 172.0 : 138.0;
    final resumeLabel = _resume == null
        ? '立即播放'
        : '继续观看 · ${_episodeLabel(_resume!)}';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: isTv ? 440 : 350,
              backgroundColor: AppTheme.background,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 14),
                title: Text(
                  detail.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isTv ? 28 : 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                background: _HeroBackdrop(detail: detail),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(isTv ? 28 : 20, 12, isTv ? 28 : 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _info(detail),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: ElevatedButton.icon(
                                autofocus: true,
                                onPressed: playable == null ? null : _playResume,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(
                                  resumeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: OutlinedButton.icon(
                                onPressed: _favBusy ? null : _toggleFavorite,
                                icon: Icon(
                                  _favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  color: _favorite ? const Color(0xFFF87171) : null,
                                ),
                                label: Text(_favorite ? '已收藏' : '收藏'),
                              ),
                            ),
                          ],
                        ),
                        if (detail.content.trim().isNotEmpty) ...[
                          const SectionHeader(title: '剧情简介'),
                          Text(
                            _stripHtml(detail.content),
                            maxLines: _descExpanded ? null : 5,
                            overflow: _descExpanded ? null : TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFC3C9D6),
                              height: 1.6,
                              fontSize: 14,
                            ),
                          ),
                          if (_stripHtml(detail.content).length > 160)
                            TextButton(
                              onPressed: () => setState(() => _descExpanded = !_descExpanded),
                              child: Text(_descExpanded ? '收起' : '展开全部'),
                            ),
                        ],
                        if (detail.sources.isNotEmpty) ...[
                          const SectionHeader(title: '选集'),
                          for (final source in detail.sources) _sourceSection(source),
                        ] else ...[
                          const SectionHeader(title: '选集'),
                          const Text(
                            '暂无可播放资源',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        ],
                        if (bundle.relate.isNotEmpty) ...[
                          const SectionHeader(title: '相关推荐'),
                          SizedBox(
                            height: relatedWidth * 1.5 + 56,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: bundle.relate.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 12),
                              itemBuilder: (context, i) {
                                final movie = bundle.relate[i];
                                return PosterCard(
                                  movie: movie,
                                  width: relatedWidth,
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => DetailScreen(
                                          mid: movie.id,
                                          initialTitle: movie.name,
                                        ),
                                      ),
                                    );
                                    if (mounted) await _load();
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(MovieDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (detail.dbScore.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6C344).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '豆瓣 ${detail.dbScore}',
                  style: const TextStyle(
                    color: Color(0xFFF6C344),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (detail.cName.isNotEmpty)
              _tag(detail.cName),
            if (detail.remarks.isNotEmpty) _tag(detail.remarks),
            if (detail.language.isNotEmpty) _tag(detail.language),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          detail.meta,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
        if (detail.actor.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '主演：${detail.actor}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFC3C9D6), fontSize: 13),
          ),
        ],
        if (detail.director.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '导演：${detail.director}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFC3C9D6), fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFC3C9D6), fontSize: 12),
      ),
    );
  }

  Widget _sourceSection(PlaySource source) {
    final expanded = _expandedSources.contains(source.id);
    final list = expanded ? source.items : source.items.take(40).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                source.name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                '${source.items.length} 集',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < list.length; i++) _episodeChip(source, i),
            ],
          ),
          if (source.items.length > 40)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    if (expanded) {
                      _expandedSources.remove(source.id);
                    } else {
                      _expandedSources.add(source.id);
                    }
                  });
                },
                child: Text(expanded ? '收起' : '展开全部 ${source.items.length} 集'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _episodeChip(PlaySource source, int index) {
    final item = source.items[index];
    final label = item.episode.isEmpty ? '第${index + 1}集' : item.episode;
    final selected = _resume != null &&
        _resume!.sourceId == source.id &&
        _resume!.episode == index;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _play(source: source, episode: index),
    );
  }

  String _episodeLabel(WatchHistory item) {
    if (item.episodeName.isNotEmpty) return item.episodeName;
    return '第${item.episode + 1}集';
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.detail});

  final MovieDetail detail;

  @override
  Widget build(BuildContext context) {
    final image = detail.picture;
    return Stack(
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
              colors: [Color(0x22000000), Color(0xAA0D0F14), AppTheme.background],
              stops: [0, 0.62, 1],
            ),
          ),
        ),
      ],
    );
  }
}

String _stripHtml(String raw) {
  if (raw.isEmpty) return '';
  var text = raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return text.trim();
}
