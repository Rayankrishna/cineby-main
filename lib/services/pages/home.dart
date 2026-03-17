import 'package:app_web_ui/services/config.dart';
import 'package:app_web_ui/services/pages/webview.dart';

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
                  if (_searchStore.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (_searchStore.errorMessage != null) {
                    return Center(child: Text(_searchStore.errorMessage!));
                  }

                  if (_searchStore.searchResults.isEmpty) {
                    return const Center(child: Text("No results found"));
                  }

                  return ListView.builder(
                    itemCount: _searchStore.searchResults.length,
                    itemBuilder: (context, index) {
                      final result = _searchStore.searchResults[index];
                      return ListTile(
                        leading:
                            result.posterPath != null
                                ? Image.network(
                                  "https://image.tmdb.org/t/p/w200${result.posterPath}",
                                  width: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          const Icon(Icons.movie),
                                )
                                : const Icon(Icons.movie),
                        title: Text(result.title ?? result.name ?? 'Unknown'),
                        subtitle: Text(
                          result.overview ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          print(
                            "gvdsgdgadgswagjnadsadjkosgnopadnoijdasg ${result.id}",
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) =>
                                      MyWidget(url: "$serverurl${result.id}"),
                            ),
                          );
                        },
                      );
                    },
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
