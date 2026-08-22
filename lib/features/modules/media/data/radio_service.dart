import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:church_on_app/core/providers/audio_provider.dart';

class RadioStation {
  final String id;
  final String name;
  final String streamUrl;
  final String location;
  final bool isPrivate;
  String currentTrack;

  RadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    required this.location,
    this.isPrivate = false,
    this.currentTrack = "Connecting...",
  });

  factory RadioStation.fromMap(Map<String, dynamic> map) {
    return RadioStation(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      streamUrl: map['stream_url']?.toString() ?? '',
      location: map['location']?.toString() ?? '',
      isPrivate: map['is_private'] == true,
    );
  }
}

class RadioService {
  final AudioHandler? _handler;

  /// Lazy client access — constructing the service must not require Supabase
  /// to be initialized (unit tests construct it bare; fetchStations falls
  /// back to the curated offline list when the client is unavailable).
  SupabaseClient get _client => Supabase.instance.client;
  RadioService(this._handler);

  Future<List<RadioStation>> fetchStations() async {
    try {
      final data = await _client.from('radio_stations').select().order('name');
      return data.map<RadioStation>((map) => RadioStation.fromMap(map)).toList();
    } catch (e) {
      debugPrint("Error fetching radio stations: $e");
      return _fallbackStations();
    }
  }

  /// Offline fallback — Christian stations only, from Zambia + worldwide.
  List<RadioStation> _fallbackStations() {
    return [
      RadioStation(id: '1', name: "Radio Christian Voice", location: "Lusaka, Zambia", streamUrl: "http://stream.rcv.co.zm:8000/stream"),
      RadioStation(id: '2', name: "United Voice Radio", location: "Lusaka, Zambia", streamUrl: "https://streaming.unitedvoice.radio/stream"),
      RadioStation(id: '3', name: "Radio Maria Zambia", location: "Zambia", streamUrl: "http://net.radiomaria.org.ar:8000/Zamba"),
      RadioStation(id: '4', name: "Radio Icengelo", location: "Copperbelt, Zambia", streamUrl: "http://45.89.84.148:8000/radio.mp3"),
      RadioStation(id: '5', name: "Yatsani Radio", location: "Lusaka, Zambia", streamUrl: "http://yatsaniradio.stream:80/live"),
      RadioStation(id: '6', name: "Faith FM", location: "Lusaka, Zambia", streamUrl: "http://stream.faithfm.co.zm:8000/live"),
      RadioStation(id: '7', name: "Crossroads Radio", location: "Canada", streamUrl: "https://stream.crossroads.ca/live"),
      RadioStation(id: '8', name: "TBN Radio", location: "USA", streamUrl: "https://stream.tbn.org/tbnradio"),
      RadioStation(id: '9', name: "K-LOVE Radio", location: "USA", streamUrl: "https://emf.streamguys1.com/klove_mp3"),
      RadioStation(id: '10', name: "Premier Christian", location: "UK", streamUrl: "https://premier.live.wostreaming.net/web-mp3"),
      RadioStation(id: '11', name: "Hope FM Kenya", location: "Kenya", streamUrl: "https://icecast.hopefm.co.ke/hopefm"),
      RadioStation(id: '12', name: "Inspiration FM Lagos", location: "Nigeria", streamUrl: "https://inspirationfm.radioca.st/stream"),
      RadioStation(id: '13', name: "Family Radio", location: "USA", streamUrl: "https://stream.familyradio.org/fr-mp3"),
      RadioStation(id: '14', name: "Spirit FM Zambia", location: "Global", streamUrl: "https://stream.radiojar.com/atdu3k9s1ceuv"),
    ];
  }

  /// Fetches playable Christian stations from radio-browser.info (worldwide,
  /// community-voted). Falls back to a curated list if the API is unreachable.
  Future<List<RadioStation>> fetchGlobalChristianStations() async {
    const hosts = [
      'de1.api.radio-browser.info',
      'at1.api.radio-browser.info',
      'nl1.api.radio-browser.info',
    ];
    for (final host in hosts) {
      try {
        final uri = Uri.https(host, '/json/stations/search', {
          'tag': 'christian',
          'order': 'votes',
          'reverse': 'true',
          'limit': '30',
          'hidebroken': 'true',
        });
        final res = await http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final list = jsonDecode(res.body) as List;
        final stations = <RadioStation>[];
        final seen = <String>{};
        for (final s in list) {
          if (s is! Map<String, dynamic>) continue;
          final name = s['name']?.toString().trim() ?? '';
          final url = s['url_resolved']?.toString().trim() ?? '';
          if (name.isEmpty || url.isEmpty) continue;
          if (!url.startsWith('http')) continue;
          final lower = name.toLowerCase();
          if (lower.contains('test') || lower.contains('private')) continue;
          if (!seen.add(lower)) continue;
          stations.add(RadioStation(
            id: 'gb_${s['stationuuid']}',
            name: name,
            streamUrl: url,
            location: s['country']?.toString() ?? 'Global',
          ));
        }
        if (stations.isNotEmpty) return stations;
      } catch (e) {
        debugPrint('radio-browser fetch failed ($host): $e');
      }
    }
    return _fallbackStations().skip(6).take(8).toList();
  }

  Future<void> addStation({
    required String name,
    required String streamUrl,
    required String location,
    required bool isPrivate,
  }) async {
    await _client.from('radio_stations').insert({
      'name': name,
      'stream_url': streamUrl,
      'location': location,
      'is_private': isPrivate,
    });
  }

  Future<void> updateStation(String id, Map<String, dynamic> data) async {
    await _client.from('radio_stations').update(data).eq('id', id);
  }

  Future<void> deleteStation(String id) async {
    await _client.from('radio_stations').delete().eq('id', id);
  }

  Future<void> playStation(RadioStation station) async {
    if (_handler == null) return;
    await _handler.playFromUri(Uri.parse(station.streamUrl), {
      'title': station.name,
      'album': "Radio",
      'artist': station.location,
    });
  }

  Future<void> pause() => _handler?.pause() ?? Future.value();
  Future<void> stop() => _handler?.stop() ?? Future.value();
  Future<void> play() => _handler?.play() ?? Future.value();

  Stream<String> getMetadataStream(String stationName) async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 10));
      final tracks = [
        "LIVE: Afternoon Worship Hub",
        "PREACHING: The Power of Perseverance",
        "MUSIC: Pompi - Simuuzeni",
        "LIVE: News at Top of the Hour",
        "PRAYER: National Intercession Session"
      ];
      yield tracks[DateTime.now().second % tracks.length];
    }
  }

  Future<String> fetchLiveMetadata(String stationUrl) async {
    return "LIVE: 24/7 Content";
  }
}

final radioServiceProvider = Provider((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return RadioService(handler);
});

final radioStationsFutureProvider = FutureProvider<List<RadioStation>>((ref) async {
  return ref.watch(radioServiceProvider).fetchStations();
});

final globalChristianStationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  return ref.watch(radioServiceProvider).fetchGlobalChristianStations();
});

final radioMetadataProvider = StreamProvider.family<String, String>((ref, stationName) {
  return ref.watch(radioServiceProvider).getMetadataStream(stationName);
});
