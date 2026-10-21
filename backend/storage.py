import sqlite3
from contextlib import contextmanager
from pathlib import Path

from backend.models import Receipt, Settlement


class Store:
    def __init__(self, path: str):
        self.path = path
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with self.connection() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS people(id INTEGER PRIMARY KEY, name TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS receipts(id INTEGER PRIMARY KEY, data TEXT NOT NULL,
                    settlement TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
            """)

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def people(self):
        with self.connection() as db:
            return [dict(row) for row in db.execute("SELECT * FROM people ORDER BY id")]

    def add_person(self, name):
        with self.connection() as db:
            cursor = db.execute("INSERT INTO people(name) VALUES (?)", (name,))
            return {"id": cursor.lastrowid, "name": name}

    def save(self, receipt: Receipt, receipt_id=None):
        with self.connection() as db:
            if receipt_id is None:
                return db.execute("INSERT INTO receipts(data) VALUES (?)", (receipt.model_dump_json(),)).lastrowid
            # Corrections invalidate prior assignments because item indices may change.
            db.execute("UPDATE receipts SET data=?, settlement=NULL WHERE id=?", (receipt.model_dump_json(), receipt_id))
            return receipt_id

    def get(self, receipt_id):
        with self.connection() as db:
            row = db.execute("SELECT * FROM receipts WHERE id=?", (receipt_id,)).fetchone()
        if row is None:
            raise KeyError(receipt_id)
        return Receipt.model_validate_json(row["data"]), Settlement.model_validate_json(row["settlement"]) if row["settlement"] else None

    def history(self):
        with self.connection() as db:
            return [dict(row) for row in db.execute("SELECT id, created_at FROM receipts ORDER BY id DESC")]

    def settle(self, receipt_id, settlement):
        with self.connection() as db:
            db.execute("UPDATE receipts SET settlement=? WHERE id=?", (settlement.model_dump_json(), receipt_id))
