import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/auth_controller.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/content_service.dart';
import '../widgets/paged_movie_grid.dart';
import 'detail_screen.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.category, this.initialCid = 0});

  final CategoryNode category;
  final int initialCid;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  static const _sorts = <String, String>{
    'update_stamp': '最近更新',
    'hits': '最多播放',
    'score': '评分最高',
    'release_stamp': '最新上映',
  };

  late final ContentService _content;
  late int _cid;
  String _sort = 'update_stamp';

  @override
  void initState() {
    super.initState();
    _content = ContentService(context.read<AuthController>().api);
    _cid = widget.initialCid;
  }

  @override
  Widget build(BuildContext context) {
    final isTv = AppConfig.isTv(context);
    final category = widget.category;
    final children = category.children;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(category.name),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (children.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: isTv ? 28 : 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: ChoiceChip(
                      label: const Text('全部'),
                      selected: _cid == 0,
                      onSelected: (_) => setState(() => _cid = 0),
                    ),
                  ),
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: ChoiceChip(
                        label: Text(child.name),
                        selected: _cid == child.id,
                        onSelected: (_) => setState(() => _cid = child.id),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(isTv ? 28 : 20, 4, isTv ? 28 : 20, 6),
            child: Row(
              children: [
                const Text(
                  '排序',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _sort,
                    dropdownColor: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    items: [
                      for (final entry in _sorts.entries)
                        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _sort = value);
                    },
                  ),
                ),
                const Spacer(),
                Text(
                  category.name,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedMovieGrid(
              key: ValueKey('${category.id}-$_cid-$_sort'),
              autofocusFirst: AppConfig.isTv(context),
              loader: (page) => _content.category(
                category.id,
                cid: _cid,
                current: page,
                pageSize: 30,
                sort: _sort,
              ),
              onTap: (movie) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DetailScreen(mid: movie.id, initialTitle: movie.name),
                ),
              ),
              emptyMessage: '该分类下暂无影片',
            ),
          ),
        ],
      ),
    );
  }
}
