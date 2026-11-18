import '../../../../core/network/pagination.dart';
import '../entities/match.dart';

abstract interface class MatchRepository {
  Future<Paginated<Match>> getMatches({PageRequest page = const PageRequest()});

  Future<Match> getMatch(String matchId);

  Future<void> unmatch(String matchId);
}
