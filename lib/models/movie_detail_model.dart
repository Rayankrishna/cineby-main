class MovieDetail {
  final int id;
  final String? title;
  final String? overview;
  final String? tagline;
  final String? posterPath;
  final String? backdropPath;
  final int? runtime;
  final String? releaseDate;
  final double? voteAverage;
  final int? voteCount;
  final String? status;
  final List<Genre> genres;
  final List<CastMember> cast;
  final String? directorName;

  MovieDetail({
    required this.id,
    this.title,
    this.overview,
    this.tagline,
    this.posterPath,
    this.backdropPath,
    this.runtime,
    this.releaseDate,
    this.voteAverage,
    this.voteCount,
    this.status,
    this.genres = const [],
    this.cast = const [],
    this.directorName,
  });

  factory MovieDetail.fromJson(Map<String, dynamic> json) {
    // Parse genres
    final genresList = (json['genres'] as List<dynamic>?)
            ?.map((g) => Genre.fromJson(g as Map<String, dynamic>))
            .toList() ??
        [];

    // Parse cast from credits
    List<CastMember> castList = [];
    String? director;
    if (json['credits'] != null) {
      final credits = json['credits'] as Map<String, dynamic>;
      castList = (credits['cast'] as List<dynamic>?)
              ?.take(20)
              .map((c) => CastMember.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [];

      // Find director from crew
      final crew = credits['crew'] as List<dynamic>?;
      if (crew != null) {
        for (final member in crew) {
          if ((member as Map<String, dynamic>)['job'] == 'Director') {
            director = member['name'] as String?;
            break;
          }
        }
      }
    }

    return MovieDetail(
      id: json['id'] as int,
      title: json['title'] as String?,
      overview: json['overview'] as String?,
      tagline: json['tagline'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      runtime: json['runtime'] as int?,
      releaseDate: json['release_date'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int?,
      status: json['status'] as String?,
      genres: genresList,
      cast: castList,
      directorName: director,
    );
  }
}

class Genre {
  final int id;
  final String name;

  Genre({required this.id, required this.name});

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}

class CastMember {
  final int id;
  final String? name;
  final String? character;
  final String? profilePath;

  CastMember({required this.id, this.name, this.character, this.profilePath});

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      id: json['id'] as int,
      name: json['name'] as String?,
      character: json['character'] as String?,
      profilePath: json['profile_path'] as String?,
    );
  }
}
