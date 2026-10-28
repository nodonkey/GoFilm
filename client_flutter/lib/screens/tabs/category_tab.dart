import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/auth_controller.dart' show friendlyError;
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/content_service.dart';
import '../../widgets/common.dart';
import '../category_screen.dart';

class CategoryTab extends StatefulWidget {
  const CategoryTab({super.key, required this.content});

  final ContentService content;

  @override
  State<CategoryTab> createState() => CategoryTabState();
}

class CategoryTabState extends State<CategoryTab> {
  final FocusNode _firstCardNode = FocusNode(debugLabel: 'category-first');
  List<CategoryNode>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstCardNode.dispose();
    super.dispose();
  }

  void focusFirst() {
    if (!mounted) return;
    _firstCardNode.requestFocus();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items == null;
      _error = null;
    });
    try {
      final items = await widget.content.nav();
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

  @override
  Widget build(BuildContext context) {
    final isTv = AppConfig.isTv(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: isTv ? 28 : 20,
        title: const Text('分类'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _buildBody(isTv),
    );
  }

  Widget _buildBody(bool isTv) {
    if (_loading) return const LoadingView();
    final items = _items;
    if (items == null) {
      return ErrorRetryView(message: _error ?? '加载失败', onRetry: _load);
    }
    if (items.isEmpty) {
      return const EmptyView(message: '暂无分类');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: EdgeInsets.all(isTv ? 28 : 20),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: isTv ? 320 : 220,
          mainAxisExtent: isTv ? 128 : 112,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final node = items[i];
          return _CategoryCard(
            node: node,
            focusNode: i == 0 ? _firstCardNode : null,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CategoryScreen(category: node)),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({required this.node, required this.onTap, this.focusNode});

  final CategoryNode node;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _focused = false;

  IconData get _icon {
    final name = widget.node.name;
    if (name.contains('电影')) return Icons.movie_outlined;
    if (name.contains('剧')) return Icons.live_tv_rounded;
    if (name.contains('综艺')) return Icons.mic_external_on_outlined;
    if (name.contains('动漫') || name.contains('动画')) return Icons.animation_rounded;
    return Icons.category_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.node.children.length;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused ? AppTheme.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon, color: AppTheme.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      children > 0 ? '$children 个子分类' : '查看全部',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
