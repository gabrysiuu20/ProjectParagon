import sys
from io import BytesIO
from types import SimpleNamespace

import pytest
from PIL import Image
from fastapi.testclient import TestClient

from backend import ocr
from backend.main import create_app


def image_bytes():
    output = BytesIO()
    Image.new("RGB", (20, 30), "red").save(output, format="PNG")
    return output.getvalue()


def test_reconstruct_rows_and_reading_order():
    results = [{"rec_texts": ["2 x3,50 7,00A", "7,00", "Chleb", "SUMA PLN"],
                "rec_boxes": [[100, 11, 200, 21], [100, 40, 150, 50],
                              [0, 10, 90, 20], [0, 40, 90, 50]]}]
    assert ocr._result_text(results) == "Chleb 2 x3,50 7,00A\nSUMA PLN 7,00"
    assert ocr._result_text([{"rec_texts": [], "rec_boxes": []}]) == ""


def test_lazy_model_configuration_and_cache(monkeypatch):
    calls = []
    def factory(**kwargs):
        calls.append(kwargs)
        return object()
    monkeypatch.setitem(sys.modules, "paddleocr", SimpleNamespace(PaddleOCR=factory))
    monkeypatch.setattr(ocr, "_engine", None)
    monkeypatch.setenv("OCR_LANG", "pl")
    monkeypatch.setenv("OCR_DEVICE", "cpu")
    assert ocr._get_engine() is ocr._get_engine()
    assert len(calls) == 1
    assert calls[0]["lang"] == "pl"
    assert calls[0]["device"] == "cpu"


def test_missing_dependencies_return_503(tmp_path, monkeypatch):
    monkeypatch.setitem(sys.modules, "numpy", None)
    with TestClient(create_app(str(tmp_path / "db.sqlite3"))) as client:
        assert client.get("/health").status_code == 200
        response = client.post("/receipts/upload", files={"file": ("test.png", image_bytes())})
        assert response.status_code == 503
        assert "PaddleOCR" in response.json()["detail"]


def test_predict_adapter_without_installing_dependencies(monkeypatch):
    class Array:
        def __getitem__(self, key):
            assert key == (slice(None), slice(None), slice(None, None, -1))
            return self
        def copy(self):
            return self
    def asarray(image):
        assert image.mode == "RGB"
        assert image.size == (20, 30)
        return Array()
    class Engine:
        def predict(self, *, input):
            assert isinstance(input, Array)
            yield {"rec_texts": ["Chleb 1 x2,00 2,00A"], "rec_boxes": [[0, 0, 100, 10]]}
    monkeypatch.setitem(sys.modules, "numpy", SimpleNamespace(asarray=asarray))
    monkeypatch.setattr(ocr, "_engine", Engine())
    assert ocr.recognize(image_bytes()) == "Chleb 1 x2,00 2,00A"


def test_initialization_error_is_wrapped(monkeypatch):
    def fail():
        raise RuntimeError("model unavailable")
    monkeypatch.setitem(sys.modules, "numpy", SimpleNamespace())
    monkeypatch.setattr(ocr, "_get_engine", fail)
    with pytest.raises(ocr.OCRUnavailable):
        ocr.recognize(image_bytes())
