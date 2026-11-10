from decimal import Decimal
from io import BytesIO
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from openpyxl import load_workbook
from pydantic import ValidationError

from backend.calculator import calculate
from backend.main import create_app
from backend.models import Item, Settlement
from backend.ocr import OCRUnavailable, recognize
from backend.parser import check_receipt, parse_receipt

TEXT = Path(__file__).with_name("fixtures").joinpath("lidl.txt").read_text(encoding="utf-8")


def test_sample_receipt():
    receipt = parse_receipt(TEXT)
    assert len(receipt.items) == 8
    assert receipt.items[0].quantity == Decimal("0.43")
    assert receipt.items[0].discount == Decimal("0.43")
    assert receipt.items[0].vat == "C"
    assert check_receipt(receipt)["computed_total"] == Decimal("34.61")
    assert check_receipt(receipt)["matches"]
    assert not receipt.warnings


@pytest.mark.parametrize("text", ["Chleb 2 × 1.50 3.00 A\nSUMA PLN 3.00", "PARAGON FISKALNY\nChleb\n2*1,50 3,00A\nSUMA PLN 3,00"])
def test_alternative_layout(text):
    receipt = parse_receipt(text)
    assert receipt.items[0].name == "Chleb"
    assert receipt.items[0].amount == Decimal("3")


@pytest.mark.parametrize("text", ["", "Chleb 1 x2,00 2,00A\nSUMA PLN 9,00", "RABAT inny -1,00"])
def test_uncertain_text_has_warnings(text):
    assert parse_receipt(text).warnings


def test_ambiguous_discount():
    receipt = parse_receipt("Chleb 1 x2,00 2,00A\nRABAT -1,00\nSUMA PLN 1,00")
    assert receipt.items[0].discount == 0
    assert not check_receipt(receipt)["matches"]


def test_split_conserves_cents():
    receipt = parse_receipt("Chleb 1 x0,05 0,05A\nSUMA PLN 0,05")
    result = calculate(receipt, Settlement(assignments=[{"item_index": 0, "person_ids": [3, 1, 2]}]), {1, 2, 3})
    assert result["totals"] == {1: Decimal("0.02"), 2: Decimal("0.02"), 3: Decimal("0.01")}
    assert result["complete"]


@pytest.mark.parametrize("assignments", [[{"item_index": 99, "person_ids": [1]}], [{"item_index": 0, "person_ids": [99]}], [{"item_index": 0, "person_ids": [1, 1]}], [{"item_index": 0, "person_ids": [1]}] * 2])
def test_bad_assignments(assignments):
    with pytest.raises(ValueError):
        calculate(parse_receipt(TEXT), Settlement(assignments=assignments), {1})


@pytest.mark.parametrize("changes", [{"amount": "1.001"}, {"discount": "2"}, {"quantity": "NaN"}, {"unit_price": "-1"}])
def test_financial_validation(changes):
    with pytest.raises(ValidationError):
        Item.model_validate({"name": "X", "quantity": "1", "unit_price": "1", "amount": "1", **changes})


def test_api_workflow(tmp_path):
    path = str(tmp_path / "test.sqlite3")
    with TestClient(create_app(path, ocr=lambda data: TEXT)) as client:
        person = client.post("/people", json={"name": "=1+1"}).json()
        response = client.post("/receipts/upload", files={"file": ("receipt.jpg", b"mock-image", "image/jpeg")})
        assert response.status_code == 201
        receipt_id = response.json()["id"]
        assert response.json()["validation"]["matches"]
        assignments = [{"item_index": i, "person_ids": [person["id"]]} for i in range(8)]
        response = client.put(f"/receipts/{receipt_id}/settlement", json={"assignments": assignments})
        assert response.status_code == 200
        assert Decimal(str(response.json()["totals"][str(person["id"])])) == Decimal("34.61")
        workbook = load_workbook(BytesIO(client.get(f"/receipts/{receipt_id}/export").content))
        assert workbook["Rozliczenie"]["A2"].value == "=1+1"
        assert workbook["Rozliczenie"]["A2"].data_type == "s"
        receipt = client.get(f"/receipts/{receipt_id}").json()["receipt"]
        assert client.put(f"/receipts/{receipt_id}", json=receipt).status_code == 200
        assert client.get(f"/receipts/{receipt_id}").json()["settlement"] is None
        assert client.get("/receipts/9999").status_code == 404
        assert client.get("/receipts").json()[0]["id"] == receipt_id
    with TestClient(create_app(path)) as client:
        assert client.get(f"/receipts/{receipt_id}").status_code == 200
        assert len(client.get("/people").json()) == 1


def test_receipt_correction_persists_items_discounts_and_total(tmp_path):
    with TestClient(create_app(str(tmp_path / "correction.sqlite3"))) as client:
        created = client.post("/receipts/parse", json={"text": "PARAGON FISKALNY\nChleb 1 x2,00 2,00C\nSUMA PLN 2,00"}).json()
        receipt_id = created["id"]
        corrected = created["receipt"]
        corrected["items"] = [
            {"name": "Chleb żytni", "quantity": "2", "unit_price": "1.00", "amount": "2.00", "discount": "0.50", "vat": "C"},
            {"name": "Jabłko", "quantity": "1", "unit_price": "1.00", "amount": "1.00", "discount": "0.00", "vat": None},
        ]
        corrected["total"] = "2.50"
        response = client.put(f"/receipts/{receipt_id}", json=corrected)
        assert response.status_code == 200
        assert response.json()["validation"]["matches"]
        saved = client.get(f"/receipts/{receipt_id}").json()
        assert len(saved["receipt"]["items"]) == 2
        assert saved["receipt"]["items"][0]["name"] == "Chleb żytni"
        assert saved["receipt"]["items"][0]["discount"] == "0.50"
        assert saved["receipt"]["total"] == "2.50"
        assert saved["receipt"]["raw_text"] == corrected["raw_text"]


def test_ocr_failure(tmp_path):
    def unavailable(data):
        raise OCRUnavailable("Missing engine")
    with TestClient(create_app(str(tmp_path / "test.sqlite3"), ocr=unavailable)) as client:
        assert client.post("/receipts/upload", files={"file": ("a.jpg", b"x")}).status_code == 503
    with pytest.raises(ValueError):
        recognize(b"not an image")


def test_unassigned_costs():
    result = calculate(parse_receipt(TEXT), Settlement(assignments=[]), set())
    assert result["unassigned_amount"] == Decimal("34.61")
    assert not result["complete"]


def test_multiline_total():
    receipt = parse_receipt("Chleb 1 x2,00 2,00A\nSUMA PLN\n2,00")
    assert check_receipt(receipt)["matches"]


def test_invalid_ocr_quantity():
    receipt = parse_receipt("Chleb 0 x2,00 2,00A\nSUMA PLN 2,00")
    assert not receipt.items
    assert receipt.warnings


def test_noisy_lidl_ocr_keeps_discount_and_total():
    text = """PARAGON FISKALNY
Pomidory kiścio. luz F 0,43 ×8,99 3,87C
OPUST Pomidory kiścio. luz -0,43
Mix sałat klas. 200g 3,44C
F 1 ×5,45 5,45C
Krem z octem balsam. 1 ×8,99 8,998
SUMA PLN enasa sbsdo 17,88"""
    receipt = parse_receipt(text)
    assert len(receipt.items) == 3
    assert receipt.items[0].discount == Decimal("0.43")
    assert receipt.items[1].name == "Mix sałat klas. 200g F"
    assert receipt.items[2].amount == Decimal("8.99")
    assert receipt.items[2].vat is None
    assert receipt.total == Decimal("17.88")
    assert any("Niepewna stawka VAT" in warning for warning in receipt.warnings)


def test_carrefour_layout_and_fiscal_total_excludes_deposit():
    text = """PARAGON FISKALNY
C_MC POMIDOR POLSKI 0,21szt.w*11,99= 2,52 C
B_ZIOŁA PRYMAT 8G D 1szt*1,39= 1,39 B
OPUST B_ZIOŁA PRYMAT 8G D -0,70 B
SUMA PLN 3,21
KAUCJA DRS 3 * 0,50 1,50
DO ZAPŁATY 4,71"""
    receipt = parse_receipt(text)
    assert len(receipt.items) == 2
    assert receipt.items[1].discount == Decimal("0.70")
    assert receipt.total == Decimal("3.21")
    assert check_receipt(receipt)["matches"]


def test_ocr_text_from_lidl_photo_recovers_all_amounts():
    text = """PARAGON FISKALNY nr:715071
Pomidory kiścio. luz F 0,43 ×8,99 3,87C
OPUST Pomidory kiścio. luz
-0.43
Mix sałat klas. 200g 3,44C
L 1 ×5,45 5,45C
łosoś sałatkowy F 1 ×7.49 7,49C
Wegański deser H.P. 1 1 ×2,99 2,99B
Serek wiejski t 1 ×2,29 2,29C
Krem z octem balsam. — 1 ×8,99 8,998
Bułka ziemniaczana 1 2 ×0,99 1,98C
Bułka górska Ł 2 ×0.99 1,98C
Podsuma: 34.61
SUMA PLN enasa sbsdo 34,61"""
    receipt = parse_receipt(text)
    assert len(receipt.items) == 8
    assert receipt.items[0].discount == Decimal("0.43")
    assert receipt.total == Decimal("34.61")
    assert check_receipt(receipt)["matches"]


@pytest.mark.parametrize("fixture,count,total,discount", [
    ("lidl_ocr.txt", 8, "34.61", "0.43"),
    ("carrefour_ocr.txt", 21, "84.50", "0.70"),
])
def test_actual_photo_ocr_transcriptions(fixture, count, total, discount):
    text = Path(__file__).with_name("fixtures").joinpath(fixture).read_text(encoding="utf-8")
    receipt = parse_receipt(text)
    assert len(receipt.items) == count
    assert receipt.total == Decimal(total)
    assert sum((item.discount for item in receipt.items), Decimal("0")) == Decimal(discount)
    assert check_receipt(receipt)["matches"]
    assert all("Wiersz wymaga weryfikacji" not in warning for warning in receipt.warnings)
