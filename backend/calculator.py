from decimal import Decimal

from backend.models import Receipt, Settlement


def calculate(receipt: Receipt, settlement: Settlement, people: set[int]) -> dict:
    totals: dict[int, Decimal] = {}
    assigned = set()
    for assignment in settlement.assignments:
        index = assignment.item_index
        ids = sorted(assignment.person_ids)
        if index >= len(receipt.items) or index in assigned:
            raise ValueError("Nieprawidłowy lub powtórzony indeks produktu")
        if len(set(ids)) != len(ids) or not set(ids) <= people:
            raise ValueError("Nieznane lub powtórzone osoby")
        assigned.add(index)
        item = receipt.items[index]
        cents = int((item.amount - item.discount) * 100)
        share, remainder = divmod(cents, len(ids))
        for position, person in enumerate(ids):
            totals[person] = totals.get(person, Decimal("0.00")) + Decimal(share + (position < remainder)) / 100
    unassigned = sum((i.amount - i.discount for n, i in enumerate(receipt.items) if n not in assigned), Decimal("0.00"))
    return {"totals": totals, "unassigned_amount": unassigned,
            "complete": len(assigned) == len(receipt.items) and bool(receipt.items)}
