import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/catalog/sorting.dart';

Channel _ch(String key, String name) => Channel(
  key: key,
  name: name,
  categoryId: 'c',
  kind: MediaKind.live,
  streamId: 1,
);

Category _cat(String id) =>
    Category(id: id, name: id.toUpperCase(), kind: MediaKind.live);

List<String> _names(List<Channel> channels) =>
    channels.map((c) => c.name).toList();

List<String> _keys(List<Channel> channels) =>
    channels.map((c) => c.key).toList();

final _channels = [
  _ch('a', 'Canal 10'),
  _ch('b', 'canal 2'),
  _ch('c', 'Ábaco'),
  _ch('d', 'zeta'),
];

void main() {
  test('foldText lowercases and strips diacritics', () {
    expect(foldText('TELEDIÁRIO Ñandú Çà'), 'telediario nandu ca');
  });

  test('naturalCompare orders numbers and accents naturally', () {
    final names = ['Canal 10', 'canal 2', 'Ábaco', 'zeta']
      ..sort(naturalCompare);
    expect(names, ['Ábaco', 'canal 2', 'Canal 10', 'zeta']);
  });

  group('sortChannels', () {
    test('original keeps provider order', () {
      expect(_keys(sortChannels(_channels, const ChannelSort(), {})), [
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('alphabetical ascending and descending', () {
      expect(
        _names(
          sortChannels(
            _channels,
            const ChannelSort(mode: SortMode.alphaAsc),
            {},
          ),
        ),
        ['Ábaco', 'canal 2', 'Canal 10', 'zeta'],
      );
      expect(
        _names(
          sortChannels(
            _channels,
            const ChannelSort(mode: SortMode.alphaDesc),
            {},
          ),
        ),
        ['zeta', 'Canal 10', 'canal 2', 'Ábaco'],
      );
    });

    test('manual puts saved keys first, then the rest in original order', () {
      const sort = ChannelSort(mode: SortMode.manual, manualOrder: ['c', 'a']);
      expect(_keys(sortChannels(_channels, sort, {})), ['c', 'a', 'b', 'd']);
    });

    test('favorites first with alphabetical order inside each block', () {
      const sort = ChannelSort(mode: SortMode.alphaAsc, favoritesFirst: true);
      expect(_names(sortChannels(_channels, sort, {'d', 'b'})), [
        'canal 2',
        'zeta',
        'Ábaco',
        'Canal 10',
      ]);
    });

    test('favorites first keeps manual order inside each block', () {
      const sort = ChannelSort(
        mode: SortMode.manual,
        favoritesFirst: true,
        manualOrder: ['d', 'c', 'b', 'a'],
      );
      expect(_keys(sortChannels(_channels, sort, {'a', 'c'})), [
        'c',
        'a',
        'd',
        'b',
      ]);
    });
  });

  test('sorts 7500 channels A-Z in under 300 ms', () {
    final many = [
      for (var i = 0; i < 7500; i++)
        _ch(
          'k$i',
          '${i.isEven ? 'Ábaco' : 'Zeta'} película ${(i * 7919) % 7500} (20${i % 25})',
        ),
    ];
    final watch = Stopwatch()..start();
    final sorted = sortChannels(
      many,
      const ChannelSort(mode: SortMode.alphaAsc),
      {},
    );
    watch.stop();
    expect(sorted, hasLength(7500));
    expect(watch.elapsedMilliseconds, lessThan(300));
  });

  test('applyManualOrder drops missing keys and appends new ones', () {
    expect(applyManualOrder(['a', 'b', 'e'], ['c', 'b', 'a']), ['b', 'a', 'e']);
  });

  group('mergeManualOrder', () {
    test('keeps absent saved keys after their previous neighbour', () {
      // x was saved between a and b but is missing from the edited list.
      expect(mergeManualOrder(['b', 'a', 'c'], ['a', 'x', 'b', 'c']), [
        'b',
        'a',
        'x',
        'c',
      ]);
    });

    test('absent key with no present predecessor goes first', () {
      expect(mergeManualOrder(['b', 'a'], ['x', 'a', 'b']), ['x', 'b', 'a']);
    });

    test('nothing absent returns the edited order', () {
      expect(mergeManualOrder(['b', 'a'], ['a', 'b']), ['b', 'a']);
    });
  });

  group('sortCategories', () {
    final categories = [_cat('b'), _cat('a'), _cat('c')];

    test('hides hidden categories unless asked', () {
      const sort = CategorySort(hidden: {'a'});
      expect(sortCategories(categories, sort).map((c) => c.id), ['b', 'c']);
      expect(
        sortCategories(categories, sort, includeHidden: true).map((c) => c.id),
        ['b', 'a', 'c'],
      );
    });

    test('manual and alphabetical modes', () {
      expect(
        sortCategories(
          categories,
          const CategorySort(mode: SortMode.manual, manualOrder: ['c']),
        ).map((c) => c.id),
        ['c', 'b', 'a'],
      );
      expect(
        sortCategories(
          categories,
          const CategorySort(mode: SortMode.alphaAsc),
        ).map((c) => c.id),
        ['a', 'b', 'c'],
      );
    });
  });

  group('json', () {
    test('ChannelSort round-trips', () {
      const sort = ChannelSort(
        mode: SortMode.manual,
        favoritesFirst: true,
        manualOrder: ['x', 'y'],
      );
      final copy = ChannelSort.fromJson(sort.toJson());
      expect(copy.mode, SortMode.manual);
      expect(copy.favoritesFirst, isTrue);
      expect(copy.manualOrder, ['x', 'y']);
    });

    test('CategorySort round-trips', () {
      const sort = CategorySort(
        mode: SortMode.alphaDesc,
        manualOrder: ['a'],
        hidden: {'h'},
      );
      final copy = CategorySort.fromJson(sort.toJson());
      expect(copy.mode, SortMode.alphaDesc);
      expect(copy.manualOrder, ['a']);
      expect(copy.hidden, {'h'});
    });

    test('empty or unknown json gives defaults', () {
      expect(ChannelSort.fromJson({}).mode, SortMode.original);
      expect(ChannelSort.fromJson({}).favoritesFirst, isFalse);
      expect(ChannelSort.fromJson({'mode': 'weird'}).mode, SortMode.original);
      expect(CategorySort.fromJson({}).hidden, isEmpty);
    });
  });
}
