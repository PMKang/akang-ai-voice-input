ALTER TABLE crash_reports ADD COLUMN install_id TEXT NOT NULL DEFAULT 'unknown';

CREATE INDEX crash_reports_install_received_idx
  ON crash_reports (install_id, received_at DESC);
