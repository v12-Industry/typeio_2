-- Demo projects for manual testing, UAT and the E2E suite. This is not
-- application data: the app's own seed endpoint inserts the reference
-- rows this file depends on, and nothing else.
--
-- Idempotent per project, keyed on the root node's title -- a project
-- someone has since edited is left alone, and a newly added one appears
-- on the next run without disturbing the others. Adding a project is
-- rows in the fixture tables below, not new procedural code.

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM project.node_type WHERE id = 'work')
    OR NOT EXISTS (SELECT 1 FROM project.node_status WHERE id = 'active')
  THEN
    RAISE EXCEPTION
      'Reference data is missing. Start the app and run `make seed-db` first.';
  END IF;
END $$;

CREATE TEMP TABLE demo_project (
    key TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE demo_work (
    project_key TEXT NOT NULL,
    key TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    status TEXT NOT NULL,
    PRIMARY KEY (project_key, key)
) ON COMMIT DROP;

CREATE TEMP TABLE demo_dependency (
    project_key TEXT NOT NULL,
    dependent TEXT NOT NULL,
    dependency TEXT NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE demo_node (
    project_key TEXT NOT NULL,
    key TEXT NOT NULL,
    node_id INT NOT NULL,
    PRIMARY KEY (project_key, key)
) ON COMMIT DROP;

INSERT INTO demo_project (key, title, description) VALUES
    ('api', 'Public API launch', 'Everything the launch is waiting on.'),
    ('warehouse', 'Warehouse migration', 'One long chain, most of it already behind us.'),
    ('design', 'Design system refresh', 'Independent pieces of work that wait on nothing.'),
    ('billing', 'Billing rewrite', 'A diamond: two streams over one shared foundation.'),
    ('mobile', 'Mobile relaunch', 'The large one: several streams over a shared bottleneck.'),
    ('compliance', 'Compliance audit', 'A project nobody has broken into work yet.');

INSERT INTO demo_work (project_key, key, title, description, status) VALUES
    ('api', 'A', 'Publish the launch post', 'Announcement, once there is something to announce.', 'active'),
    ('api', 'B', 'Ship the mobile client', 'The client everyone is actually waiting for.', 'active'),
    ('api', 'C', 'Stabilise the public API', 'Freeze the surface and stop breaking callers.', 'active'),
    ('api', 'D', 'Run the beta programme', 'A dozen friendly teams, in production.', 'active'),
    ('api', 'E', 'Finish the auth service', 'Tokens, refresh, revocation.', 'active'),
    ('api', 'F', 'Open the partner sandbox', 'Somewhere partners can integrate safely.', 'active'),
    ('api', 'G', 'Write the integration guide', 'The document a partner reads first.', 'active'),

    ('warehouse', 'A', 'Decommission the old warehouse', 'The last step, once nothing reads from it.', 'open'),
    ('warehouse', 'B', 'Cut reporting over', 'Point every dashboard at the new tables.', 'open'),
    ('warehouse', 'C', 'Backfill the history', 'Ten years of rows, in batches.', 'active'),
    ('warehouse', 'D', 'Mirror the write path', 'Dual-write until the backfill catches up.', 'closed'),
    ('warehouse', 'E', 'Model the new schema', 'Star schema, agreed with the analysts.', 'closed'),
    ('warehouse', 'F', 'Stand up the cluster', 'Provisioned, monitored, and paid for.', 'closed'),

    ('design', 'A', 'Agree the colour tokens', 'One palette, named and documented.', 'closed'),
    ('design', 'B', 'Rebuild the button set', 'Every variant, one component.', 'active'),
    ('design', 'C', 'Document the spacing scale', 'The scale everything else is measured in.', 'open'),
    ('design', 'D', 'Audit the icon set', 'Find the duplicates and the strays.', 'open'),
    ('design', 'E', 'Ship a dark theme toggle', 'Dropped in favour of following the system.', 'rejected'),

    ('billing', 'A', 'Invoice the new plans', 'Monthly and annual, prorated.', 'open'),
    ('billing', 'B', 'Migrate the legacy plans', 'Everyone still on the old price book.', 'active'),
    ('billing', 'C', 'Rebuild the ledger', 'Double-entry, and reconciled nightly.', 'active'),
    ('billing', 'D', 'Retire the coupon engine', 'Superseded by the discount rules.', 'rejected'),

    ('mobile', 'A', 'Submit to the app stores', 'Two review queues, one release note.', 'open'),
    ('mobile', 'B', 'Run the field trial', 'Fifty devices, four weeks.', 'open'),
    ('mobile', 'C', 'Rebuild the onboarding flow', 'Three screens instead of seven.', 'active'),
    ('mobile', 'D', 'Rewrite the sync engine', 'Offline-first, conflict-aware.', 'active'),
    ('mobile', 'E', 'Replace the crash reporter', 'The one that actually symbolicates.', 'closed'),
    ('mobile', 'F', 'Agree the offline rules', 'What the app may do with no network.', 'closed'),
    ('mobile', 'G', 'Port the design system', 'The tokens, on the phone.', 'active'),
    ('mobile', 'H', 'Rework the settings screen', 'Everything nobody could find.', 'open'),
    ('mobile', 'I', 'Drop the tablet layout', 'Not enough users to carry the cost.', 'rejected'),
    ('mobile', 'J', 'Instrument the funnel', 'Know where people give up.', 'active'),
    ('mobile', 'K', 'Refresh the marketing site', 'The page the store listing points at.', 'open'),
    ('mobile', 'L', 'Pick the release train', 'Fortnightly, with a cut-off everyone believes.', 'closed');

INSERT INTO demo_dependency (project_key, dependent, dependency) VALUES
    ('api', 'A', 'D'),
    ('api', 'D', 'E'),
    ('api', 'B', 'C'),
    ('api', 'C', 'E'),
    ('api', 'F', 'G'),
    ('api', 'F', 'C'),

    ('warehouse', 'A', 'B'),
    ('warehouse', 'B', 'C'),
    ('warehouse', 'C', 'D'),
    ('warehouse', 'D', 'E'),
    ('warehouse', 'E', 'F'),

    ('billing', 'A', 'C'),
    ('billing', 'B', 'C'),

    ('mobile', 'A', 'B'),
    ('mobile', 'B', 'C'),
    ('mobile', 'B', 'D'),
    ('mobile', 'C', 'G'),
    ('mobile', 'D', 'F'),
    ('mobile', 'D', 'E'),
    ('mobile', 'H', 'G'),
    ('mobile', 'J', 'D'),
    ('mobile', 'K', 'C'),
    ('mobile', 'A', 'L');

DO $$
DECLARE
  fixture RECORD;
  new_project_id INT;
BEGIN
  FOR fixture IN SELECT * FROM demo_project ORDER BY key LOOP
    IF EXISTS (SELECT 1 FROM project.node WHERE title = fixture.title) THEN
      RAISE NOTICE 'Skipping %: already present.', fixture.title;
      CONTINUE;
    END IF;

    INSERT INTO project.project DEFAULT VALUES RETURNING id INTO new_project_id;

    INSERT INTO project.node
      (title, description, node_type_id, node_status_id, project_id)
    VALUES
      (fixture.title, fixture.description, 'project_root', 'active', new_project_id);

    WITH inserted AS (
      INSERT INTO project.node
        (title, description, node_type_id, node_status_id, project_id)
      SELECT w.title, w.description, 'work', w.status, new_project_id
      FROM demo_work w
      WHERE w.project_key = fixture.key
      ORDER BY w.key
      RETURNING id, title
    )
    INSERT INTO demo_node (project_key, key, node_id)
    SELECT fixture.key, w.key, inserted.id
    FROM inserted
    JOIN demo_work w
      ON w.project_key = fixture.key AND w.title = inserted.title;

    INSERT INTO project.dependency (node_id, to_node_id)
    SELECT dependent.node_id, dependency.node_id
    FROM demo_dependency d
    JOIN demo_node dependent
      ON dependent.project_key = d.project_key AND dependent.key = d.dependent
    JOIN demo_node dependency
      ON dependency.project_key = d.project_key AND dependency.key = d.dependency
    WHERE d.project_key = fixture.key;

    RAISE NOTICE 'Seeded %.', fixture.title;
  END LOOP;
END $$;

COMMIT;
