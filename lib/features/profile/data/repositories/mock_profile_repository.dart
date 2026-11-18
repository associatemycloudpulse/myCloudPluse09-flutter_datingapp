import '../../../../core/errors/failure.dart';
import '../../../../dev/mock/mock_backend.dart';
import '../../domain/entities/login_activity.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

class MockProfileRepository implements ProfileRepository {
  MockProfileRepository(this._backend);

  final MockBackend _backend;

  MyProfile _myProfile() => MyProfile(
    profile: _backend.me,
    preferences: _backend.preferences,
    phoneNumber: _backend.phoneNumber,
  );

  @override
  Future<MyProfile> getMyProfile() => _backend.run('getMyProfile', _myProfile);

  @override
  Future<MyProfile> updateMyProfile(ProfileUpdate update) async {
    final profile = await _updateMyProfile(update);
    await _backend.saveAccount();
    return profile;
  }

  @override
  Future<DatingPreferences> updatePreferences(
    DatingPreferences preferences,
  ) async {
    final saved = await _updatePreferences(preferences);
    await _backend.saveAccount();
    return saved;
  }

  Future<MyProfile> _updateMyProfile(ProfileUpdate update) =>
      _backend.run('updateMyProfile', () {
        final name = update.displayName?.trim();
        if (name != null && (name.isEmpty || name.length > 40)) {
          throw const Failure(
            ErrorCode.validationError,
            details: [FieldError(field: 'displayName', reason: 'LENGTH_1_40')],
          );
        }
        if (update.interests != null &&
            (update.interests!.isEmpty || update.interests!.length > 10)) {
          throw const Failure(
            ErrorCode.validationError,
            details: [FieldError(field: 'interests', reason: 'COUNT_1_10')],
          );
        }
        _backend.me = _backend.me.copyWith(
          displayName: name,
          bio: update.bio,
          interests: update.interests,
          basics: update.basics,
        );
        return _myProfile();
      });

  Future<DatingPreferences> _updatePreferences(DatingPreferences preferences) =>
      _backend.run('updatePreferences', () {
        if (preferences.minAge < 18 ||
            preferences.minAge > preferences.maxAge) {
          throw const Failure(
            ErrorCode.validationError,
            details: [FieldError(field: 'minAge', reason: 'OUT_OF_RANGE')],
          );
        }
        return _backend.preferences = preferences;
      });

  @override
  Future<UserProfile> getProfile(String userId) =>
      _backend.run('getProfile', () {
        if (_backend.blockedIds.contains(userId)) {
          throw const Failure(ErrorCode.notFound);
        }
        return _backend.profiles[userId] ??
            (throw const Failure(ErrorCode.notFound));
      });

  @override
  Future<MyProfile> addPhoto(String mediaId) async {
    final profile = await _backend.run('addPhoto', () {
      final path = _backend.media[mediaId];
      if (path == null) {
        throw const Failure(
          ErrorCode.mediaRejected,
          details: [FieldError(field: 'mediaId', reason: 'NOT_READY')],
        );
      }
      final urls = _withIds(_backend.me);
      if (urls.photoUrls.length >= 6) {
        throw const Failure(ErrorCode.conflict);
      }
      _backend.me = urls.copyWith(
        photoUrls: [...urls.photoUrls, path],
        photoIds: [...urls.photoIds, 'pho_$mediaId'],
      );
      return _myProfile();
    });
    await _backend.saveAccount();
    return profile;
  }

  @override
  Future<MyProfile> removePhoto(String photoId) async {
    final profile = await _backend.run('removePhoto', () {
      final current = _withIds(_backend.me);
      final index = current.photoIds.indexOf(photoId);
      if (index < 0) throw const Failure(ErrorCode.notFound);
      if (current.photoUrls.length < 2) {
        throw const Failure(ErrorCode.conflict);
      }
      final urls = [...current.photoUrls]..removeAt(index);
      final ids = [...current.photoIds]..removeAt(index);
      _backend.me = current.copyWith(photoUrls: urls, photoIds: ids);
      return _myProfile();
    });
    await _backend.saveAccount();
    return profile;
  }

  @override
  Future<MyProfile> setInterests(List<String> interestIds) async {
    if (interestIds.isEmpty || interestIds.length > 10) {
      throw const Failure(
        ErrorCode.validationError,
        details: [FieldError(field: 'interestIds', reason: 'COUNT_1_10')],
      );
    }
    return updateMyProfile(ProfileUpdate(interests: interestIds));
  }

  @override
  Future<MyProfile> reorderPhotos(List<String> photoIds) async {
    final profile = await _backend.run('reorderPhotos', () {
      final current = _withIds(_backend.me);
      if (photoIds.length != current.photoIds.length ||
          !photoIds.every(current.photoIds.contains)) {
        throw const Failure(ErrorCode.validationError);
      }
      final urls = [
        for (final id in photoIds)
          current.photoUrls[current.photoIds.indexOf(id)],
      ];
      _backend.me = current.copyWith(photoUrls: urls, photoIds: photoIds);
      return _myProfile();
    });
    await _backend.saveAccount();
    return profile;
  }

  @override
  Future<List<LoginActivity>> loginActivity() =>
      _backend.run('loginActivity', () {
        return [
          LoginActivity(
            id: 'login_1',
            at: _backend.now(),
            platform: 'ANDROID',
            city: _backend.me.city,
          ),
        ];
      });

  @override
  Future<MediaInfo> getMedia(String mediaId) => _backend.run('getMedia', () {
    final path = _backend.media[mediaId];
    if (path == null) throw const Failure(ErrorCode.notFound);
    return MediaInfo(id: mediaId, url: path, purpose: 'PROFILE_PHOTO');
  });

  UserProfile _withIds(UserProfile profile) {
    if (profile.photoIds.length == profile.photoUrls.length) return profile;
    return profile.copyWith(
      photoIds: [
        for (var i = 0; i < profile.photoUrls.length; i++) 'pho_${profile.id}_$i',
      ],
    );
  }
}
