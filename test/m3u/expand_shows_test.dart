import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/m3u/episode_title.dart';

Channel _ep(String name, String category) => Channel(
  key: 'h:$name',
  name: name,
  categoryId: category,
  kind: MediaKind.series,
  url: 'http://h/series/$name.mp4',
);

void main() {
  test('expandShows completes partial shows from their category', () {
    final category = [
      _ep('Dark S01E01', 'c'),
      _ep('Dark S01E02', 'c'),
      _ep('Dark S01E03', 'c'),
      _ep('Other S01E01', 'c'),
    ];
    final partial = groupM3uEpisodes([category[2]]);
    final full = expandShows(partial, (id) => id == 'c' ? category : const []);
    expect(full.keys, ['Dark']);
    expect(full['Dark']!.map((e) => e.name), [
      'Dark S01E01',
      'Dark S01E02',
      'Dark S01E03',
    ]);
  });

  test('keeps the partial list when the category no longer has the show', () {
    final partial = groupM3uEpisodes([_ep('Gone S01E01', 'x')]);
    final full = expandShows(partial, (_) => const []);
    expect(full['Gone']!, hasLength(1));
  });
}
