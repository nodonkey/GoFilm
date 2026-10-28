import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../core/auth_controller.dart';
import '../core/theme.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  static final RegExp _qidPattern = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

  late final AuthController _auth;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthController>();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _extractQid(String raw) {
    final value = raw.trim();
    if (_qidPattern.hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    final qid = uri?.queryParameters['qid'];
    if (qid != null && _qidPattern.hasMatch(qid)) return qid;
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    final qid = _extractQid(raw);
    if (qid == null) return;

    setState(() {
      _processing = true;
      _error = null;
    });
    await _controller.stop();
    try {
      await _auth.scanQr(qid);
      await _auth.confirmQr(qid);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('登录成功'),
          content: const Text('电视已登录，可以继续在电视上操作。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = friendlyError(e);
      });
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫一扫登录电视'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => ColoredBox(
              color: Colors.black,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_rounded,
                          size: 44, color: AppTheme.textMuted),
                      const SizedBox(height: 14),
                      const Text(
                        '无法启动相机',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '请确认已授予相机权限后重试',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () async {
                          await _controller.stop();
                          await _controller.start();
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.accent, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _processing ? '正在确认登录…' : '将电视上的二维码放入取景框',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFF87171), fontSize: 13),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _controller.start();
                        },
                        child: const Text('重新扫描'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
