import 'package:app_web_ui/models/movie_detail_model.dart';

class TvDetail {
  final int id;
  final String? name;
  final String? overview;
  final String? tagline;
  final String? posterPath;
  final String? backdropPath;
  final String? firstAirDate;
  final double? voteAverage;
  final int? voteCount;
  final String? status;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final List<Genre> genres;
  final List<CastMember> cast;
  final String? creatorName;
  final List<SeasonSummary> seasons;

  TvDetail({
    required this.id,
    this.name,
    this.overview,
    this.tagline,
    this.posterPath,
    this.backdropPath,
    this.firstAirDate,
    this.voteAverage,
    this.voteCount,
    this.status,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.genres = const [],
    this.cast = const [],
    this.creatorName,
    this.seasons = const [],
  });

  factory TvDetail.fromJson(Map<String, dynamic> json) {
    final genresList =
        (json['genres'] as List<dynamic>?)
            ?.map((g) => Genre.fromJson(g as Map<String, dynamic>))
            .toList() ??
        [];

    List<CastMember> castList = [];
    if (json['credits'] != null) {
      final credits = json['credits'] as Map<String, dynamic>;
      castList =
          (credits['cast'] as List<dynamic>?)
              ?.take(20)
              .map((c) => CastMember.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [];
    }

    String? creator;
    final createdBy = json['created_by'] as List<dynamic>?;
    if (createdBy != null && createdBy.isNotEmpty) {
      creator = (createdBy.first as Map<String, dynamic>)['name'] as String?;
    }

    final seasonsList =
        (json['seasons'] as List<dynamic>?)
            ?.map((s) => SeasonSummary.fromJson(s as Map<String, dynamic>))
            .where((s) => s.seasonNumber > 0)
            .toList() ??
        [];

    return TvDetail(
      id: json['id'] as int,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      tagline: json['tagline'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      firstAirDate: json['first_air_date'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int?,
      status: json['status'] as String?,
      numberOfSeasons: json['number_of_seasons'] as int?,
      numberOfEpisodes: json['number_of_episodes'] as int?,
      genres: genresList,
      cast: castList,
      creatorName: creator,
      seasons: seasonsList,
    );
  }
}

class SeasonSummary {
  final int id;
  final int seasonNumber;
  final String? name;
  final int? episodeCount;
  final String? posterPath;
  final String? airDate;

  SeasonSummary({
    required this.id,
    required this.seasonNumber,
    this.name,
    this.episodeCount,
    this.posterPath,
    this.airDate,
  });

  factory SeasonSummary.fromJson(Map<String, dynamic> json) {
    return SeasonSummary(
      id: json['id'] as int,
      seasonNumber: json['season_number'] as int? ?? 0,
      name: json['name'] as String?,
      episodeCount: json['episode_count'] as int?,
      posterPath: json['poster_path'] as String?,
      airDate: json['air_date'] as String?,
    );
  }
}

class SeasonDetail {
  final int seasonNumber;
  final String? name;
  final String? overview;
  final List<Episode> episodes;

  SeasonDetail({
    required this.seasonNumber,
    this.name,
    this.overview,
    this.episodes = const [],
  });

  factory SeasonDetail.fromJson(Map<String, dynamic> json) {
    final eps =
        (json['episodes'] as List<dynamic>?)
            ?.map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return SeasonDetail(
      seasonNumber: json['season_number'] as int? ?? 0,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      episodes: eps,
    );
  }
}

class Episode {
  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String? name;
  final String? overview;
  final String? stillPath;
  final String? airDate;
  final int? runtime;
  final double? voteAverage;

  Episode({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    this.name,
    this.overview,
    this.stillPath,
    this.airDate,
    this.runtime,
    this.voteAverage,
  });

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id'] as int,
      episodeNumber: json['episode_number'] as int? ?? 0,
      seasonNumber: json['season_number'] as int? ?? 0,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      stillPath: json['still_path'] as String?,
      airDate: json['air_date'] as String?,
      runtime: json['runtime'] as int?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
    );
  }
}
