import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/content_service.dart';
import '../../widgets/paged_movie_grid.dart';
import '../detail_screen.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key, required this.content});

  final ContentService content;

  @override
  State<SearchTab> createState() => SearchTabState();
}

class SearchTabState extends State<SearchTab> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _keyword = '';

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void focusInput() {
    if (!mounted) return;
    _focus.requestFocus();
  }

  bool get isInputFocused => _focus.hasFocus;

  void _submit() {
    final value = _input.text.trim();
    if (value.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _keyword = value);
  }

  void _open(MovieBasic movie) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailScreen(mid: movie.id, initialTitle: movie.name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = AppConfig.isTv(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: isTv ? 28 : 20,
        title: const Text('搜索'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(isTv ? 28 : 20, 4, isTv ? 28 : 20, 12),
            child: TextField(
              controller: _input,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '搜索影片、剧集、演员',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: _submit,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
          ),
          Expanded(
            child: _keyword.isEmpty
                ? const _SearchHint()
                : PagedMovieGrid(
                    key: ValueKey(_keyword),
                    autofocusFirst: isTv,
                    loader: (page) => widget.content.search(
                      _keyword,
                      current: page,
                      pageSize: 30,
                    ),
                    onTap: _open,
                    emptyMessage: '没有找到「$_keyword」相关影片',
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_search_rounded, size: 56, color: AppTheme.textMuted),
            const SizedBox(height: 14),
            const Text(
              '输入关键词开始搜索',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '支持片名、演员、导演等关键词',
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
