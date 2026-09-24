import 'package:church_on_app/core/widgets/maps/map_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = 'https://maps.churchonapp.com/region-zm-zw-mw-mz.pmtiles';
  const lusaka = 'https://maps.churchonapp.com/tiles/lusaka-z13-19.pmtiles';

  const lusakaBbox = '[-15.78,27.66,-15.02,28.62]';
  const extras = '[{"name":"lusaka","bbox":$lusakaBbox,'
      '"minZoom":16,"maxZoom":19,"url":"$lusaka"}]';

  List<MapSourceRegion> table() => buildMapSourceTable(
        primaryUrl: base,
        zimbabweUrl: base, // equal -> must be skipped as a duplicate
        extraJson: extras,
      );

  group('buildMapSourceTable', () {
    test('includes base + city, skips zimbabwe when it equals the primary', () {
      final t = table();
      expect(t, hasLength(2));
      expect(t.first.isBase, isTrue);
      expect(t.first.url, base);
      expect(t.first.maxZoom, 15);
      expect(t.map((r) => r.name), containsAll(['base', 'lusaka']));
    });

    test('a distinct zimbabwe URL is kept', () {
      final t = buildMapSourceTable(
        primaryUrl: base,
        zimbabweUrl: 'https://maps.churchonapp.com/zimbabwe-old.pmtiles',
      );
      expect(t.map((r) => r.name), contains('zimbabwe'));
      expect(t.map((r) => r.url), contains('https://maps.churchonapp.com/zimbabwe-old.pmtiles'));
    });

    test('drops malformed entries instead of throwing', () {
      final t = buildMapSourceTable(
        primaryUrl: base,
        extraJson: '''
[
  {"name":"no-url","bbox":[1,2,3,4]},
  {"name":"no-bbox","url":"https://x/1.pmtiles"},
  {"name":"bad-bbox","bbox":[1,2,3],"url":"https://x/2.pmtiles"},
  {"name":"inverted","bbox":[10,0,0,10],"url":"https://x/3.pmtiles"},
  {"name":"ok","bbox":[1,2,3,4],"url":"https://x/4.pmtiles","minzoom":14,"maxzoom":20}
]
''',
      );
      expect(t.map((r) => r.name), ['base', 'ok']);
      expect(t.last.minZoom, 14);
      expect(t.last.maxZoom, 20);
    });

    test('invalid JSON returns just the base', () {
      final t = buildMapSourceTable(primaryUrl: base, extraJson: 'not json');
      expect(t, hasLength(1));
      expect(t.single.isBase, isTrue);
    });

    test('duplicate URLs collapse to one entry', () {
      final t = buildMapSourceTable(
        primaryUrl: base,
        extraJson: '[{"name":"a","bbox":[1,2,3,4],"url":"$base"},'
            '{"name":"b","bbox":[1,2,3,4],"url":"$base"}]',
      );
      expect(t, hasLength(1));
    });

    test('empty primary yields an empty table', () {
      expect(buildMapSourceTable(primaryUrl: '   '), isEmpty);
    });
  });

  group('resolveMapSource', () {
    test('city wins over base when inside bbox and at z16+', () {
      const center = MapLatLng(-15.4, 28.28); // Lusaka
      expect(resolveMapSource(table(), center, 16)?.name, 'lusaka');
      expect(resolveMapSource(table(), center, 19)?.name, 'lusaka');
    });

    test('base is used below the city minZoom', () {
      const center = MapLatLng(-15.4, 28.28);
      expect(resolveMapSource(table(), center, 15)?.name, 'base');
      expect(resolveMapSource(table(), center, 12)?.name, 'base');
    });

    test('base is used past the city maxZoom (over-zoom)', () {
      const center = MapLatLng(-15.4, 28.28);
      expect(resolveMapSource(table(), center, 21)?.name, 'base');
    });

    test('centres outside every city fall back to base', () {
      const kitwe = MapLatLng(-12.8, 28.2);
      expect(resolveMapSource(table(), kitwe, 17)?.name, 'base');
      const ocean = MapLatLng(0, 0);
      expect(resolveMapSource(table(), ocean, 17)?.name, 'base');
    });

    test('smallest matching bbox wins', () {
      final t = buildMapSourceTable(
        primaryUrl: base,
        extraJson: '[{"name":"country","bbox":[-18,21,-8,33],'
            '"minZoom":0,"maxZoom":19,"url":"https://x/country.pmtiles"},'
            '{"name":"city","bbox":[-15.78,27.66,-15.02,28.62],'
            '"minZoom":16,"maxZoom":19,"url":"https://x/city.pmtiles"}]',
      );
      const center = MapLatLng(-15.4, 28.28);
      expect(resolveMapSource(t, center, 17)?.name, 'city');
      expect(resolveMapSource(t, center, 10)?.name, 'country');
    });

    test('empty table resolves to null', () {
      expect(resolveMapSource(const [], const MapLatLng(0, 0), 14), isNull);
    });
  });
}
