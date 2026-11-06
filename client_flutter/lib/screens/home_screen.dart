import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/auth_controller.dart';
import '../core/theme.dart';
import '../services/content_service.dart';
import 'tabs/category_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/search_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ContentService _content;
  final GlobalKey<HomeTabState> _homeKey = GlobalKey<HomeTabState>();
  final GlobalKey<CategoryTabState> _categoryKey = GlobalKey<CategoryTabState>();
  final GlobalKey<SearchTabState> _searchKey = GlobalKey<SearchTabState>();
  final GlobalKey<ProfileTabState> _profileKey = GlobalKey<ProfileTabState>();
  final GlobalKey _contentKey = GlobalKey();
  final List<FocusNode> _railNodes = List.generate(
    4,
    (i) => FocusNode(debugLabel: 'tv-rail-$i'),
  );
  int _current = 0;

  static const List<({IconData icon, IconData selectedIcon, String label})>
  _tvDestinations = [
    (icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: '首页'),
    (icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view_rounded, label: '分类'),
    (icon: Icons.search_outlined, selectedIcon: Icons.search_rounded, label: '搜索'),
    (icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: '我的'),
  ];

  @override
  void initState() {
    super.initState();
    _content = ContentService(context.read<AuthController>().api);
  }

  @override
  void dispose() {
    for (final node in _railNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusCurrent() {
    switch (_current) {
      case 0:
        _homeKey.currentState?.focusFirst();
      case 1:
        _categoryKey.currentState?.focusFirst();
      case 2:
        _searchKey.currentState?.focusInput();
      case 3:
        _profileKey.currentState?.focusFirst();
    }
  }

  void _select(int index) {
    if (index == _current) {
      if (AppConfig.isTv(context)) _focusCurrent();
      return;
    }
    setState(() => _current = index);
    if (!AppConfig.isTv(context)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusCurrent());
  }

  KeyEventResult _onContentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    if (_searchKey.currentState?.isInputFocused ?? false) {
      return KeyEventResult.ignored;
    }
    if (_current == 0 && (_homeKey.currentState?.isBannerFocused ?? false)) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null) return KeyEventResult.ignored;
    final focusedObject = focused.context?.findRenderObject();
    final contentObject = _contentKey.currentContext?.findRenderObject();
    if (focusedObject is! RenderBox || contentObject is! RenderBox) {
      return KeyEventResult.ignored;
    }
    final left = focusedObject.localToGlobal(Offset.zero).dx;
    final contentLeft = contentObject.localToGlobal(Offset.zero).dx;
    if (left > contentLeft + 160) return KeyEventResult.ignored;
    _railNodes[_current].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final isTv = AppConfig.isTv(context);
    final pages = [
      HomeTab(
        key: _homeKey,
        content: _content,
        onOpenSearch: () => _select(2),
        onOpenProfile: () => _select(3),
      ),
      CategoryTab(key: _categoryKey, content: _content),
      SearchTab(key: _searchKey, content: _content),
      ProfileTab(key: _profileKey),
    ];
    final body = IndexedStack(index: _current, children: pages);

    if (isTv) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) SystemNavigator.pop();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: Row(
              children: [
                _TvRail(
                  selected: _current,
                  nodes: _railNodes,
                  destinations: _tvDestinations,
                  onActivate: _select,
                  onExit: _focusCurrent,
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ColoredBox(
                    key: _contentKey,
                    color: Colors.transparent,
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      includeSemantics: false,
                      onKeyEvent: _onContentKey,
                      child: body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) SystemNavigator.pop();
      },
      child: Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _current,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: '分类',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search_rounded),
              label: '搜索',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}

class _TvRail extends StatelessWidget {
  const _TvRail({
    required this.selected,
    required this.nodes,
    required this.destinations,
    required this.onActivate,
    required this.onExit,
  });

  final int selected;
  final List<FocusNode> nodes;
  final List<({IconData icon, IconData selectedIcon, String label})>
  destinations;
  final ValueChanged<int> onActivate;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      color: AppTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Row(
              children: [
                Icon(Icons.movie_filter_rounded, color: AppTheme.accent, size: 26),
                SizedBox(width: 10),
                Text(
                  'GoFilm',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          for (var i = 0; i < destinations.length; i++)
            _TvRailItem(
              node: nodes[i],
              icon: destinations[i].icon,
              selectedIcon: destinations[i].selectedIcon,
              label: destinations[i].label,
              selected: i == selected,
              onActivate: () => onActivate(i),
              onExit: onExit,
            ),
        ],
      ),
    );
  }
}

class _TvRailItem extends StatefulWidget {
  const _TvRailItem({
    required this.node,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onActivate,
    required this.onExit,
  });

  final FocusNode node;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onActivate;
  final VoidCallback onExit;

  @override
  State<_TvRailItem> createState() => _TvRailItemState();
}

class _TvRailItemState extends State<_TvRailItem> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    final activateKeys = <LogicalKeyboardKey>{
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.gameButtonA,
    };
    if (activateKeys.contains(event.logicalKey)) {
      widget.onActivate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onActivate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _focused
                  ? AppTheme.surfaceHigh
                  : widget.selected
                  ? AppTheme.accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? AppTheme.accent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.selected ? widget.selectedIcon : widget.icon,
                  size: 24,
                  color: active ? AppTheme.accent : AppTheme.textMuted,
                ),
                const SizedBox(width: 14),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                    color: active ? Colors.white : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
