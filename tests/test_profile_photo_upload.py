"""Route /api/update_profile_photo — Storage seul, aucun repli base64 (build 6b).

Ordre attendu : upload → écriture profil {photo_url, photo_b64: None} → suppression
de l'ancien fichier. Profil en échec → nouveau fichier supprimé. Suppression de
l'ancien en échec → warning, 200.
"""
import os
import sys
from unittest.mock import MagicMock, patch

from flask import Flask

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import db
from routes.profile import profile_bp

BASE = "https://x.supabase.co/storage/v1/object/public/profile-photos/"
IMG = "data:image/jpeg;base64,/9j/AAAA"
OLD = BASE + "user_1/old-uuid.jpg"


def _client(bucket):
    client = MagicMock()
    client.storage.from_.return_value = bucket
    return client


def _bucket(upload_error=None, remove_error=None):
    bucket = MagicMock()
    if upload_error:
        bucket.upload.side_effect = upload_error
    if remove_error:
        bucket.remove.side_effect = remove_error
    bucket.get_public_url.side_effect = lambda path: BASE + path + "?"
    return bucket


def _post(bucket, profile, save_ok=True):
    app = Flask(__name__)
    app.register_blueprint(profile_bp)
    save = MagicMock(return_value=save_ok)
    with patch.object(db, "_client", _client(bucket)), \
         patch("user_profile.load_user_profile", return_value=profile), \
         patch("user_profile.save_user_profile", save):
        resp = app.test_client().post("/api/update_profile_photo", json={"photo_b64": IMG})
    return resp, save


def _uploaded_path(bucket):
    return bucket.upload.call_args.kwargs["path"]


def test_a_storage_failure_is_502_and_writes_nothing():
    bucket = _bucket(upload_error=RuntimeError("bucket down"))
    resp, save = _post(bucket, {"photo_url": OLD})
    assert resp.status_code == 502
    assert resp.get_json() == {"success": False, "error": "storage_unavailable"}
    save.assert_not_called()
    bucket.remove.assert_not_called()


def test_b_profile_save_failure_is_500_and_removes_new_file():
    bucket = _bucket()
    resp, _ = _post(bucket, {"photo_url": OLD}, save_ok=False)
    assert resp.status_code == 500
    assert resp.get_json()["error"] == "profile_save_failed"
    new_path = _uploaded_path(bucket)
    bucket.remove.assert_called_once_with([new_path])  # jamais l'ancien


def test_c_success_writes_exact_patch_then_removes_old_file():
    bucket = _bucket()
    resp, save = _post(bucket, {"photo_url": OLD, "photo_b64": "data:image/jpeg;base64,legacy"})
    new_path = _uploaded_path(bucket)
    assert resp.status_code == 200
    assert resp.get_json() == {"success": True, "photo_url": BASE + new_path}
    save.assert_called_once_with({"photo_url": BASE + new_path, "photo_b64": None})
    bucket.remove.assert_called_once_with(["user_1/old-uuid.jpg"])
    # Nom non devinable : user_1/<uuid4>.jpg
    name = new_path.removeprefix("user_1/").removesuffix(".jpg")
    assert new_path.startswith("user_1/") and len(name) == 36 and name != "profile"


def test_d_old_file_delete_failure_is_logged_not_blocking(caplog):
    bucket = _bucket(remove_error=RuntimeError("delete refused"))
    with caplog.at_level("WARNING", logger="trainingos"):
        resp, save = _post(bucket, {"photo_url": OLD})
    assert resp.status_code == 200
    save.assert_called_once()
    assert "old file delete failed" in caplog.text


def test_e_no_previous_photo_url_deletes_nothing():
    bucket = _bucket()
    resp, _ = _post(bucket, {"photo_b64": "data:image/jpeg;base64,legacy"})
    assert resp.status_code == 200
    bucket.remove.assert_not_called()


def test_old_url_outside_user_folder_is_never_deleted():
    bucket = _bucket()
    resp, _ = _post(bucket, {"photo_url": BASE + "other/x.jpg"})
    assert resp.status_code == 200
    bucket.remove.assert_not_called()


def test_upload_uses_unique_paths():
    b1, b2 = _bucket(), _bucket()
    _post(b1, {})
    _post(b2, {})
    assert _uploaded_path(b1) != _uploaded_path(b2)
