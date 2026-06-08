import 'package:json_annotation/json_annotation.dart';

part 'search_model.g.dart';

@JsonSerializable()
class SearchResponse {
  final int page;
  final List<SearchResult> results;
  @JsonKey(name: 'total_pages')
  final int totalPages;
  @JsonKey(name: 'total_results')
  final int totalResults;

  SearchResponse({
    required this.page,
    required this.results,
    required this.totalPages,
    required this.totalResults,
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) =>
      _$SearchResponseFromJson(json);

  Map<String, dynamic> toJson() => _$SearchResponseToJson(this);
}

@JsonSerializable()
class SearchResult {
  final int id;
  final String? title;
  final String? name; // Some results use 'name' instead of 'title'
  @JsonKey(name: 'original_title')
  final String? originalTitle;
  @JsonKey(name: 'original_name')
  final String? originalName;
  final String? overview;
  @JsonKey(name: 'poster_path')
  final String? posterPath;
  @JsonKey(name: 'backdrop_path')
  final String? backdropPath;
  @JsonKey(name: 'media_type')
  final String? mediaType;
  @JsonKey(name: 'release_date')
  final String? releaseDate;
  // TMDB's multi-search returns `first_air_date` for TV results instead of
  // `release_date`. Keeping them separate so we can coalesce via
  // `releaseDate ?? firstAirDate` in scoring / filtering.
  @JsonKey(name: 'first_air_date')
  final String? firstAirDate;
  @JsonKey(name: 'vote_average')
  final double? voteAverage;
  @JsonKey(name: 'vote_count')
  final int? voteCount;

  SearchResult({
    required this.id,
    this.title,
    this.name,
    this.originalTitle,
    this.originalName,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.mediaType,
    this.releaseDate,
    this.firstAirDate,
    this.voteAverage,
    this.voteCount,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) =>
      _$SearchResultFromJson(json);

  Map<String, dynamic> toJson() => _$SearchResultToJson(this);
}
