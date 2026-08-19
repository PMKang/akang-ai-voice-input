-- Notify on every newly accepted repeat occurrence of an open crash group.
-- The existing notification reason CHECK remains unchanged; the key prefix
-- lets the formatter distinguish this from the first "new" notification.
CREATE TRIGGER crash_reports_after_insert_repeat_notification
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
    'occurrence:' || NEW.report_id,
    NEW.fingerprint,
    NEW.report_id,
    'new',
    NEW.received_at
  FROM crash_groups
  WHERE NEW.kind <> 'test'
    AND crash_groups.fingerprint = NEW.fingerprint
    AND crash_groups.status = 'open';
END;
