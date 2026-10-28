import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/auth_controller.dart';
import '../core/theme.dart';
import 'home_screen.dart';
import 'tv_login_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _nickName = TextEditingController();

  late final AuthController _auth;
  bool _registerMode = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
    _server.text = _auth.baseUrl;
  }

  @override
  void dispose() {
    _server.dispose();
    _account.dispose();
    _password.dispose();
    _nickName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final account = _account.text.trim();
    final password = _password.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      if (_registerMode) {
        await _auth.register(
          baseUrl: _server.text,
          userName: account,
          password: password,
          nickName: _nickName.text.trim(),
          platform: AppConfig.platform(context),
          deviceName: AppConfig.defaultDeviceName(context),
        );
      } else {
        await _auth.login(
          baseUrl: _server.text,
          account: account,
          password: password,
          platform: AppConfig.platform(context),
          deviceName: AppConfig.defaultDeviceName(context),
        );
      }
      if (!mounted) return;
      // 登录前弹出的“请先登录”提示不应继续浮在新页面上
      ScaffoldMessenger.of(context).clearSnackBars();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: _server.text);
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
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.10:3601',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    final normalized = AppConfig.normalizeBaseUrl(result);
    _server.text = normalized;
    await _auth.setBaseUrl(normalized);
    if (!mounted) return;
    setState(() {});
  }

  void _openTvLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TvLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = AppConfig.isTv(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'GoFilm',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isTv ? 'Android TV 客户端' : '登录后同步观看记录与收藏',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: _editServer,
                      icon: const Icon(Icons.dns_outlined, size: 16),
                      label: Text(
                        _server.text.isEmpty ? '设置服务器地址' : _server.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (isTv) ...[
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _openTvLogin,
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('手机扫码登录'),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('或使用账号密码', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _account,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: _registerMode ? '用户名' : '账号',
                      hintText: _registerMode ? '3-20位字母、数字或下划线' : '用户名',
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: _registerMode ? TextInputAction.next : TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _loading ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      ),
                    ),
                  ),
                  if (_registerMode) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nickName,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _loading ? null : _submit(),
                      decoration: const InputDecoration(
                        labelText: '昵称（可选）',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFF87171), fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_registerMode ? '注册并登录' : '登录'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _registerMode = !_registerMode;
                              _error = null;
                            }),
                    child: Text(_registerMode ? '已有账号，去登录' : '没有账号？注册'),
                  ),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const HomeScreen()),
                              (_) => false,
                            ),
                    child: const Text('先逛逛（游客模式）'),
                  ),
                  if (_error != null && _error!.contains('连接'))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        onPressed: _editServer,
                        icon: const Icon(Icons.wifi_tethering, size: 16),
                        label: const Text('检查服务器地址'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
