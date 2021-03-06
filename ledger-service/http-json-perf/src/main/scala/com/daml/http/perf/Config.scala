// Copyright (c) 2020 Digital Asset (Switzerland) GmbH and/or its affiliates. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

package com.daml.http.perf

import java.io.File

import com.daml.jwt.JwtDecoder
import com.daml.jwt.domain.Jwt
import scopt.RenderingMode

import scala.concurrent.duration.{Duration, FiniteDuration}

private[perf] final case class Config(
    scenario: String,
    dars: List[File],
    jwt: Jwt,
    reportsDir: Option[File],
    maxDuration: Option[FiniteDuration]
) {
  override def toString: String =
    s"Config(" +
      s"scenario=${this.scenario}, " +
      s"dars=${dars: List[File]}," +
      s"jwt=..., " + // don't print the JWT
      s"reportsDir=${reportsDir: Option[File]}," +
      s"maxDuration=${this.maxDuration: Option[FiniteDuration]}" +
      ")"
}

private[perf] object Config {
  val Empty =
    Config(scenario = "", dars = List.empty, jwt = Jwt(""), reportsDir = None, maxDuration = None)

  def parseConfig(args: Seq[String]): Option[Config] =
    configParser.parse(args, Config.Empty)

  @SuppressWarnings(Array("org.wartremover.warts.NonUnitStatements"))
  private val configParser: scopt.OptionParser[Config] =
    new scopt.OptionParser[Config]("http-json-perf-binary") {
      override def renderingMode: RenderingMode = RenderingMode.OneColumn

      head("JSON API Perf Test Tool")

      help("help").text("Print this usage text")

      opt[String]("scenario")
        .action((x, c) => c.copy(scenario = x))
        .required()
        .text("Performance test scenario to run.")

      opt[Seq[File]]("dars")
        .action((x, c) => c.copy(dars = x.toList))
        .required()
        .text("DAR files to pass to Sandbox.")

      opt[String]("jwt")
        .action((x, c) => c.copy(jwt = Jwt(x)))
        .required()
        .validate(validateJwt)
        .text("JWT token to use when connecting to JSON API.")

      opt[File]("reports-dir")
        .action((x, c) => c.copy(reportsDir = Some(x)))
        .optional()
        .text("Directory where reports generated. If not set, reports will not be generated.")

      opt[Duration]("max-duration")
        .action((x, c) => c.copy(maxDuration = Some(FiniteDuration(x.length, x.unit))))
        .optional()
        .text(s"Optional maximum perf test duration. Default value infinity. Examples: 500ms, 5s, 10min, 1h, 1d.")
    }

  private def validateJwt(s: String): Either[String, Unit] = {
    import scalaz.syntax.show._

    JwtDecoder
      .decode(Jwt(s))
      .bimap(
        error => error.shows,
        _ => ()
      )
      .toEither
  }
}
