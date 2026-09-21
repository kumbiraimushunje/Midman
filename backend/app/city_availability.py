"""Which service categories are offered in which city.

Only Zimbabwe has cities modeled for now - Harare, Bulawayo and Mutare.
A request for any other country skips city selection entirely (city stays
None) and sees the full active taxonomy unfiltered.

Harare (the capital, MidMan's main hub) offers every active category.
Bulawayo and Mutare don't yet have the logistics/partner network for
Airport Transfers (transportation), Hardware & Construction Material, or
Property Cleaning - those stay Harare-only until that changes. Edit a city's list
here (see service_taxonomy.py's ACTIVE_CATEGORIES for the full set of
valid values) as coverage grows - the request-creation endpoint enforces
whatever's listed here, and the app's New Request form filters its
Category dropdown the same way once a city is picked.
"""

from .service_taxonomy import ACTIVE_CATEGORIES

ZIMBABWE_CITIES = ["Harare", "Bulawayo", "Mutare"]

_NOT_YET_OUTSIDE_HARARE = {"transportation", "building_materials", "property_cleaning"}

CITY_AVAILABLE_CATEGORIES: dict[str, list[str]] = {
    "Harare": list(ACTIVE_CATEGORIES),
    "Bulawayo": [c for c in ACTIVE_CATEGORIES if c not in _NOT_YET_OUTSIDE_HARARE],
    "Mutare": [c for c in ACTIVE_CATEGORIES if c not in _NOT_YET_OUTSIDE_HARARE],
}


def categories_available_in(city: str | None) -> list[str] | None:
    """None means unfiltered (every active category) - used for a city
    that isn't in CITY_AVAILABLE_CATEGORIES, or no city at all."""
    if city is None:
        return None
    return CITY_AVAILABLE_CATEGORIES.get(city)
