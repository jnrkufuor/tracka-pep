import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// How the phone is connected right now.
enum Net { offline, wifi, mobile }

/// Watches the connection. An interface so tests can pretend to be on Wi-Fi,
/// on mobile data or offline without a real phone.
abstract class NetCheck {
  Future<Net> now();
  Stream<Net> get changes;
}

Net _from(List<ConnectivityResult> r) {
  if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) return Net.wifi;
  if (r.contains(ConnectivityResult.mobile) || r.contains(ConnectivityResult.vpn) || r.contains(ConnectivityResult.other)) {
    return Net.mobile;
  }
  return Net.offline;
}

class DeviceNet implements NetCheck {
  final _c = Connectivity();

  @override
  Future<Net> now() async {
    try {
      return _from(await _c.checkConnectivity());
    } catch (_) {
      return Net.wifi; // can't tell (some browsers): don't block uploads
    }
  }

  @override
  Stream<Net> get changes => _c.onConnectivityChanged.map(_from);
}

class FakeNet implements NetCheck {
  FakeNet([this.value = Net.wifi]);

  Net value;
  final _ctrl = StreamController<Net>.broadcast();

  void set(Net n) {
    value = n;
    _ctrl.add(n);
  }

  @override
  Future<Net> now() async => value;

  @override
  Stream<Net> get changes => _ctrl.stream;
}
