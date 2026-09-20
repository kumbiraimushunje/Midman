"""The 3-level service taxonomy shown to customers: Group -> Category (the
`category` column, a ServiceCategory enum) -> Service Type (the
`service_type` column, a free-text string constrained to this list per
category, since the values are numerous, business-editable, and don't need
Postgres-level enforcement).

Mirrored by hand in mobile/lib/service_taxonomy.dart - keep both in sync when
this changes. Groups are a pure navigation concept (Home screen -> category
picker) and are never persisted; a category always belongs to exactly one
group, so the group is only ever derived, never stored.

A handful of existing ServiceCategory enum members (school_fees, medical,
prescriptions, family_essentials, documents, property_management, cleaning)
predate this taxonomy and are intentionally left out of ACTIVE_CATEGORIES -
they're kept in the Postgres enum only so historical rows created before
this change stay valid; new requests never use them again.
"""

SERVICE_GROUPS = [
    {
        "label": "Family Care & Child Support",
        "categories": [
            {
                "value": "groceries",
                "label": "Groceries",
                "service_types": ["Food Supplies", "Personal Care Products", "Baby Products", "Household Supplies", "Other"],
            },
            {
                "value": "healthcare",
                "label": "Healthcare",
                "service_types": [
                    "Pay Hospital Bill",
                    "Buy Medication",
                    "Specialist Appointments",
                    "Medical Procedures",
                    "Laboratory Tests",
                    "Other Healthcare-Related Expenses",
                ],
            },
            {
                "value": "education",
                "label": "Education",
                "service_types": ["Tuition Fees", "Exam Fees", "Uniforms", "Transport", "Stationery", "Other Education-Related Expenses"],
            },
        ],
    },
    {
        "label": "Documents & Administration",
        "categories": [
            {"value": "document_collection", "label": "Document Collection", "service_types": ["Document Collection", "Other"]},
            {"value": "document_delivery", "label": "Document Delivery", "service_types": ["Document Submission", "Other"]},
            {
                "value": "government_errands",
                "label": "Administrative Errands",
                "service_types": ["Application Follow-ups", "Certificate Collection"],
                "notice": (
                    "MidMan provides ordinary administrative assistance only (queuing, form "
                    "submission, collection). Anything requiring a licensed professional (e.g. "
                    "a lawyer) or Power of Attorney isn't covered here and needs separate arrangement."
                ),
            },
        ],
    },
    {
        "label": "Property Management & Home Services",
        "categories": [
            {
                "value": "property_inspection",
                "label": "Property Inspections",
                "service_types": ["Condition Reporting", "Utility Coordination", "Occupancy Confirmation", "Other"],
            },
            {
                "value": "maintenance",
                "label": "Maintenance",
                "service_types": [
                    "Plumbing",
                    "Electrical",
                    "Air Conditioning",
                    "Painting",
                    "Carpentry",
                    "Appliance Repairs",
                    "General Repairs",
                    "Cleaning",
                    "Landscaping",
                    "Other",
                ],
            },
            {
                "value": "tenant_coordination",
                "label": "Tenant Coordination",
                "service_types": ["Move-in/Move-out Inspections", "Key Collection", "Key Handover"],
            },
            {"value": "property_cleaning", "label": "Property Cleaning", "service_types": ["Deep Cleaning", "Move-In / Move-Out"]},
            {
                "value": "building_materials",
                "label": "Building Materials",
                "service_types": [
                    "Cement",
                    "Bricks",
                    "Sand",
                    "Steel",
                    "Roofing Materials",
                    "Plumbing Materials",
                    "Electrical Materials",
                    "Paint",
                    "Tiles",
                    "Hardware",
                ],
            },
            {
                "value": "household_procurement",
                "label": "Household Procurement",
                "service_types": ["Appliances", "Furniture", "Electronics", "Household Goods", "Office Equipment", "Other Approved Products"],
            },
            {"value": "procurement", "label": "Other", "service_types": ["General Procurement"]},
        ],
    },
    {
        "label": "Gifts & Celebrations",
        "description_hint": "e.g. Cake, Flowers, Gift, Delivery, Personalized Card, Personalised hoodies/tshirts",
        "categories": [
            {
                "value": "birthday_gifts",
                "label": "Birthday Gifts",
                "service_types": ["Cake Only", "Cake & Flowers", "Cake + Flowers & Gift", "Restaurant/Event Coordination"],
            },
            {
                "value": "anniversary_valentines_gifts",
                "label": "Anniversary/Valentines Gifts",
                "service_types": ["Cake Only", "Cake & Flowers", "Cake + Flowers & Gift", "Restaurant/Event Coordination"],
            },
            {
                "value": "graduation_gifts",
                "label": "Graduation Gifts",
                "service_types": ["Cake Only", "Cake & Flowers", "Cake + Flowers & Gift", "Restaurant/Event Coordination", "Photoshoot"],
            },
            {
                "value": "corporate_gifts",
                "label": "Corporate Gifts",
                "service_types": ["Employee Gifts", "Client Gifts", "Business Partner Gifts", "Executive Gifts", "Special Occasions"],
            },
            {
                "value": "gifts",
                "label": "Other Celebrations",
                "service_types": ["Cake Only", "Cake & Flowers", "Cake + Flowers & Gift", "Restaurant/Event Coordination", "Photoshoot"],
            },
        ],
    },
    {
        "label": "Transportation & Mobility",
        "categories": [
            {
                "value": "transportation",
                "label": "Airport Transfers",
                "service_types": ["Airport Drop off", "Airport Pick up"],
                "extra_fields": ["Airport", "Flight number", "Passenger", "Arrival time", "Destination"],
            },
        ],
    },
    {
        "label": "Other",
        "categories": [
            {
                "value": "personal_concierge",
                "label": "Personal Concierge/Errands",
                "service_types": ["Collections", "Deliveries", "Purchases", "Appointments", "Local Errands", "Personal Administration"],
            },
        ],
    },
]

# category value -> list of allowed service_type strings.
SERVICE_TYPES_BY_CATEGORY = {cat["value"]: cat["service_types"] for group in SERVICE_GROUPS for cat in group["categories"]}

# The only categories offered to customers/the AI concierge right now.
ACTIVE_CATEGORIES = list(SERVICE_TYPES_BY_CATEGORY.keys())
