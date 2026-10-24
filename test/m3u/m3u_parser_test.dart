import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/catalog/catalog_models.dart';
import 'package:iptv_player/m3u/m3u_parser.dart';

const _basic =
    '#EXTM3U\n'
    '#EXTINF:-1 tvg-id="a.es" tvg-logo="http://l/a.png" group-title="Deportes",Canal A\n'
    'http://h/live/u/p/1.ts';

void main() {
  group('parseM3u', () {
    test('parses a basic entry', () {
      final entries = parseM3u(_basic);
      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.name, 'Canal A');
      expect(entry.tvgId, 'a.es');
      expect(entry.tvgLogo, 'http://l/a.png');
      expect(entry.groupTitle, 'Deportes');
      expect(entry.url, 'http://h/live/u/p/1.ts');
    });

    test('handles BOM and CRLF', () {
      final entries = parseM3u('﻿${_basic.replaceAll('\n', '\r\n')}');
      expect(entries.single.name, 'Canal A');
      expect(entries.single.url, 'http://h/live/u/p/1.ts');
    });

    test('splits name at the first comma outside quotes', () {
      final entries = parseM3u(
        '#EXTM3U\n'
        '#EXTINF:-1 group-title="Cine, Series",Película, la\n'
        'http://h/movie/u/p/2.mkv',
      );
      expect(entries.single.groupTitle, 'Cine, Series');
      expect(entries.single.name, 'Película, la');
    });

    test('skips blank lines and other directives before the URL', () {
      final entries = parseM3u(
        '#EXTM3U\n'
        '#EXTINF:-1,Canal B\n'
        '\n'
        '#EXTVLCOPT:http-user-agent=X\n'
        'http://h/2',
      );
      expect(entries.single.name, 'Canal B');
      expect(entries.single.url, 'http://h/2');
    });

    test('drops an EXTINF without URL', () {
      final entries = parseM3u(
        '#EXTM3U\n'
        '#EXTINF:-1,Sin URL\n'
        '#EXTINF:-1,Con URL\n'
        'http://h/3',
      );
      expect(entries.map((e) => e.name), ['Con URL']);
    });

    test('uses the URL as name when there is no EXTINF', () {
      final entries = parseM3u('#EXTM3U\nhttp://h/4');
      expect(entries.single.name, 'http://h/4');
    });

    test('ignores lines that are not URLs (e.g. an HTML error page)', () {
      expect(parseM3u('<html>\n<body>login</body>\n</html>'), isEmpty);
    });

    test('ignores HTML lines that contain URLs', () {
      expect(
        parseM3u(
          '<html>\n<link href="https://cdn/x.css">\n'
          '<a href="http://h/renew">Renovar</a>\n</html>',
        ),
        isEmpty,
      );
    });

    test('empty attributes become null', () {
      final entries = parseM3u('#EXTM3U\n#EXTINF:-1 tvg-id="",C\nhttp://h/5');
      expect(entries.single.tvgId, isNull);
    });
  });

  group('parseM3uTvgUrl', () {
    test('takes the first url-tvg', () {
      expect(
        parseM3uTvgUrl(
          '#EXTM3U url-tvg="http://a/epg.xml.gz,http://b"\n$_basic',
        ),
        'http://a/epg.xml.gz',
      );
    });

    test('accepts x-tvg-url, BOM and CRLF', () {
      expect(
        parseM3uTvgUrl('﻿#EXTM3U x-tvg-url="http://a/e.xml"\r\n$_basic'),
        'http://a/e.xml',
      );
    });

    test('reads url-tvg from a second #EXTM3U line (TDTChannels)', () {
      expect(
        parseM3uTvgUrl(
          '#EXTM3U @LaQuay https://github.com/LaQuay/TDTChannels\n'
          '#EXTM3U url-tvg="https://www.tdtchannels.com/epg/TV.xml.gz"\n'
          '#EXTINF:-1 tvg-id="La1.TV" group-title="Generalistas",La 1\n'
          'https://rtvelivestream.rtve.es/rtvesec/la1/la1_main_dvr.m3u8\n',
        ),
        'https://www.tdtchannels.com/epg/TV.xml.gz',
      );
    });

    test('ignores #EXTM3U lines after the first entry', () {
      expect(
        parseM3uTvgUrl('$_basic\n#EXTM3U url-tvg="http://late/e.xml"\n'),
        isNull,
      );
    });

    test('is null without the attribute', () {
      expect(parseM3uTvgUrl(_basic), isNull);
      expect(parseM3uTvgUrl('#EXTM3U\n$_basic'), isNull);
      expect(parseM3uTvgUrl('#EXTM3U url-tvg=""\n'), isNull);
    });
  });

  group('classifyStreamUrl', () {
    test('detects movies, series and live', () {
      expect(classifyStreamUrl('http://h/movie/u/p/9.mkv'), MediaKind.movie);
      expect(classifyStreamUrl('http://h/series/u/p/9.mp4'), MediaKind.series);
      expect(classifyStreamUrl('http://h/live/u/p/9.ts'), MediaKind.live);
      expect(classifyStreamUrl('http://x/9'), MediaKind.live);
    });
  });
}
