import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final AuthController _auth;

  List<DeviceSession>? _items;
  String? _error;
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
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
      final items = await _auth.devices();
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

  Future<void> _revoke(DeviceSession device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下线设备'),
        content: Text('确定让「${device.deviceName}」退出登录？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('下线'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = device.deviceId);
    try {
      await _auth.revokeDevice(device.deviceId);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _logoutAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全部下线'),
        content: const Text('所有设备都将退出登录，包括当前设备。是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('全部下线'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final count = await _auth.logoutAll();
      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(SnackBar(content: Text('已下线 $count 个设备')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录设备'),
        actions: [
          if ((_items?.length ?? 0) > 0)
            TextButton(
              onPressed: _logoutAll,
              child: const Text(
                '全部下线',
                style: TextStyle(color: Color(0xFFF87171)),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_auth.isLoggedIn) {
      return const EmptyView(message: '登录后管理设备');
    }
    if (_loading) return const LoadingView();
    final items = _items;
    if (items == null) {
      return ErrorRetryView(message: _error ?? '加载失败', onRetry: _load);
    }
    if (items.isEmpty) {
      return const EmptyView(message: '暂无登录设备');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final device = items[i];
          final isTvDevice = device.platform.contains('tv');
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isTvDevice ? Icons.tv_rounded : Icons.smartphone_rounded,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.deviceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (device.current) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '当前设备',
                                style: TextStyle(fontSize: 10, color: AppTheme.accent),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${device.platform.isEmpty ? '未知平台' : device.platform}'
                        '${device.appVersion.isEmpty ? '' : ' · v${device.appVersion}'}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '最近活跃 ${_formatTime(device.lastActiveAt)}'
                        '${device.lastIp.isEmpty ? '' : ' · ${device.lastIp}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                if (!device.current)
                  _busyId == device.deviceId
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => _revoke(device),
                          child: const Text('下线', style: TextStyle(color: Color(0xFFF87171))),
                        ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _formatTime(int milliseconds) {
  if (milliseconds <= 0) return '未知';
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
