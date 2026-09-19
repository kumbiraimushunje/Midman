/// Which service categories are offered in which city - mirrors
/// backend/app/city_availability.py by hand, keep both in sync.
///
/// Only Zimbabwe has cities modeled for now - Harare, Bulawayo and Mutare.
/// Every category defaults to available in all 3; edit a city's list here
/// (and the matching one server-side) to restrict it once some services
/// aren't actually offered everywhere.
const kZimbabweCities = ['Harare', 'Bulawayo', 'Mutare'];

/// null means "every active category" - used for a city not in this map
/// (or no city selected), so unfiltered until told otherwise.
const Map<String, List<String>?> kCityAvailableCategories = {
  'Harare': null,
  'Bulawayo': null,
  'Mutare': null,
};

List<String>? categoriesAvailableInCity(String? city) {
  if (city == null) return null;
  return kCityAvailableCategories[city];
}
