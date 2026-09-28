# Fixtures

Receipt fixtures are local inputs for `make receipts`. Git ignores the
`Fixtures/Receipts/` directory because scans are large and can contain private
data.

## Layout

```
Fixtures/
  Receipts/
    <fixture-name>/
      fixtures/
        1.png                              # one or more receipt samples
      expected.json                        # optional evaluation criteria
```

`ReceiptLab` accepts:

- a single image/PDF file (no evaluation),
- a fixture folder (containing `fixtures/`),
- a folder of fixture folders (batch run).

## Add a fixture

Create a fixture folder and copy a receipt image or PDF into its `fixtures`
directory:

```sh
mkdir -p Fixtures/Receipts/store-name
mkdir -p Fixtures/Receipts/store-name/fixtures
cp /path/to/receipt.png Fixtures/Receipts/store-name/fixtures/1.png
```

ReceiptLab evaluates each file in `fixtures` as a separate sample. A PDF can
contain multiple pages for one sample. All samples in the fixture folder use
the same `expected.json` file.

Add an optional `expected.json` file to the new folder. Run the folder or one
input file:

```sh
make receipts of=store-name
make receipts of=store-name/1
```

Folder names can contain nested paths. For example,
`make receipts of=groceries/store-name/1` resolves
`Fixtures/Receipts/groceries/store-name/fixtures/1.*`. You can also give `of`
an existing folder or file path.

## `expected.json`

Each field is optional. ReceiptLab skips fields that are absent or `null`.
`itemCount` requires an exact count.

```json
{
  "currency": "USD",
  "subtotal": 12.34,
  "savings": 0.78,
  "tax": 1.02,
  "tip": null,
  "total": 12.58,
  "itemCount": 2,
  "amountTolerance": 0.01,
  "items": [
    {
      "rawName": "BANANA",
      "lineTotal": 1.08,
      "quantity": 1,
      "unitPrice": 1.08
    },
    {
      "rawName": "LEMON",
      "lineTotal": 1.78
    }
  ]
}
```

`currency`, `subtotal`, `savings`, `tax`, `tip`, and `total` compare directly
with the parsed receipt. `amountTolerance` sets the absolute tolerance for
receipt amounts, item line totals, and unit prices. The default is 0.01.

When `items` is present, ReceiptLab checks all expected items and rejects extra
parsed items. `rawName` allows small OCR differences but rejects unrelated
names. `lineTotal` is required. `quantity` and `unitPrice` are optional.
ReceiptLab derives the parsed unit price from `lineTotal / quantity`. Quantity
uses a fixed tolerance of 0.001.
