import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/auth_controller.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/content_service.dart';
import '../widgets/common.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.mid,
    required this.title,
    this.playFrom,
    this.episode = 0,
    this.initialPosition = 0,
  });

  final int mid;
  final String title;
  final String? playFrom;
  final int episode;
  final int initialPosition;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late final AuthController _auth;
  late final ContentService _content;

  VideoPlayerController? _video;
  PlayBundle? _bundle;
  Timer? _saveTimer;
  Timer? _hideTimer;

  bool _loading = true;
  bool _showControls = true;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = context.read<AuthController>();
    _content = ContentService(_auth.api);
    _load();
    _saveTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_saveHistory()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    unawaited(_saveHistory());
    final video = _video;
    video?.removeListener(_onVideoChanged);
    video?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _video?.pause();
      unawaited(_saveHistory());
    }
  }

  Future<void> _load() async {
    final previous = _video;
    if (previous != null) {
      previous.removeListener(_onVideoChanged);
      _video = null;
      await previous.dispose();
    }
    if (!mounted) return;
    setState(() {
      _bundle = null;
      _loading = true;
      _error = null;
      _completed = false;
      _showControls = true;
    });
    try {
      final bundle = await _content.play(
        widget.mid,
        playFrom: widget.playFrom,
        episode: widget.episode,
      );
      final uri = Uri.parse(bundle.current.link);
      final controller = VideoPlayerController.networkUrl(
        uri,
        formatHint:
            uri.path.contains('/proxy/m3u8') ? VideoFormat.hls : null,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final duration = controller.value.duration;
      if (widget.initialPosition > 0 &&
          duration.inSeconds > widget.initialPosition + 3) {
        await controller.seekTo(Duration(seconds: widget.initialPosition));
      }
      controller.addListener(_onVideoChanged);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _bundle = bundle;
        _video = controller;
        _loading = false;
      });
      _scheduleHide();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException
            ? e.message
            : '视频加载失败，请检查网络或服务器代理配置';
      });
    }
  }

  void _onVideoChanged() {
    final video = _video;
    if (video == null || !mounted) return;
    final value = video.value;
    if (value.hasError && _error == null) {
      setState(() => _error = '播放出错，请重试');
      return;
    }
    if (!_completed &&
        value.duration.inMilliseconds > 0 &&
        value.position.inMilliseconds >= value.duration.inMilliseconds - 800) {
      _completed = true;
      _hideTimer?.cancel();
      unawaited(_saveHistory());
      if (mounted) setState(() => _showControls = true);
    }
  }

  Future<void> _saveHistory() async {
    final bundle = _bundle;
    final video = _video;
    if (bundle == null || video == null || !_auth.isLoggedIn) return;
    final value = video.value;
    final duration = value.duration.inSeconds;
    if (duration <= 0) return;
    var position = value.position.inSeconds;
    if (position < 0) position = 0;
    if (position > duration) position = duration;
    try {
      await _content.saveHistory(
        mid: widget.mid,
        sourceId: bundle.currentPlayFrom,
        episode: bundle.currentEpisode,
        episodeName: bundle.current.episode,
        position: position,
        duration: duration,
      );
    } catch (_) {
      // 进度同步失败不打断播放
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (AppConfig.isTv(context)) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_video?.value.isPlaying ?? false) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _togglePlay() {
    final video = _video;
    if (video == null) return;
    if (video.value.isPlaying) {
      video.pause();
      _hideTimer?.cancel();
    } else {
      if (_completed) {
        video.seekTo(Duration.zero);
        _completed = false;
      }
      video.play();
      _scheduleHide();
    }
    setState(() => _showControls = true);
  }

  PlaySource? _currentSource() {
    final bundle = _bundle;
    if (bundle == null) return null;
    for (final source in bundle.detail.sources) {
      if (source.id == bundle.currentPlayFrom) return source;
    }
    return null;
  }

  bool get _hasNext {
    final bundle = _bundle;
    final source = _currentSource();
    return bundle != null &&
        source != null &&
        bundle.currentEpisode + 1 < source.items.length;
  }

  void _nextEpisode() {
    final bundle = _bundle;
    if (bundle == null || !_hasNext) return;
    _openEpisode(bundle.currentPlayFrom, bundle.currentEpisode + 1);
  }

  void _openEpisode(String sourceId, int episode) {
    unawaited(_saveHistory());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mid: widget.mid,
          title: widget.title,
          playFrom: sourceId,
          episode: episode,
        ),
      ),
    );
  }

  Future<void> _pickEpisode() async {
    final bundle = _bundle;
    if (bundle == null) return;
    final choice = await showModalBottomSheet<_EpisodeChoice>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EpisodeSheet(bundle: bundle),
    );
    if (choice != null && mounted) {
      _openEpisode(choice.sourceId, choice.episode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在加载视频…', style: TextStyle(color: AppTheme.textMuted)),
          ],
        ),
      );
    }
    if (_error != null) {
      return ErrorRetryView(message: _error!, onRetry: _load);
    }
    final bundle = _bundle;
    final video = _video;
    if (bundle == null || video == null) return const SizedBox.shrink();

    final ratio = video.value.aspectRatio;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: ratio > 0 ? ratio : 16 / 9,
            child: VideoPlayer(video),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
          ),
        ),
        AnimatedOpacity(
          opacity: _showControls ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_showControls,
            child: _buildControls(bundle, video),
          ),
        ),
      ],
    );
  }

  Widget _buildControls(PlayBundle bundle, VideoPlayerController video) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.62),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _episodeLabel(bundle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            Expanded(
              child: Center(
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: video,
                  builder: (context, value, _) {
                    return IconButton(
                      autofocus: true,
                      iconSize: 64,
                      onPressed: _togglePlay,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: video,
              builder: (context, value, _) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Column(
                    children: [
                      VideoProgressIndicator(
                        video,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        colors: const VideoProgressColors(
                          playedColor: AppTheme.accent,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _formatDuration(value.position),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          const Spacer(),
                          Text(
                            _formatDuration(value.duration),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _pickEpisode,
                            icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
                            label: const Text('选集'),
                          ),
                          const Spacer(),
                          if (_hasNext)
                            TextButton.icon(
                              onPressed: _nextEpisode,
                              icon: const Icon(Icons.skip_next_rounded, size: 20),
                              label: const Text('下一集'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _episodeLabel(PlayBundle bundle) {
    final name = bundle.current.episode.isEmpty
        ? '第${bundle.currentEpisode + 1}集'
        : bundle.current.episode;
    final source = _currentSource();
    if (source == null) return name;
    return '${source.name} · $name';
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class _EpisodeChoice {
  const _EpisodeChoice(this.sourceId, this.episode);

  final String sourceId;
  final int episode;
}

class _EpisodeSheet extends StatefulWidget {
  const _EpisodeSheet({required this.bundle});

  final PlayBundle bundle;

  @override
  State<_EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<_EpisodeSheet> {
  int _sourceIndex = 0;

  @override
  void initState() {
    super.initState();
    final sources = widget.bundle.detail.sources;
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].id == widget.bundle.currentPlayFrom) {
        _sourceIndex = i;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.bundle.detail.sources;
    if (sources.isEmpty) {
      return const SafeArea(child: EmptyView(message: '暂无可播放剧集'));
    }
    final source = sources[_sourceIndex];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '选集',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (sources.length > 1)
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: sources.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    return ChoiceChip(
                      label: Text(sources[i].name),
                      selected: i == _sourceIndex,
                      onSelected: (_) => setState(() => _sourceIndex = i),
                    );
                  },
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 108,
                  mainAxisExtent: 40,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: source.items.length,
                itemBuilder: (context, i) {
                  final item = source.items[i];
                  final selected = source.id == widget.bundle.currentPlayFrom &&
                      i == widget.bundle.currentEpisode;
                  final label = item.episode.isEmpty ? '第${i + 1}集' : item.episode;
                  return ChoiceChip(
                    label: SizedBox(
                      width: double.infinity,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => Navigator.of(context).pop(
                      _EpisodeChoice(source.id, i),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
