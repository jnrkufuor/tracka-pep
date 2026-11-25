"""The wire format Tracka depends on. If these fail, Tracka would reject Pep's results."""

from pep.callbacks import encode, sign, verify
from pep.contracts import AnalysisRequest, CoachResult, Skill


def test_request_accepts_trackas_exact_payload():
    req = AnalysisRequest.model_validate(
        {
            "analysisId": "6f1c2a8e-1111-4c9a-9a51-2b6e8f0d1c11",
            "videoUrl": "https://example.com/clip.mp4",
            "lengthSeconds": 24.5,
            "positions": ["ST", "LW"],
            "callbackUrl": "https://api.tracka.app/api/coach/results",
        }
    )
    assert req.positions == ["ST", "LW"]
    assert req.clip_type == "match"  # Pep's extras have defaults


def test_result_uses_camel_case_and_drops_empty_fields():
    r = CoachResult(
        analysis_id="a",
        status="READY",
        overall_score=71,
        confidence="MEDIUM",
        skills=[Skill(name="Pace", score=80, explanation="x", drill="y")],
    )
    wire = r.to_wire()
    assert wire["analysisId"] == "a" and wire["overallScore"] == 71
    assert "error" not in wire
    assert wire["skills"][0] == {"name": "Pace", "score": 80, "explanation": "x", "drill": "y"}


def test_failed_result_has_a_message():
    wire = CoachResult.failed("a", "too short").to_wire()
    assert wire == {
        "analysisId": "a",
        "status": "FAILED",
        "error": "too short",
        "skills": [],
        "moments": [],
        "roleFit": [],
        "metrics": {},
        "tips": [],
    }


def test_signature_matches_node_crypto():
    # Same as Node: crypto.createHmac('sha256', 'test-secret').update('{"a":1}').digest('hex')
    body = encode({"a": 1})
    assert body == b'{"a":1}'
    sig = sign(body, "test-secret")
    assert sig == "179bf20a8b9040a32368814a68b0dc270823b5968498e0a73796c4202708ed8d"  # computed with Node
    assert verify(body, sig, "test-secret")
    assert not verify(body + b" ", sig, "test-secret")
    assert not verify(body, sig, "other-secret")
