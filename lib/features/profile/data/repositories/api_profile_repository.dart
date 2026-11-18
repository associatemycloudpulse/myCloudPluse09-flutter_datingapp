import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/json.dart';
import '../../domain/entities/login_activity.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../models/profile_dto.dart';

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._client);

  final ApiClient _client;

  @override
  Future<MyProfile> getMyProfile() async =>
      MyProfileDto.fromJson(asJson(await _client.get(ApiEndpoints.myProfile)));

  @override
  Future<MyProfile> updateMyProfile(ProfileUpdate update) async =>
      MyProfileDto.fromJson(
        asJson(
          await _client.patch(ApiEndpoints.myProfile, body: update.toJson()),
        ),
      );

  @override
  Future<DatingPreferences> updatePreferences(
    DatingPreferences preferences,
  ) async => DatingPreferencesDto.fromJson(
    asJson(
      await _client.put(
        ApiEndpoints.myPreferences,
        body: DatingPreferencesDto.toJson(preferences),
      ),
    ),
  );

  @override
  Future<UserProfile> getProfile(String userId) async =>
      UserProfileDto.fromJson(
        asJson(await _client.get(ApiEndpoints.profile(userId))),
      ).toEntity();

  @override
  Future<MyProfile> addPhoto(String mediaId) async => MyProfileDto.fromJson(
    asJson(
      await _client.post(ApiEndpoints.profilePhotos, body: {'mediaId': mediaId}),
    ),
  );

  @override
  Future<MyProfile> removePhoto(String photoId) async => MyProfileDto.fromJson(
    asJson(await _client.delete(ApiEndpoints.profilePhoto(photoId))),
  );

  @override
  Future<MyProfile> setInterests(List<String> interestIds) async =>
      MyProfileDto.fromJson(
        asJson(
          await _client.put(
            ApiEndpoints.profileInterests,
            body: {'interestIds': interestIds},
          ),
        ),
      );

  @override
  Future<MyProfile> reorderPhotos(List<String> photoIds) async =>
      MyProfileDto.fromJson(
        asJson(
          await _client.patch(
            ApiEndpoints.profilePhotoOrder,
            body: {'photoIds': photoIds},
          ),
        ),
      );

  @override
  Future<List<LoginActivity>> loginActivity() async {
    final data = asJson(await _client.get(ApiEndpoints.profileLoginActivity));
    return [
      for (final json in asJsonList(data['items'], 'items'))
        LoginActivity(
          id: json.req<String>('id'),
          at: json.reqDate('at'),
          platform: json.opt<String>('platform'),
          ip: json.opt<String>('ip'),
          city: json.opt<String>('city'),
        ),
    ];
  }

  @override
  Future<MediaInfo> getMedia(String mediaId) async {
    final json = asJson(await _client.get(ApiEndpoints.media(mediaId)));
    return MediaInfo(
      id: json.req<String>('id'),
      url: json.req<String>('url'),
      purpose: json.req<String>('purpose'),
    );
  }
}
