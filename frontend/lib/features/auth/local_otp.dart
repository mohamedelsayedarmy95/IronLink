import 'package:flutter/foundation.dart';

import '../../core/env.dart';

const _requested = bool.fromEnvironment('IRONLINK_LOCAL_OTP');

bool get localOtpEnabled =>
    kDebugMode &&
    _requested &&
    isLocalOtpTarget(Env.apiBaseUrl, Env.wsBaseUrl);

bool isLocalOtpTarget(String apiUrl, String wsUrl) {
  final api = Uri.tryParse(apiUrl);
  final ws = Uri.tryParse(wsUrl);
  if (api == null || ws == null || !api.hasPort || api.port != ws.port) {
    return false;
  }
  return api ==
          Uri(
            scheme: 'http',
            host: 'localhost',
            port: api.port,
            path: '/api/v1',
          ) &&
      ws == Uri(scheme: 'ws', host: 'localhost', port: api.port);
}
