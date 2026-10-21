"""Conservative text parser: unrecognized lines remain visible for review."""
import re
from decimal import Decimal, ROUND_HALF_UP
from pydantic import ValidationError

from backend.models import Item, Receipt

CENT = Decimal("0.01")
NUMBER = r"\d+(?:[.,]\d+)?"
PRODUCT = re.compile(
    rf"^(?P<name>.*?)\s*(?P<qty>{NUMBER})\s*[x×*]\s*"
    rf"(?P<price>{NUMBER})\s+(?P<amount>\d+[.,]\d{{2}})\s*(?P<vat>[A-G])?$", re.I
)
TOTAL = re.compile(r"^SUMA\s*(?:PLN|ZŁ|ZL)?\s*[:=]?\s*(\d+[.,]\d{2})\s*$", re.I)
DISCOUNT = re.compile(r"^(?:OPUST|RABAT)\b", re.I)
NEGATIVE = re.compile(r"-\s*(\d+[.,]\d{2})\s*[A-G]?$", re.I)
FINAL_AMOUNT = re.compile(r"^(\d+[.,]\d{2})\s*[A-G]?$", re.I)


def decimal(text: str) -> Decimal:
    return Decimal(text.replace(",", "."))


def check_receipt(receipt: Receipt) -> dict:
    computed = sum((i.amount - i.discount for i in receipt.items), Decimal("0.00"))
    difference = None if receipt.total is None else computed - receipt.total
    return {"computed_total": computed, "difference": difference,
            "matches": difference == 0 if difference is not None else False}


def parse_receipt(text: str) -> Receipt:
    receipt = Receipt(raw_text=text)
    pending_name = ""
    pending_discount = ""
    discounted_item = None
    in_body = False
    pending_total = False
    for raw in text.splitlines():
        line = " ".join(raw.split())
        if not line:
            continue
        if pending_total:
            if FINAL_AMOUNT.match(line):
                line = "SUMA PLN " + line
            pending_total = False
        if re.fullmatch(r"SUMA\s*(?:PLN|ZŁ|ZL)?", line, re.I):
            pending_total = True
            continue
        match = TOTAL.match(line)
        if match:
            value = decimal(match[1])
            if receipt.total is not None and receipt.total != value:
                receipt.warnings.append("Sprzeczne sumy paragonu; wymagana korekta.")
            receipt.total = value
            continue
        if re.match(r"^(Podsum|SPRZEDAŻ|SPRZEDAZ|PTU|SUMA PTU|ROZLICZENIE|KARTA)", line, re.I):
            in_body = False
            pending_name = ""
            continue
        if "PARAGON FISKALNY" in line.upper():
            in_body = True
            continue
        if DISCOUNT.match(line) or pending_discount:
            discount_line = pending_discount + " " + line if pending_discount else line
            amount = NEGATIVE.search(discount_line)
            if not amount:
                pending_discount = discount_line
                continue
            pending_discount = ""
            # Only attach a discount when its explicit label matches the preceding product.
            label = DISCOUNT.sub("", discount_line).strip()
            label = NEGATIVE.sub("", label).strip()
            if receipt.items and label.casefold() == receipt.items[-1].name.casefold():
                item = receipt.items[-1]
                value = decimal(amount[1])
                if item.discount + value <= item.amount:
                    item.discount += value
                    discounted_item = item
                else:
                    receipt.warnings.append(f"Rabat przekracza wartość: {line}")
            else:
                receipt.warnings.append(f"Nieprzypisany rabat: {discount_line.strip()}")
            continue
        match = PRODUCT.match(line)
        if match:
            name = match["name"].strip() or pending_name
            if not name:
                receipt.warnings.append(f"Brak nazwy produktu: {line}")
                continue
            try:
                item = Item(name=name, quantity=decimal(match["qty"]),
                            unit_price=decimal(match["price"]), amount=decimal(match["amount"]),
                            vat=match["vat"].upper() if match["vat"] else None)
            except ValidationError:
                receipt.warnings.append(f"Nieprawidłowe dane produktu: {line}")
                pending_name = ""
                continue
            receipt.items.append(item)
            if (item.quantity * item.unit_price).quantize(CENT, rounding=ROUND_HALF_UP) != item.amount:
                receipt.warnings.append(f"Ilość × cena nie zgadza się z wartością: {name}")
            pending_name = ""
            discounted_item = None
            in_body = True
            continue
        match = FINAL_AMOUNT.match(line)
        if discounted_item is not None and match:
            if decimal(match[1]) != discounted_item.amount - discounted_item.discount:
                receipt.warnings.append(f"Niezgodna wartość po rabacie: {line}")
            discounted_item = None
            continue
        if in_body:
            receipt.warnings.append(f"Wiersz wymaga weryfikacji: {line}")
            pending_name = line
    if pending_discount:
        receipt.warnings.append(f"Niepełny rabat: {pending_discount}")
    if not receipt.items:
        receipt.warnings.append("Nie rozpoznano produktów.")
    if receipt.total is None:
        receipt.warnings.append("Nie rozpoznano sumy paragonu.")
    elif not check_receipt(receipt)["matches"]:
        receipt.warnings.append("Suma produktów nie zgadza się z sumą paragonu.")
    return receipt
