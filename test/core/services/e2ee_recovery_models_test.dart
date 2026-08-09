import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/e2ee/e2ee_recovery_models.dart';

void main() {
  test('trusted-device recovery is enabled only by an explicit capability', () {
    expect(
      supportsTrustedDeviceE2EERecovery(
        const {'e2ee_recovery_mode': 'trusted_device_rewrap'},
      ),
      isTrue,
    );
    expect(supportsTrustedDeviceE2EERecovery(const {}), isFalse);
    expect(supportsTrustedDeviceE2EERecovery(null), isFalse);
  });

  test('recovery request parses approval payload without losing key version',
      () {
    final request = E2EERecoveryRequest.fromJson({
      'request_id': 'request-1',
      'status': 'approved',
      'requester_device_id': 'new-device',
      'requester_device_name': 'New Phone',
      'requester_device_type': 'android',
      'requester_public_key': '{"kty":"RSA"}',
      'requester_public_key_algo': 'rsa-jwk-oaep-2048',
      'source_device_id': 'old-device',
      'source_key_fingerprint': 'abc123',
      'source_key_version': '7',
      'encrypted_payload': 'ciphertext',
      'payload_algo': 'rsa-jwk-oaep-2048',
      'is_requester': true,
      'expires_at': '2026-07-15T00:00:00Z',
    });

    expect(request.requestId, 'request-1');
    expect(request.isApproved, isTrue);
    expect(request.isRequester, isTrue);
    expect(request.sourceDeviceId, 'old-device');
    expect(request.sourceKeyVersion, 7);
    expect(request.encryptedPayload, 'ciphertext');
  });
}
