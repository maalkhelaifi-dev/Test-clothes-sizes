# Size chart file format

Charts are imported and exported as JSON (**Size charts › + › Import chart file**). The importer checks every chart, and nothing is saved if any chart fails.

```json
{
  "formatVersion": 1,
  "unit": "in",
  "charts": [
    {
      "id": "6F1C3E1A-2B7D-4C1E-9A55-3D2B9E0F1A01",
      "brand": "Example Brand",
      "productLine": "Classic Oxford Shirt",
      "category": "shirts",
      "audience": "unisex",
      "region": "us",
      "sizeSystem": "Neck size (in)",
      "measurementType": "body",
      "sizes": [
        { "label": "15",   "measurements": { "neck": { "minCM": 15,   "maxCM": 15.25 }, "chest": { "minCM": 38, "maxCM": 40 } } },
        { "label": "15.5", "measurements": { "neck": { "minCM": 15.5, "maxCM": 15.75 }, "chest": { "minCM": 40, "maxCM": 42 } } }
      ],
      "source": {
        "isDemoData": false,
        "url": "https://www.example-brand.com/size-guide",
        "lastVerified": "2026-09-30",
        "notes": "Copied from the official size guide, shirts tab."
      }
    }
  ]
}
```

## Fields

| Field | Values |
|---|---|
| `unit` | `"cm"` or `"in"`. Every range in the file is in this unit and is converted to centimetres on import. (The key is named `minCM`/`maxCM` for storage compatibility, but the values follow `unit`.) |
| `category` | `tops`, `shirts`, `jackets`, `outerwear`, `suits`, `trousers`, `skirts`, `dresses` |
| `audience` | `unisex`, `womens`, `mens`. The chart line as the brand labels it. |
| `region` | `international`, `us`, `uk`, `eu`, `jp`, `au`, `other` |
| `measurementType` | `body`: the sizes describe the wearer's body. `garment`: the sizes describe the finished garment. |
| `garmentConvention` | Garment charts only: `fullCircumference` or `flatHalfWidth` (garment laid flat, measured across one side) |
| `productLine` | Optional. A collection, fit name or single garment. When present, it takes priority over the brand-wide chart. |
| measurement keys | `height`, `neck`, `shoulderWidth`, `chest`, `underbust`, `waist`, `hips`, `sleeveLength`, `armLength`, `bicep`, `wrist`, `inseam`, `outseam`, `thigh`, `knee`, `calf`, `ankle`, `napeToWaist`, `shoulderToWaist`, `rise` |
| ranges | `minCM == maxCM` for single values. Sizes must be listed smallest to largest. |
| `source.url` | **Required.** The brand's official size-guide page. |
| `source.lastVerified` | **Required.** The date you checked the values (`yyyy-MM-dd` or ISO 8601). It can't be in the future. |
| `source.isDemoData` | Must be `false` for imported charts. |

## Rules
- Copy values exactly from the official source. Don't estimate or interpolate missing sizes.
- If a brand publishes separate charts per product or collection, add one chart per product line.
- Re-check charts periodically, and use **Mark as re-verified today** once you have.
