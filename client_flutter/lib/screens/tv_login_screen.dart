import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/auth_controller.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'home_screen.dart';

class TvLoginScreen extends StatefulWidget {
  const TvLoginScreen({super.key});

  @override
  State<TvLoginScreen> createState() => _TvLoginScreenState();
}

class _TvLoginScreenState extends State<TvLoginScreen> {
  late final AuthController _auth;
  QrCreateResult? _qr;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  String _status = '正在生成二维码…';
  String? _error;
  int _left = 0;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _create());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    setState(() {
      _error = null;
      _status = '正在生成二维码…';
      _qr = null;
      _finishing = false;
    });
    try {
      final qr = await _auth.createQr(
        platform: 'android-tv',
        deviceName: AppConfig.defaultDeviceName(context),
      );
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _status = '等待手机扫码';
        _left = qr.expiresIn;
      });
      final interval = qr.pollInterval <= 0 ? 2 : qr.pollInterval;
      _pollTimer = Timer.periodic(Duration(seconds: interval), (_) => _poll());
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _qr == null) return;
        if (_left <= 1) {
          _countdownTimer?.cancel();
          _pollTimer?.cancel();
          setState(() {
            _left = 0;
            _status = '二维码已过期';
          });
        } else {
          setState(() => _left--);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '二维码生成失败';
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _poll() async {
    final qr = _qr;
    if (qr == null || _finishing) return;
    try {
      final result = await _auth.pollQr(qr.qid, qr.pollToken);
      if (!mounted || _finishing) return;
      switch (result.status) {
        case 'confirmed':
          final session = result.auth;
          if (session == null) return;
          _finishing = true;
          _pollTimer?.cancel();
          _countdownTimer?.cancel();
          setState(() => _status = '登录成功');
          await _auth.applyQrAuth(session);
          if (!mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          );
          break;
        case 'scanned':
          if (_status != '已扫码，请在手机上确认') {
            setState(() => _status = '已扫码，请在手机上确认');
          }
          break;
        case 'pending':
          break;
        case 'expired':
        case 'canceled':
          _pollTimer?.cancel();
          _countdownTimer?.cancel();
          setState(() {
            _status = result.status == 'canceled' ? '二维码已取消' : '二维码已过期';
            _left = 0;
          });
          break;
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        _pollTimer?.cancel();
        setState(() => _status = '二维码已失效，请刷新');
      }
    } catch (_) {
      // 网络抖动时继续轮询
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码登录')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '使用手机 GoFilm 扫码',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '手机端：我的 → 扫一扫登录电视\n也可用系统相机直接扫码打开确认页',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, height: 1.6),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: _qr == null
                    ? const SizedBox(
                        width: 220,
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : QrImageView(
                        data: _qr!.qrUrl,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 15,
                  color: _status == '登录成功' ? const Color(0xFF4ADE80) : Colors.white,
                ),
              ),
              if (_qr != null && _left > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$_left 秒后过期',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFF87171), fontSize: 13),
                  ),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新二维码'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('使用账号密码登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
