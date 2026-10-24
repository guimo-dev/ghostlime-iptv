/// Fictional catalog served by the demo server: no real channels, brands or people.
library;

/// Username and password accepted by the demo server.
const demoUser = 'demo';
const demoPassword = 'demo';

/// How far before and after "now" the demo guide reaches.
const guidePast = Duration(hours: 6);
const guideFuture = Duration(hours: 72);

/// Length of every guide programme.
const _programmeLength = Duration(hours: 2);

const liveCategoryNames = {
  '1': 'Noticias Demo',
  '2': 'Deportes Demo',
  '3': 'Cine Demo',
  '4': 'Música Demo',
};

const movieCategoryNames = {
  '11': 'Aventuras Demo',
  '12': 'Comedias Demo',
  '13': 'Misterio Demo',
};

const seriesCategoryNames = {'21': 'Dramas Demo', '22': 'Humor Demo'};

/// Id of the live channel whose stream is cut after a while (the last one).
const unstableChannelId = 24;

/// Six channel names per live category; the first is exactly 120 characters,
/// and the rest mix ñ, emoji and Cyrillic.
final liveChannelNames = <String, List<String>>{
  '1': [
    '${'Canal Largo Demo '.padRight(100, 'x')}${'1234567890'.padRight(20, '-')}',
    'Noticias Mañana Demo',
    'Ночные новости Demo',
    'Telediario Demo 24h',
    'Mundo Demo Hoy',
    'Última Hora Demo',
  ],
  '2': [
    'Fútbol Demo 1 ⚽',
    'Baloncesto Demo',
    'Спорт Demo',
    'Ciclismo Demo',
    'Tenis Demo Pro',
    'Motor Demo 🏎',
  ],
  '3': [
    'Cine Estrella Demo',
    'Cine Clásico Demo',
    'Кино Demo',
    'Estrenos Demo 🎬',
    'Cine Español Demo',
    'Terror Demo',
  ],
  '4': [
    'Radio Visual Demo',
    'Pop Demo 🎵',
    'Музыка Demo',
    'Rock Demo',
    'Jazz Nocturno Demo',
    'Canal inestable (demo)',
  ],
};

const _movieTitles = [
  'La isla del faro perdido',
  'El mapa de las nubes',
  'Los guardianes del valle',
  'Viaje al país de los espejos',
  'La brújula de cristal',
  'Cazadores de estrellas',
  'Una boda sin novio',
  'El pingüino electricista',
  'Vecinos del tercero',
  'Cuatro amigos y un camello',
  'La tarta imposible',
  'Domingo de lluvia y risas',
  'El enigma del reloj parado',
  'Carta sin remitente',
  'La noche del museo vacío',
  'El jardinero invisible',
  'Tres pistas en la niebla',
  'El último tren a ninguna parte',
];

const _seriesTitles = [
  'Valle de las Sombras Demo',
  'Hermanas del Puerto Demo',
  'La Casa Azul Demo',
  'Oficina Rara Demo',
  'Los Vecinos Demo',
  'Cocina Caótica Demo',
];

/// One live channel of the demo catalog.
class DemoChannel {
  const DemoChannel(this.id, this.name, this.categoryId);

  final int id;
  final String name;
  final String categoryId;

  /// Id the guide uses for this channel.
  String get epgId => 'demo.ch$id';
}

/// All 24 live channels, ids 1..24.
final List<DemoChannel> demoChannels = () {
  final channels = <DemoChannel>[];
  liveChannelNames.forEach((categoryId, names) {
    for (final name in names) {
      channels.add(DemoChannel(channels.length + 1, name, categoryId));
    }
  });
  return channels;
}();

/// One movie of the demo catalog.
class DemoMovie {
  const DemoMovie(this.id, this.title, this.categoryId);

  final int id;
  final String title;
  final String categoryId;
}

/// All 18 movies, ids 101..118, six per category.
final List<DemoMovie> demoMovies = [
  for (var i = 0; i < _movieTitles.length; i++)
    DemoMovie(
      101 + i,
      _movieTitles[i],
      movieCategoryNames.keys.elementAt(i ~/ 6),
    ),
];

/// One episode of a demo series.
class DemoEpisode {
  const DemoEpisode(this.id, this.season, this.number, this.title);

  final int id;
  final int season;
  final int number;
  final String title;
}

/// One series of the demo catalog.
class DemoSeries {
  const DemoSeries(this.id, this.title, this.categoryId);

  final int id;
  final String title;
  final String categoryId;

  /// Two seasons of four episodes each; ids are unique across series.
  List<DemoEpisode> get episodes => [
    for (var season = 1; season <= 2; season++)
      for (var number = 1; number <= 4; number++)
        DemoEpisode(
          2000 + (id - 201) * 8 + (season - 1) * 4 + number,
          season,
          number,
          'Episodio $number de la temporada $season',
        ),
  ];
}

/// All 6 series, ids 201..206, three per category.
final List<DemoSeries> demoSeries = [
  for (var i = 0; i < _seriesTitles.length; i++)
    DemoSeries(
      201 + i,
      _seriesTitles[i],
      seriesCategoryNames.keys.elementAt(i ~/ 3),
    ),
];

/// A programme of the demo guide.
class DemoProgramme {
  const DemoProgramme(this.channelId, this.start, this.stop, this.title);

  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;
}

/// Programmes of every channel from `now - guidePast` to `now + guideFuture`.
///
/// Slots are aligned to even UTC hours: the first starts at or before
/// `now - guidePast` and the last starts within 2 h before `now + guideFuture`.
List<DemoProgramme> demoProgrammes(DateTime now) {
  final from = now.toUtc().subtract(guidePast);
  final firstStart = DateTime.utc(
    from.year,
    from.month,
    from.day,
    from.hour - from.hour % _programmeLength.inHours,
  );
  final end = now.toUtc().add(guideFuture);
  final programmes = <DemoProgramme>[];
  for (final channel in demoChannels) {
    var start = firstStart;
    var slot = channel.id;
    while (!start.isAfter(end)) {
      programmes.add(
        DemoProgramme(
          channel.epgId,
          start,
          start.add(_programmeLength),
          'Programa ${slot % 7 + 1} de ${channel.name}',
        ),
      );
      start = start.add(_programmeLength);
      slot++;
    }
  }
  return programmes;
}
