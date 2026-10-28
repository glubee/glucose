"""Native OCR -> preprocessing -> numeric extraction -> HTTP response.

All fixtures are synthetic. Private screenshots are never test/CI assets.
"""
import shutil

import cv2
import numpy as np
import pytest
import pytesseract
from fastapi.testclient import TestClient

from graph_parser import PARSER_VERSION
from main import app
from test_graph_parser import build_graph_image


def native_ocr_ready():
    if not shutil.which('tesseract'):
        return False
    return {'kor', 'eng'} <= set(pytesseract.get_languages())


@pytest.mark.skipif(not native_ocr_ready(), reason='Native Tesseract kor+eng required')
@pytest.mark.parametrize('dark,letterbox', [(False, False), (True, False), (False, True)])
def test_real_date_ocr_and_numeric_curve_through_http(monkeypatch, dark, letterbox):
    monkeypatch.setenv('INTERNAL_TOKEN', 'native-test-token')
    encoded = build_graph_image(dark_mode=dark)
    image = cv2.imdecode(np.frombuffer(encoded, np.uint8), cv2.IMREAD_COLOR)
    ink = (240, 240, 240) if dark else (20, 20, 20)
    cv2.putText(image, '2026-10-01', (350, 86), cv2.FONT_HERSHEY_SIMPLEX, 1.1, ink, 2, cv2.LINE_AA)
    if letterbox:
        image = cv2.copyMakeBorder(image, 120, 120, 0, 0, cv2.BORDER_CONSTANT, value=(0, 0, 0))
    ok, data = cv2.imencode('.png', image)
    assert ok
    with TestClient(app) as client:
        response = client.post('/v1/graph/parse', headers={'X-Internal-Token': 'native-test-token'},
                               files={'image': ('synthetic.png', data.tobytes(), 'image/png')})
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload['date'] == '2026-10-01'
    assert payload['meta']['parser_version'] == PARSER_VERSION
    assert len(payload['readings']) == 96
    for i, reading in enumerate(payload['readings']):
        assert reading['time'] == f'{i//4:02d}:{i%4*15:02d}'
        if 40 <= i <= 47:
            assert reading['value'] is None
            assert reading['flag'] == 'MISSING'
        else:
            assert reading['value'] == pytest.approx(150 + 45*np.sin(i/10), abs=2)


@pytest.mark.parametrize('code,status', [
    ('GRAPH_DATE_NOT_RECOGNIZED', 422),
    ('GRAPH_AXES_NOT_RECOGNIZED', 422),
    ('GRAPH_OCR_UNAVAILABLE', 503),
])
def test_errors_identify_the_actual_failed_stage(monkeypatch, code, status):
    from graph_parser import GraphParseFailure
    from main import get_graph_parser

    class Failure:
        def parse(self, image_bytes):
            raise GraphParseFailure(code, '단계별 인식 실패')

    monkeypatch.setenv('INTERNAL_TOKEN', 'native-test-token')
    app.dependency_overrides[get_graph_parser] = lambda: Failure()
    try:
        with TestClient(app) as client:
            response = client.post('/v1/graph/parse', headers={'X-Internal-Token': 'native-test-token'},
                                   files={'image': ('synthetic.png', build_graph_image(), 'image/png')})
        assert response.status_code == status
        assert response.json()['code'] == code
    finally:
        app.dependency_overrides.pop(get_graph_parser, None)
