import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/m3u/episode_title.dart';

Channel _episode(String name) => Channel(
  key: 't:$name',
  name: name,
  categoryId: 'series:x',
  kind: MediaKind.series,
  url: 'http://h/series/u/p/1.mkv',
);

void main() {
  group('parseEpisodeTitle', () {
    test('compact marker', () {
      expect(parseEpisodeTitle('Dark S01E02'), (
        show: 'Dark',
        season: 1,
        episode: 2,
      ));
    });

    test('spaced marker with short numbers', () {
      expect(parseEpisodeTitle('Dark S1 E2'), (
        show: 'Dark',
        season: 1,
        episode: 2,
      ));
    });

    test('prefix and trailing title', () {
      expect(parseEpisodeTitle('ES - Dark - S02 E10 - Título'), (
        show: 'ES - Dark',
        season: 2,
        episode: 10,
      ));
    });

    test('lowercase marker', () {
      expect(parseEpisodeTitle('dark s01e02'), (
        show: 'dark',
        season: 1,
        episode: 2,
      ));
    });

    test('dash before the show-less marker and no pattern', () {
      expect(parseEpisodeTitle('Película 2024'), isNull);
      expect(parseEpisodeTitle('S01E02'), isNull);
      expect(parseEpisodeTitle(''), isNull);
    });
  });

  group('groupM3uEpisodes', () {
    test('groups by show, in first-appearance order, sorted by episode', () {
      final grouped = groupM3uEpisodes([
        _episode('Dark S01E02'),
        _episode('Lost S01E01'),
        _episode('Dark S01E01'),
        _episode('Dark S02E01'),
      ]);
      expect(grouped.keys, ['Dark', 'Lost']);
      expect(grouped['Dark']!.map((c) => c.name), [
        'Dark S01E01',
        'Dark S01E02',
        'Dark S02E01',
      ]);
      expect(grouped['Lost']!.single.name, 'Lost S01E01');
    });

    test('titles without a marker each become their own show', () {
      final grouped = groupM3uEpisodes([
        _episode('Special A'),
        _episode('Special B'),
      ]);
      expect(grouped.keys, ['Special A', 'Special B']);
    });
  });
}
