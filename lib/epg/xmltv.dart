import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../xtream/xtream_client.dart';
import 'programme.dart';

final _timePattern = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\s*([+-])(\d{2})(\d{2}))?$',
);

/// Length given to a programme with no `stop` and no later programme to end at.
const _defaultDuration = Duration(hours: 1);

/// Parses an XMLTV time (`YYYYMMDDhhmmss[ ±hhmm]`) into UTC; no offset means
/// UTC. Returns `null` when [value] is not a valid time.
DateTime? parseXmltvTime(String value) {
  final match = _timePattern.firstMatch(value.trim());
  if (match == null) return null;
  int part(int group) => int.parse(match.group(group)!);
  final time = DateTime.utc(
    part(1),
    part(2),
    part(3),
    part(4),
    part(5),
    part(6),
  );
  // DateTime normalises overflows (month 13, day 40...); reject those.
  if (time.month != part(2) || time.day != part(3) || part(4) > 23) return null;
  if (match.group(7) == null) return time;
  final offset = Duration(hours: part(8), minutes: part(9));
  return match.group(7) == '+' ? time.subtract(offset) : time.add(offset);
}

/// Streams an XMLTV document and returns the programmes of [channelIds] that
/// end after [from] and start before [to], sorted by channel and start.
///
/// Detects gzip by its header, decodes UTF-8 tolerating malformed bytes and a
/// BOM. A programme without `stop` ends when the next one of its channel
/// starts (one hour if it is the last). Programmes with no valid `start` or no
/// title are dropped. Throws [XtreamException] when the XML is malformed.
Future<List<Programme>> parseXmltv(
  Stream<List<int>> bytes, {
  required Set<String> channelIds,
  required DateTime from,
  required DateTime to,
}) async {
  final raw = <_RawProgramme>[];
  _RawProgramme? current;
  String? field;
  final text = StringBuffer();
  try {
    final events = (await _decodeText(bytes))
        .toXmlEvents()
        .normalizeEvents()
        .flatten();
    await for (final event in events) {
      if (event is XmlStartElementEvent) {
        if (event.name == 'programme') {
          current = _startProgramme(event, channelIds, to);
        } else if (current != null &&
            !event.isSelfClosing &&
            (event.name == 'title' || event.name == 'desc')) {
          field = event.name;
          text.clear();
        }
      } else if (event is XmlTextEvent && field != null) {
        text.write(event.value);
      } else if (event is XmlCDATAEvent && field != null) {
        text.write(event.value);
      } else if (event is XmlEndElementEvent) {
        if (event.name == field && current != null) {
          final value = text.toString().trim();
          if (field == 'title') current.title ??= value;
          if (field == 'desc') current.description ??= value;
          field = null;
        } else if (event.name == 'programme') {
          if (current != null && current.title?.isNotEmpty == true) {
            raw.add(current);
          }
          current = null;
          field = null;
        }
      }
    }
  } on XmlException {
    throw const XtreamException(
      'La guía de programación no tiene un formato válido.',
    );
  }
  return _resolve(raw, from);
}

/// Reads the attributes of a `<programme>` start tag; `null` when the channel
/// is not wanted, the start is invalid or it starts after [to].
_RawProgramme? _startProgramme(
  XmlStartElementEvent event,
  Set<String> channelIds,
  DateTime to,
) {
  String? attribute(String name) {
    for (final a in event.attributes) {
      if (a.name == name) return a.value;
    }
    return null;
  }

  final channel = attribute('channel');
  if (channel == null || !channelIds.contains(channel)) return null;
  final start = parseXmltvTime(attribute('start') ?? '');
  if (start == null || !start.isBefore(to)) return null;
  final stopText = attribute('stop');
  return _RawProgramme(
    channel,
    start,
    stopText == null ? null : parseXmltvTime(stopText),
  );
}

/// Sorts by (channel, start), fills missing stops and drops what ended
/// before [from].
List<Programme> _resolve(List<_RawProgramme> raw, DateTime from) {
  raw.sort((a, b) {
    final byChannel = a.channelId.compareTo(b.channelId);
    return byChannel != 0 ? byChannel : a.start.compareTo(b.start);
  });
  final result = <Programme>[];
  for (var i = 0; i < raw.length; i++) {
    final p = raw[i];
    var stop = p.stop;
    if (stop == null) {
      final next = i + 1 < raw.length ? raw[i + 1] : null;
      final nextStart = next != null && next.channelId == p.channelId
          ? next.start
          : null;
      stop = nextStart != null && nextStart.isAfter(p.start)
          ? nextStart
          : p.start.add(_defaultDuration);
    }
    if (!stop.isAfter(from)) continue;
    result.add(
      Programme(
        channelId: p.channelId,
        start: p.start,
        stop: stop,
        title: p.title!,
        description: p.description?.isEmpty == true ? null : p.description,
      ),
    );
  }
  return result;
}

/// Gunzips [bytes] when they start with the gzip magic number, then decodes
/// UTF-8 (tolerating malformed bytes) and strips a leading BOM.
Future<Stream<String>> _decodeText(Stream<List<int>> bytes) async {
  final iterator = StreamIterator(bytes);
  if (!await iterator.moveNext()) return const Stream.empty();
  final first = iterator.current;
  Stream<List<int>> whole() async* {
    yield first;
    while (await iterator.moveNext()) {
      yield iterator.current;
    }
  }

  final isGzip = first.length >= 2 && first[0] == 0x1f && first[1] == 0x8b;
  final plain = isGzip ? gzip.decoder.bind(whole()) : whole();
  var atStart = true;
  return const Utf8Decoder(allowMalformed: true).bind(plain).map((chunk) {
    if (!atStart) return chunk;
    atStart = false;
    return chunk.startsWith('﻿') ? chunk.substring(1) : chunk;
  });
}

/// A programme being read; the stop may still be missing.
class _RawProgramme {
  _RawProgramme(this.channelId, this.start, this.stop);

  final String channelId;
  final DateTime start;
  final DateTime? stop;
  String? title;
  String? description;
}

/// Downloads the XMLTV guide at [url] and parses it as [parseXmltv] does,
/// all inside a separate isolate so the UI never stalls.
///
/// A non-200 response, a network error or an unreadable guide throw
/// [XtreamException] with a Spanish message that never contains the URL.
Future<List<Programme>> fetchXmltv(
  Uri url, {
  required Set<String> channelIds,
  required DateTime from,
  required DateTime to,
  String? userAgent,
}) => Isolate.run(() async {
  final client = http.Client();
  try {
    final http.StreamedResponse response;
    try {
      response = await client
          .send(
            http.Request('GET', url)
              ..headers.addAll({'User-Agent': ?userAgent}),
          )
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      // Network errors embed the URL (which may hold credentials).
      throw const XtreamException('No se puede descargar la guía.');
    }
    if (response.statusCode != 200) {
      throw XtreamException(
        'La guía ha respondido con un error (HTTP ${response.statusCode}).',
      );
    }
    try {
      return await parseXmltv(
        response.stream.timeout(const Duration(seconds: 60)),
        channelIds: channelIds,
        from: from,
        to: to,
      );
    } on XtreamException {
      rethrow;
    } catch (_) {
      throw const XtreamException('No se puede descargar la guía.');
    }
  } finally {
    client.close();
  }
});
