"""Which service categories are offered in which city.

Only Zimbabwe has cities modeled for now - Harare, Bulawayo and Mutare.
A request for any other country skips city selection entirely (city stays
None) and sees the full active taxonomy unfiltered.

Every category defaults to available in all 3 cities below. Edit a city's
list to remove a category value (see service_taxonomy.py's ACTIVE_CATEGORIES
for the full set of valid values) to restrict it to the cities where it's
actually offered - the request-creation endpoint enforces whatever's listed
here, and the app's New Request form filters its Category dropdown the same
way once a city is picked.
"""

from .service_taxonomy import ACTIVE_CATEGORIES

ZIMBABWE_CITIES = ["Harare", "Bulawayo", "Mutare"]

CITY_AVAILABLE_CATEGORIES: dict[str, list[str]] = {
    "Harare": list(ACTIVE_CATEGORIES),
    "Bulawayo": list(ACTIVE_CATEGORIES),
    "Mutare": list(ACTIVE_CATEGORIES),
}


def categories_available_in(city: str | None) -> list[str] | None:
    """None means unfiltered (every active category) - used for a city
    that isn't in CITY_AVAILABLE_CATEGORIES, or no city at all."""
    if city is None:
        return None
    return CITY_AVAILABLE_CATEGORIES.get(city)
