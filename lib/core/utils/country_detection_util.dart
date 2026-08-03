String detectCountryFromCoordinates(double latitude, double longitude) {
  if (latitude < -17.5 && longitude > 25.0) {
    return 'Zimbabwe';
  }
  return 'Zambia';
}

String? detectCountryFromPlacemark(String? countryName) {
  if (countryName == 'Zimbabwe' || countryName == 'Zambia') {
    return countryName;
  }
  return null;
}