import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/auth_controller.dart';
import '../../core/theme.dart';
import '../devices_screen.dart';
import '../library_screen.dart';
import '../login_screen.dart';
import '../qr_scan_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => ProfileTabState();
}

class ProfileTabState extends State<ProfileTab> {
  final FocusNode _firstTileNode = FocusNode(debugLabel: 'profile-first');

  @override
  void dispose() {
    _firstTileNode.dispose();
    super.dispose();
  }

  void focusFirst() {
    if (!mounted) return;
    _firstTileNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isTv = AppConfig.isTv(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: isTv ? 28 : 20,
        title: const Text('我的'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(isTv ? 28 : 20, 8, isTv ? 28 : 20, 32),
        children: [
          if (auth.isLoggedIn) _UserCard(auth: auth) else const _GuestCard(),
          const SizedBox(height: 22),
          _MenuGroup(
            children: [
              _MenuTile(
                focusNode: _firstTileNode,
                icon: Icons.history_rounded,
                title: '观看记录',
                subtitle: '跨设备同步播放进度',
                onTap: () => _openLibrary(context, auth, 0),
              ),
              _MenuTile(
                icon: Icons.favorite_border_rounded,
                title: '我的收藏',
                subtitle: '收藏的影片',
                onTap: () => _openLibrary(context, auth, 1),
              ),
              if (!isTv)
                _MenuTile(
                  icon: Icons.qr_code_scanner_rounded,
                  title: '扫一扫登录电视',
                  subtitle: '扫描电视上的二维码完成授权',
                  onTap: () {
                    if (!auth.isLoggedIn) {
                      _needLogin(context);
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const QrScanScreen()),
                    );
                  },
                ),
              _MenuTile(
                icon: Icons.devices_rounded,
                title: '登录设备管理',
                subtitle: '查看并下线已登录设备',
                onTap: () => _openDevices(context, auth),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MenuGroup(
            children: [
              _MenuTile(
                icon: Icons.dns_outlined,
                title: '服务器地址',
                subtitle: auth.baseUrl,
                onTap: () => _editServer(context, auth),
              ),
              _MenuTile(
                icon: Icons.info_outline_rounded,
                title: '版本',
                subtitle: 'GoFilm ${AppConfig.appVersion} · ${isTv ? 'TV' : '手机'}端',
              ),
            ],
          ),
          if (isTv && auth.deviceId.isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                '设备 ID：${auth.deviceId}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ),
          ],
          if (auth.isLoggedIn) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => _logout(context, auth),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF87171),
                minimumSize: const Size(0, 48),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('退出登录'),
            ),
          ],
        ],
      ),
    );
  }

  void _needLogin(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('请先登录'),
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

  void _openLibrary(BuildContext context, AuthController auth, int tab) {
    if (!auth.isLoggedIn) {
      _needLogin(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LibraryScreen(initialTab: tab)),
    );
  }

  void _openDevices(BuildContext context, AuthController auth) {
    if (!auth.isLoggedIn) {
      _needLogin(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DevicesScreen()),
    );
  }

  Future<void> _editServer(BuildContext context, AuthController auth) async {
    final controller = TextEditingController(text: auth.baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('服务器地址'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(context, controller.text),
          decoration: const InputDecoration(hintText: 'http://192.168.1.10:3601'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    if (!context.mounted) return;
    if (auth.isLoggedIn) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('切换服务器'),
          content: const Text('切换服务器后需要重新登录，是否继续？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await auth.setBaseUrl(result);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('服务器地址已更新')));
  }

  Future<void> _logout(BuildContext context, AuthController auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后仍可以游客身份浏览影片，是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await auth.logout();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已退出登录')));
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final user = auth.user!;
    final initial = user.displayName.isEmpty
        ? '?'
        : String.fromCharCode(user.displayName.runes.first);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.18),
            child: Text(
              initial,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.accent),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${user.userName}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              user.role == 'admin' ? '管理员' : '会员',
              style: const TextStyle(color: AppTheme.accent, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.surfaceHigh,
                child: Icon(Icons.person_outline, size: 30, color: AppTheme.textMuted),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('游客模式', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text(
                      '登录后可同步观看记录和收藏',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: const Text('登录 / 注册'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 56),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatefulWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.focusNode,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  late final bool _ownsNode = widget.focusNode == null;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focused == _node.hasFocus) return;
    setState(() => _focused = _node.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        color: _focused ? AppTheme.accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _focused ? AppTheme.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        focusNode: _node,
        leading: Icon(widget.icon, color: AppTheme.textMuted),
        title: Text(widget.title),
        subtitle: widget.subtitle == null
            ? null
            : Text(
                widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
        trailing: widget.onTap == null
            ? null
            : const Icon(Icons.chevron_right, color: AppTheme.textMuted),
        onTap: widget.onTap,
      ),
    );
  }
}
