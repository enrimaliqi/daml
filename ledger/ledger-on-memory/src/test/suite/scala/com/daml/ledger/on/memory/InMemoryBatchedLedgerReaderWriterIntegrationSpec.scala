// Copyright (c) 2020 Digital Asset (Switzerland) GmbH and/or its affiliates. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

package com.daml.ledger.on.memory

import com.daml.ledger.participant.state.kvutils.ParticipantStateIntegrationSpecBase
import com.daml.ledger.participant.state.kvutils.ParticipantStateIntegrationSpecBase.ParticipantState
import com.daml.ledger.participant.state.kvutils.api.{
  BatchingLedgerWriter,
  BatchingLedgerWriterConfig,
  BatchingQueueFactory,
  KeyValueParticipantState
}
import com.daml.ledger.participant.state.v1.{LedgerId, ParticipantId}
import com.daml.lf.engine.Engine
import com.daml.logging.LoggingContext
import com.daml.metrics.Metrics
import com.daml.resources.ResourceOwner

import scala.concurrent.duration._

class InMemoryBatchedLedgerReaderWriterIntegrationSpec(enableBatching: Boolean = true)
    extends ParticipantStateIntegrationSpecBase(
      s"In-memory ledger/participant with parallel validation ${if (enableBatching) "enabled"
      else "disabled"}") {
  private val batchingLedgerWriterConfig =
    BatchingLedgerWriterConfig(
      enableBatching = enableBatching,
      maxBatchQueueSize = 100,
      maxBatchSizeBytes = 4 * 1024 * 1024 /* 4MB */,
      maxBatchWaitDuration = 100.millis,
      // In-memory ledger doesn't support concurrent commits.
      maxBatchConcurrentCommits = 1
    )

  override val isPersistent: Boolean = false

  override def participantStateFactory(
      ledgerId: Option[LedgerId],
      participantId: ParticipantId,
      testId: String,
      metrics: Metrics,
  )(implicit logCtx: LoggingContext): ResourceOwner[ParticipantState] = {
    new InMemoryBatchedLedgerReaderWriter.SingleParticipantOwner(
      ledgerId,
      participantId,
      metrics = metrics,
      engine = Engine(),
    ).map { readerWriter =>
      val batchingLedgerWriter = new BatchingLedgerWriter(
        BatchingQueueFactory.batchingQueueFrom(batchingLedgerWriterConfig),
        readerWriter)
      new KeyValueParticipantState(readerWriter, batchingLedgerWriter, metrics)
    }
  }
}