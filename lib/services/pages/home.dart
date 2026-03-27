import 'package:app_web_ui/services/pages/movie_detail_page.dart';

import 'package:app_web_ui/stores/search_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final SearchStore _searchStore = SearchStore();

  @override
  void initState() {
    super.initState();
    _searchStore.fetchTrendingResults();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  _searchStore.setSearchQuery(value);
                },
              ),
            ),
            Expanded(
              child: Observer(
                builder: (_) {
                  if (_searchStore.isLoading &&
                      _searchStore.searchResults.isEmpty &&
                      _searchStore.trendingResults.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (_searchStore.errorMessage != null) {
                    return Center(child: Text(_searchStore.errorMessage!));
                  }

                  final results =
                      _searchStore.searchQuery.isNotEmpty
                          ? _searchStore.searchResults
                          : _searchStore.trendingResults;

                  if (results.isEmpty) {
                    return const Center(child: Text("No results found"));
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_searchStore.searchQuery.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            "Trending Today",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.6,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final result = results[index];
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => MovieDetailPage(
                                          movieId: result.id,
                                        ),
                                  ),
                                );
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child:
                                          result.posterPath != null
                                              ? Image.network(
                                                "https://image.tmdb.org/t/p/w300${result.posterPath}",
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => const Center(
                                                      child: Icon(Icons.movie),
                                                    ),
                                              )
                                              : const Center(
                                                child: Icon(Icons.movie),
                                              ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    result.title ?? result.name ?? 'Unknown',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
