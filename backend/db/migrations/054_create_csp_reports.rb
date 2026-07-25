# frozen_string_literal: true

# Aggregated Content-Security-Policy violation reports (issues #315/#317).
#
# One row per distinct (disposition, directive, blocked_uri, document_uri)
# rather than one per POST: the question the admin page answers is "which
# violations are still happening, and are any of them ours?", which needs
# counts and a last-seen stamp, not a firehose. Aggregating also bounds the
# table on a public, unauthenticated endpoint — see CspReports::Record for
# the normalisation and cardinality caps that keep the key space small.
Sequel.migration do
  change do
    create_table(:csp_reports) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      # 'enforce' (the policy blocked it) or 'report' (Report-Only would have).
      column :disposition, :text, null: false
      # The effective directive, normalised to a known CSP directive name.
      column :directive, :text, null: false
      # Origin only ("https://evil.example") or a CSP keyword ("inline",
      # "eval", "data"); paths and query strings are stripped before insert.
      column :blocked_uri, :text, null: false
      # Path only — never the query string, which can carry personal data.
      column :document_uri, :text, null: false
      column :count, :integer, null: false, default: 1
      column :first_seen_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :last_seen_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      # Last-seen detail for triage: source_file, line/column, script_sample,
      # user_agent. Kept as a sample rather than a column each — it's read by
      # a human on one admin page, never queried.
      column :sample, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")

      index %i[disposition directive blocked_uri document_uri], unique: true,
                                                                name: :csp_reports_violation_key
      index Sequel.desc(:last_seen_at), name: :csp_reports_last_seen_at_index
    end
  end
end
