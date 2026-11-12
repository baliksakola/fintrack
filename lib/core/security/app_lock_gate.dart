import 'package:material_ui/material_ui.dart';
import 'app_lock_service.dart';
import '../../features/dashboard/dashboard_screen.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _ready = false;
  bool _unlocked = false;
  bool _setup = false;
  bool _busy = false;
  String? _error;
  final _pin = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    final hasPin = await AppLockService.instance.hasPin();
    if (!mounted) return;
    setState(() {
      _setup = !hasPin;
      _ready = true;
    });
    if (hasPin && await AppLockService.instance.biometricEnabled()) {
      await _unlockBiometric();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_unlocked && mounted) setState(() => _unlocked = false);
    }
  }

  Future<void> _submitPin() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (_setup) {
        if (_pin.text.length != 6 || _pin.text != _confirm.text) {
          setState(() => _error = 'PIN harus 6 angka dan konfirmasi harus sama.');
          return;
        }
        await AppLockService.instance.setPin(_pin.text);
        setState(() { _setup = false; _unlocked = true; });
      } else if (await AppLockService.instance.verifyPin(_pin.text)) {
        setState(() { _unlocked = true; _error = null; });
      } else {
        setState(() => _error = 'PIN tidak sesuai.');
      }
      _pin.clear();
      _confirm.clear();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockBiometric() async {
    final ok = await AppLockService.instance.authenticateBiometric();
    if (ok && mounted) setState(() => _unlocked = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    if (_unlocked) return const DashboardScreen();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB))),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 56),
                    const SizedBox(height: 16),
                    Text('FinTrack Paday', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_setup ? 'Buat PIN keamanan 6 angka untuk aplikasi.' : 'Masukkan PIN untuk membuka aplikasi.', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(labelText: 'PIN 6 angka', border: OutlineInputBorder(), counterText: ''),
                    ),
                    if (_setup) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirm,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(labelText: 'Ulangi PIN', border: OutlineInputBorder(), counterText: ''),
                      ),
                    ],
                    if (_error != null) Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, child: FilledButton(
                      onPressed: _busy ? null : _submitPin,
                      child: Text(_setup ? 'Simpan PIN' : 'Buka aplikasi'),
                    )),
                    if (!_setup) TextButton.icon(
                      onPressed: _unlockBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Gunakan biometrik'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
