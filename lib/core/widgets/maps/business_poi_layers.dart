// Business / amenity POI labels for the self-hosted Protomaps v4 basemap.
//
// The stock Protomaps v4 `pois` layer only labels natural POIs
// (beach/forest/marina/park/peak/zoo). OSM shops, cafés, restaurants,
// supermarkets, clinics, etc. are present in the same tile `pois` source-layer
// but are deliberately filtered out of the base style.
//
// This file adds a single extra symbol layer that surfaces those business POI
// names from the SAME tiles — no new tile source, no third-party service.
//
// Icon safety: the label layer is appended AFTER every stock layer, so the
// existing street/place labels keep their placement priority. The sprite
// (maps.churchonapp.com/map-assets/sprites/v4/{light,dark}) only contains a
// subset of `kind`s; for kinds without a sprite the icon simply does not draw
// and the text label still renders (the renderer logs a non-fatal warning).
//
// To regenerate/extend, add kinds to [kBusinessPoiKinds] only after confirming
// they exist in the v4 sprite sheet.

/// POI `kind`s that carry a business/amenity meaning. All of these exist in the
/// Protomaps v4 sprite sheet (bar, cafe, fast_food, restaurant, supermarket,
/// convenience, clothes, electronics, books, beauty, post_office, school,
/// library, museum, theatre, stadium, university, bus_stop, drinking_water,
/// toilets, garden, artwork, attraction, ferry_terminal, train_station,
/// aerodrome, animal, bench).
const List<String> kBusinessPoiKinds = [
  'bar',
  'cafe',
  'fast_food',
  'restaurant',
  'supermarket',
  'convenience',
  'clothes',
  'electronics',
  'books',
  'beauty',
  'post_office',
  'school',
  'library',
  'museum',
  'theatre',
  'stadium',
  'university',
  'bus_stop',
  'drinking_water',
  'toilets',
  'garden',
  'artwork',
  'attraction',
  'ferry_terminal',
  'train_station',
  'aerodrome',
  'animal',
  'bench',
];

/// A Protomaps v4 style layer that labels business/amenity POIs from the
/// `pois` tile source-layer. Mirrors the stock `pois` layer's layout structure
/// (so the same renderer features are used) but with its own kind filter,
/// text halo and colours for light/dark basemaps.
Map<String, Object> businessPoiLayer({required bool dark}) => {
      'id': 'pois_business',
      'type': 'symbol',
      'source': 'protomaps',
      'source-layer': 'pois',
      'filter': [
        'all',
        [
          'in',
          ['get', 'kind'],
          ['literal', kBusinessPoiKinds],
        ],
        [
          '>=',
          ['zoom'],
          ['get', 'min_zoom'],
        ],
      ],
      'layout': {
        'icon-image': ['get', 'kind'],
        'icon-size': 0.9,
        'text-font': ['Noto Sans Regular'],
        'text-justify': 'auto',
        'text-field': [
          'coalesce',
          ['get', 'name:en'],
          ['get', 'name'],
        ],
        'text-size': 10,
        'text-max-width': 8,
        'text-offset': [1, 0],
        'text-variable-anchor': ['left', 'right'],
      },
      'paint': {
        'text-color': dark ? '#E6E6E6' : '#3E3E3E',
        'text-halo-color': dark ? '#121212' : '#FFFFFF',
        'text-halo-width': 1.2,
      },
    };
