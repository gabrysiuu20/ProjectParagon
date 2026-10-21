import os

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from backend.calculator import calculate
from backend.export import export_xlsx
from backend.models import Person, Receipt, Settlement
from backend.ocr import OCRUnavailable, recognize
from backend.parser import check_receipt, parse_receipt
from backend.storage import Store


class TextInput(BaseModel):
    text: str = Field(min_length=1, max_length=100000)


def create_app(db_path=None, ocr=recognize):
    app = FastAPI(title="ProjectParagon", version="0.1.0")
    store = Store(db_path or os.getenv("PARAGON_DB", "data/paragon.sqlite3"))

    def load(receipt_id):
        try:
            return store.get(receipt_id)
        except KeyError:
            raise HTTPException(404, "Nie znaleziono paragonu")

    def view(receipt_id, receipt):
        return {"id": receipt_id, "receipt": receipt.model_dump(mode="json"), "validation": check_receipt(receipt)}

    @app.get("/health")
    def health():
        return {"status": "ok"}

    @app.get("/people")
    def people():
        return store.people()

    @app.post("/people", status_code=201)
    def add_person(person: Person):
        if not person.name.strip():
            raise HTTPException(422, "Pusta nazwa osoby")
        return store.add_person(person.name.strip())

    @app.post("/receipts/parse", status_code=201)
    def parse(payload: TextInput):
        receipt = parse_receipt(payload.text)
        return view(store.save(receipt), receipt)

    @app.post("/receipts/upload", status_code=201)
    async def upload(file: UploadFile = File(...)):
        try:
            data = await file.read(10 * 1024 * 1024 + 1)
        finally:
            await file.close()
        if len(data) > 10 * 1024 * 1024:
            raise HTTPException(413, "Limit zdjęcia: 10 MB")
        try:
            text = await run_in_threadpool(ocr, data)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        except OCRUnavailable as exc:
            raise HTTPException(503, str(exc))
        receipt = parse_receipt(text)
        return view(store.save(receipt), receipt)

    @app.get("/receipts")
    def history():
        return store.history()

    @app.get("/receipts/{receipt_id}")
    def get(receipt_id: int):
        receipt, settlement = load(receipt_id)
        return {**view(receipt_id, receipt), "settlement": settlement}

    @app.put("/receipts/{receipt_id}")
    def correct(receipt_id: int, receipt: Receipt):
        load(receipt_id)
        store.save(receipt, receipt_id)
        return view(receipt_id, receipt)

    @app.put("/receipts/{receipt_id}/settlement")
    def settle(receipt_id: int, settlement: Settlement):
        receipt, _ = load(receipt_id)
        try:
            result = calculate(receipt, settlement, {p["id"] for p in store.people()})
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        store.settle(receipt_id, settlement)
        return {**result, "receipt_validation": check_receipt(receipt)}

    @app.get("/receipts/{receipt_id}/export")
    def export(receipt_id: int):
        receipt, settlement = load(receipt_id)
        data = export_xlsx(receipt, settlement or Settlement(assignments=[]), store.people())
        return Response(data, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                        headers={"Content-Disposition": f'attachment; filename="receipt-{receipt_id}.xlsx"'})

    return app
