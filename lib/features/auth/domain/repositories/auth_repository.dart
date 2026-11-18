import '../entities/auth_session.dart';
import '../entities/otp_challenge.dart';

abstract interface class AuthRepository {
  /// Sends a one-time code to [phoneNumber] (E.164, e.g. `+919876543210`).
  Future<OtpChallenge> requestOtp(String phoneNumber);

  Future<AuthSession> verifyOtp({
    required String phoneNumber,
    required String code,
  });

  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    required DateTime dateOfBirth,
    required String acceptedTermsVersion,
  });

  Future<AuthSession> login({required String email, required String password});

  /// Provider is `google` or `apple`. Returns `FEATURE_NOT_CONFIGURED` until
  /// the backend has social credentials.
  Future<AuthSession> socialSignIn({
    required String provider,
    required String idToken,
  });

  /// The restored session, or `null` when signed out. Throws on network
  /// failure rather than reporting "signed out".
  Future<AuthSession?> currentSession();

  /// Revokes the current refresh token (or all devices when [allDevices]).
  Future<void> signOut({bool allDevices = false});
}
