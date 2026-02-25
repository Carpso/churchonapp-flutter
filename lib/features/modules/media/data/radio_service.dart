import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:church_on_app/core/providers/audio_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RadioStation {
  final String name;
  final String streamUrl;
  final String location;
  String currentTrack;

  RadioStation({
    required this.name,
    required this.streamUrl,
    required this.location,
    this.currentTrack = "Connecting...",
  });
}

class RadioService {
  final AudioHandler? _handler;
  RadioService(this._handler);

  final List<RadioStation> stations = [
    RadioStation(name: "Radio Christian Voice", location: "Lusaka", streamUrl: "http://stream.rcv.co.zm:8000/stream"),
    RadioStation(name: "United Voice Radio", location: "Lusaka", streamUrl: "https://streaming.unitedvoice.radio/stream"),
    RadioStation(name: "Radio Maria Zambia", location: "National", streamUrl: "http://net.radiomaria.org.ar:8000/Zamba"),
    RadioStation(name: "Radio Icengelo", location: "Copperbelt", streamUrl: "https://stream.icengelo.com/radio/8000/radio.mp3"),
    RadioStation(name: "Yatsani Radio", location: "Lusaka", streamUrl: "http://yatsaniradio.stream:80/live"),
  ];

  Future<void> playStation(RadioStation station) async {
    if (_handler == null) return;
    await _handler!.playFromUri(Uri.parse(station.streamUrl), {
      'title': station.name,
      'album': "Kingdom Radio",
      'artist': station.location,
    });
  }

  Future<void> pause() => _handler?.pause() ?? Future.value();
  Future<void> stop() => _handler?.stop() ?? Future.value();
  Future<void> play() => _handler?.play() ?? Future.value();

  // In a real app, you would fetch from: http://stream.url/status-json.xsl
  // For this VPS setup, we simulate real-time metadata updates.
  Stream<String> getMetadataStream(String stationName) async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 10));
      // Simulation of live metadata
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
    // Standard Shoutcast polling logic - would be used if URL is available
    // try {
    //   final response = await http.get(Uri.parse("$stationUrl/7.html"));
    //   if (response.statusCode == 200) {
    //     return response.body.split(',').last; 
    //   }
    // } catch (_) {}
    return "LIVE: 24/7 Kingdom Content";
  }
}

final radioServiceProvider = Provider((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return RadioService(handler);
});

final radioMetadataProvider = StreamProvider.family<String, String>((ref, stationName) {
  return ref.watch(radioServiceProvider).getMetadataStream(stationName);
});

