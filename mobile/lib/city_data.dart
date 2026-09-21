import 'models/models.dart' show kServiceCategories;

/// Which service categories are offered in which city - mirrors
/// backend/app/city_availability.py by hand, keep both in sync.
///
/// Only Zimbabwe has cities modeled for now - Harare, Bulawayo and Mutare.
/// Harare (the capital, MidMan's main hub) offers every active category;
/// Bulawayo and Mutare don't yet have the logistics/partner network for
/// Airport Transfers (transportation), Hardware & Construction Material, or
/// Property Cleaning, so those stay Harare-only until that changes.
const kZimbabweCities = ['Harare', 'Bulawayo', 'Mutare'];

const _notYetOutsideHarare = ['transportation', 'building_materials', 'property_cleaning'];

/// null means "every active category" - used for a city not in this map
/// (or no city selected), so unfiltered until told otherwise.
final Map<String, List<String>?> kCityAvailableCategories = {
  'Harare': null,
  'Bulawayo': kServiceCategories.map((c) => c.value).where((v) => !_notYetOutsideHarare.contains(v)).toList(),
  'Mutare': kServiceCategories.map((c) => c.value).where((v) => !_notYetOutsideHarare.contains(v)).toList(),
};

List<String>? categoriesAvailableInCity(String? city) {
  if (city == null) return null;
  return kCityAvailableCategories[city];
}
