import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final SupabaseClient _client = Supabase.instance.client;
  RadioService(this._handler);

  Future<List<RadioStation>> fetchStations() async {
    try {
      final data = await _client.from('radio_stations').select().order('name');
      return data.map<RadioStation>((map) => RadioStation.fromMap(map)).toList();
    } catch (e) {
      debugPrint("Error fetching radio stations: $e");
      return [
        RadioStation(id: '1', name: "Radio Christian Voice", location: "Lusaka, Zambia", streamUrl: "http://stream.rcv.co.zm:8000/stream"),
        RadioStation(id: '2', name: "United Voice Radio", location: "Lusaka, Zambia", streamUrl: "https://streaming.unitedvoice.radio/stream"),
        RadioStation(id: '3', name: "Radio Maria Zambia", location: "Zambia", streamUrl: "http://net.radiomaria.org.ar:8000/Zamba"),
        RadioStation(id: '4', name: "Radio Icengelo", location: "Copperbelt, Zambia", streamUrl: "http://45.89.84.148:8000/radio.mp3"),
        RadioStation(id: '5', name: "Yatsani Radio", location: "Lusaka, Zambia", streamUrl: "http://yatsaniradio.stream:80/live"),
        RadioStation(id: '6', name: "Faith FM", location: "Lusaka, Zambia", streamUrl: "http://stream.faithfm.co.zm:8000/live"),
        RadioStation(id: '7', name: "Crossroads Radio", location: "International", streamUrl: "http://stream.crossroads.ca:8000/live"),
        RadioStation(id: '8', name: "TBN Radio", location: "International", streamUrl: "http://stream.tbn.org:8000/radio"),
        RadioStation(id: '9', name: "Power FM Zambia", location: "Lusaka, Zambia", streamUrl: "http://stream.powerfm.co.zm:8000/live"),
        RadioStation(id: '10', name: "Christian Radio", location: "Zambia", streamUrl: "http://stream.christianradio.co.zm:8000/live"),
      ];
    }
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

final radioMetadataProvider = StreamProvider.family<String, String>((ref, stationName) {
  return ref.watch(radioServiceProvider).getMetadataStream(stationName);
});
