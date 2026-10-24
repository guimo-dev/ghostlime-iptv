# Servidor de demostración

Servidor Xtream Codes / M3U local con un catálogo totalmente inventado (sin canales,
marcas ni personas reales). Sirve para los tests visuales y para revisar la app a mano.
Solo usa `dart:io` y `dart:convert`.

```
dart run tool/demo_server/main.dart --port 8899
```

Imprime la URL y queda escuchando. Credenciales: usuario `demo`, contraseña `demo`.

| Ruta | Contenido |
| --- | --- |
| `/player_api.php?username=demo&password=demo[&action=...]` | API Xtream: 4 categorías y 24 canales de directo, 3 categorías y 18 películas, 2 categorías y 6 series (2 temporadas de 4 episodios) |
| `/playlist.m3u` | Lista M3U con todo lo anterior y `url-tvg` hacia `/xmltv.php` |
| `/xmltv.php` | Guía XMLTV de todos los canales, de ahora-6 h a ahora+72 h |
| `/live/demo/demo/<id>.ts`, `/series/demo/demo/<id>.ts` | El clip de 12 s en bucle, sin fin, a ritmo casi real (chunked) hasta que el cliente se va |
| `/movie/demo/demo/<id>.mp4` | El mismo clip, finito, con `Accept-Ranges: bytes` y respuestas `206` a `Range` |
| `/img/<n>.png` | Póster de color liso con el número `n` |

El canal 24, **Canal inestable (demo)**, corta la conexión a los 45 s de streaming en cada
petición, para reproducir cortes de stream. El bucle repite el clip de 12 s tal cual (un
clip de 10 min no cabe en 3 MB), así que en cada vuelta los timestamps saltan hacia atrás.

Desde código: `final server = await DemoServer.start();` (`baseUrl`, `close()`; `paced: false` envía sin pausas; `unstableCutoff` cambia los 45 s); con
`server.down = true` todas las rutas responden 503.

## Clip

`assets/demo.ts` (H.264 1280x720 25 fps + AAC en silencio, 12 s, < 3 MB) se generó con ffmpeg
(`winget install --id Gyan.FFmpeg -e --scope user`, solo herramienta de desarrollo):

```
ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=25 -f lavfi -i anullsrc=r=48000:cl=stereo -t 12 -c:v libx264 -crf 30 -pix_fmt yuv420p -c:a aac -b:a 16k -f mpegts tool/demo_server/assets/demo.ts
```

(`-crf 30` y `-b:a 16k` se añadieron al comando base: sin ellos el fichero pesaba 4,5 MB. El audio es silencio (`anullsrc`) para que los tests visuales no suenen; antes era un tono de 440 Hz.)
