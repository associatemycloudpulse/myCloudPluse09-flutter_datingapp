import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/json.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/otp_challenge.dart';
import '../../domain/phone_number.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/auth_dto.dart';

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._client, this._tokenStore);

  final ApiClient _client;
  final TokenStore _tokenStore;

  Future<AuthSession> _persistAuth(Object? data) async {
    final response = AuthResultDto.fromJson(asJson(data));
    await _tokenStore.save(response.tokens);
    return response.toEntity();
  }

  @override
  Future<OtpChallenge> requestOtp(String phoneNumber) async =>
      OtpChallengeDto.fromJson(
        asJson(
          await _client.post(
            ApiEndpoints.otpRequest,
            body: {'phoneNumber': PhoneNumberRules.normalize(phoneNumber)},
            skipAuth: true,
          ),
        ),
      );

  @override
  Future<AuthSession> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async => _persistAuth(
    await _client.post(
      ApiEndpoints.otpVerify,
      body: {
        'phoneNumber': PhoneNumberRules.normalize(phoneNumber),
        'code': code,
      },
      skipAuth: true,
    ),
  );

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    required DateTime dateOfBirth,
    required String acceptedTermsVersion,
  }) async => _persistAuth(
    await _client.post(
      ApiEndpoints.register,
      body: {
        'email': email.trim(),
        'password': password,
        'displayName': displayName.trim(),
        'dateOfBirth': dateOfBirth.toUtc().toIso8601String().split('T').first,
        'acceptedTermsVersion': acceptedTermsVersion,
      },
      skipAuth: true,
    ),
  );

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async => _persistAuth(
    await _client.post(
      ApiEndpoints.login,
      body: {'email': email.trim(), 'password': password},
      skipAuth: true,
    ),
  );

  @override
  Future<AuthSession> socialSignIn({
    required String provider,
    required String idToken,
  }) async => _persistAuth(
    await _client.post(
      ApiEndpoints.social(provider),
      body: {'idToken': idToken},
      skipAuth: true,
    ),
  );

  @override
  Future<AuthSession?> currentSession() async {
    if (await _tokenStore.read() == null) return null;
    try {
      final me = asJson(await _client.get(ApiEndpoints.myProfile));
      return AuthSession(
        userId: me.req<String>('id'),
        needsOnboarding: me.opt<bool>('onboardingComplete') == false,
      );
    } on Failure catch (failure) {
      if (failure.code != ErrorCode.unauthenticated) rethrow;
      await _tokenStore.clear();
      return null;
    }
  }

  @override
  Future<void> signOut({bool allDevices = false}) async {
    final tokens = await _tokenStore.read();
    try {
      if (tokens != null) {
        await _client.post(
          allDevices ? ApiEndpoints.logoutAll : ApiEndpoints.logout,
          body: allDevices ? null : {'refreshToken': tokens.refreshToken},
        );
      }
    } on Failure {
      // Local sign-out must succeed even when the server revoke call fails.
    } finally {
      await _tokenStore.clear();
    }
  }
}
