-- Copyright (c) 2019 Digital Asset (Switzerland) GmbH and/or its affiliates. All rights reserved.
-- SPDX-License-Identifier: Apache-2.0

---------------------------------------------------------------------------------------------------
-- V8: party_entries
--
-- This schema version adds a table for tracking party allocation submissions
---------------------------------------------------------------------------------------------------

DROP TABLE parties;

CREATE TABLE party_entries
(
    -- The ledger end at the time when the party allocation was added
    ledger_offset    bigint              not null,
    recorded_at      timestamp           not null, --with timezone
    -- SubmissionId for the party allocation
    submission_id    varchar primary key not null,
    -- participant id that initiated the allocation request
    participant_id   varchar,
    -- party
    party            varchar,
    -- displayName
    display_name     varchar,
    -- The type of entry, 'accept' or 'reject' or 'implicit'
    typ              varchar             not null,
    -- If the type is 'reject', then the rejection reason is set.
    -- Rejection reason is a human-readable description why the change was rejected.
    rejection_reason varchar,
    -- true if the party was added on participantId node that owns the party
    is_local         bool,

    constraint check_party_entry_type
        check (
                (typ = 'accept' and rejection_reason is null) or
                (typ = 'reject' and rejection_reason is not null) or
                (typ = 'implicit' and party is not null)
            )
);

-- Index for retrieving the party allocation entry by submission id per participant
CREATE UNIQUE INDEX idx_party_entries
    ON party_entries (submission_id, participant_id)