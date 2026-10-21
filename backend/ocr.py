import io
import logging
import os
from threading import Lock

from PIL import Image, ImageOps, UnidentifiedImageError

_engine = None
_engine_lock = Lock()


class OCRUnavailable(Exception):
    pass


def _get_engine():
    """Import and initialize only on first upload, so the API works without OCR."""
    global _engine
    if _engine is None:
        from paddleocr import PaddleOCR

        _engine = PaddleOCR(
            lang=os.getenv("OCR_LANG", "pl"),
            device=os.getenv("OCR_DEVICE", "cpu"),
            use_doc_orientation_classify=False,
            use_doc_unwarping=False,
            use_textline_orientation=False,
        )
    return _engine


def _result_text(results) -> str:
    """Rejoin horizontally separated detections into receipt rows."""
    pages = []
    for result in results:
        texts = result["rec_texts"]
        boxes = result["rec_boxes"]
        if len(texts) != len(boxes):
            raise ValueError("Inconsistent PaddleOCR text and box counts")
        fragments = []
        for text, box in zip(texts, boxes):
            if text.strip():
                x1, y1, x2, y2 = map(float, box)
                fragments.append(((y1 + y2) / 2, x1, max(y2 - y1, 1), text.strip()))
        rows = []
        for fragment in sorted(fragments):
            y, x, height, text = fragment
            if rows and abs(y - rows[-1][0][0]) <= min(height, rows[-1][0][2]) * 0.5:
                rows[-1].append(fragment)
            else:
                rows.append([fragment])
        pages.append("\n".join(" ".join(f[3] for f in sorted(row, key=lambda f: f[1])) for row in rows))
    return "\n".join(pages)


def recognize(data: bytes) -> str:
    try:
        with Image.open(io.BytesIO(data)) as source:
            if source.width * source.height > 25_000_000:
                raise ValueError("Zdjęcie przekracza limit 25 megapikseli")
            image = ImageOps.exif_transpose(source).convert("RGB")
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
        raise ValueError("Nieprawidłowy obraz") from exc
    try:
        import numpy as np

        # PaddleOCR accepts OpenCV-style BGR arrays. Serialize shared model access.
        with _engine_lock:
            engine = _get_engine()
            return _result_text(engine.predict(input=np.asarray(image)[:, :, ::-1].copy()))
    except ImportError as exc:
        raise OCRUnavailable("OCR niedostępny: zainstaluj PaddleOCR 3.x i zgodny silnik PaddlePaddle") from exc
    except Exception as exc:
        logging.getLogger(__name__).exception("PaddleOCR inference failed")
        raise OCRUnavailable("PaddleOCR: nie udało się zainicjalizować modelu lub odczytać obrazu; sprawdź konfigurację i logi") from exc
