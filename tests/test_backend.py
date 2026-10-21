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
