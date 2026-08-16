PRAGMA foreign_keys = ON;

CREATE TABLE crash_groups (
  fingerprint TEXT PRIMARY KEY,
  product TEXT NOT NULL,
  kind TEXT NOT NULL,
  source TEXT NOT NULL,
  label TEXT NOT NULL,
  error_type TEXT NOT NULL,
  top_frame TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  first_seen TEXT NOT NULL,
  last_seen TEXT NOT NULL,
  first_version TEXT NOT NULL,
  last_version TEXT NOT NULL,
  occurrence_count INTEGER NOT NULL DEFAULT 1 CHECK (occurrence_count > 0),
  resolved_at TEXT,
  regressed_at TEXT
);

CREATE TABLE crash_reports (
  report_id TEXT PRIMARY KEY,
  fingerprint TEXT NOT NULL,
  product TEXT NOT NULL,
  kind TEXT NOT NULL,
  source TEXT NOT NULL,
  label TEXT NOT NULL,
  version TEXT NOT NULL,
  build TEXT NOT NULL,
  os_version TEXT NOT NULL,
  architecture TEXT NOT NULL,
  error_type TEXT NOT NULL,
  error_message TEXT NOT NULL,
  stack TEXT NOT NULL,
  top_frame TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  incident_id TEXT NOT NULL,
  breadcrumbs_json TEXT NOT NULL,
  received_at TEXT NOT NULL
);

CREATE INDEX crash_reports_fingerprint_received_idx
  ON crash_reports (fingerprint, received_at DESC);

CREATE TABLE crash_notifications (
  notification_key TEXT PRIMARY KEY,
  fingerprint TEXT NOT NULL,
  report_id TEXT NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN ('new', 'regression', 'test')),
  created_at TEXT NOT NULL,
  sent_at TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  lease_until TEXT,
  last_error TEXT
);

CREATE INDEX crash_notifications_pending_idx
  ON crash_notifications (sent_at, lease_until, created_at);

-- The trigger keeps report de-duplication, group counts, and notification
-- creation in the same SQLite statement. Replaying a report_id is therefore
-- idempotent and cannot increment the group twice.
CREATE TRIGGER crash_reports_after_insert
AFTER INSERT ON crash_reports
BEGIN
  INSERT OR IGNORE INTO crash_notifications (
    notification_key,
    fingerprint,
    report_id,
    reason,
    created_at
  )
  SELECT
    'test:' || NEW.report_id,
    NEW.fingerprint,
    NEW.report_id,
    'test',
    NEW.received_at
  WHERE NEW.kind = 'test';

  INSERT OR IGNORE INTO crash_notifications (
    notification_key,
    fingerprint,
    report_id,
    reason,
    created_at
  )
  SELECT
    'new:' || NEW.fingerprint,
    NEW.fingerprint,
    NEW.report_id,
    'new',
    NEW.received_at
  WHERE NEW.kind <> 'test'
    AND NOT EXISTS (
      SELECT 1 FROM crash_groups WHERE fingerprint = NEW.fingerprint
    );

  INSERT OR IGNORE INTO crash_notifications (
    notification_key,
    fingerprint,
    report_id,
    reason,
    created_at
  )
  SELECT
    'regression:' || NEW.fingerprint || ':' || COALESCE(resolved_at, 'unknown'),
    NEW.fingerprint,
    NEW.report_id,
    'regression',
    NEW.received_at
  FROM crash_groups
  WHERE NEW.kind <> 'test'
    AND fingerprint = NEW.fingerprint
    AND status = 'resolved';

  INSERT INTO crash_groups (
    fingerprint,
    product,
    kind,
    source,
    label,
    error_type,
    top_frame,
    status,
    first_seen,
    last_seen,
    first_version,
    last_version,
    occurrence_count,
    resolved_at,
    regressed_at
  ) VALUES (
    NEW.fingerprint,
    NEW.product,
    NEW.kind,
    NEW.source,
    NEW.label,
    NEW.error_type,
    NEW.top_frame,
    'open',
    NEW.received_at,
    NEW.received_at,
    NEW.version,
    NEW.version,
    1,
    NULL,
    NULL
  )
  ON CONFLICT(fingerprint) DO UPDATE SET
    kind = excluded.kind,
    label = excluded.label,
    error_type = excluded.error_type,
    top_frame = excluded.top_frame,
    status = 'open',
    last_seen = excluded.last_seen,
    last_version = excluded.last_version,
    occurrence_count = crash_groups.occurrence_count + 1,
    regressed_at = CASE
      WHEN crash_groups.status = 'resolved' THEN excluded.last_seen
      ELSE crash_groups.regressed_at
    END;
END;
