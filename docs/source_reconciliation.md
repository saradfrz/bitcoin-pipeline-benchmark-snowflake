# Source reconciliation · 9 November 2026

This documentation uses the supplied Snowflake ZIP for executable behavior and the final PDF for experiment observations. Neither is assumed to represent a live deployment. The original report remains a separate reference and is not bundled with this Snowflake-only package.

| Topic | Report / older prose | Supplied SQL | Documentation decision |
|---|---|---|---|
| Landing DQ | PDF §§4.3/4.6 says removed | Both roots call `dq_landing_*`, which invokes `DQ_LANDING_SCOPE` | Show landing DQ in Snowflake diagrams and instructions |
| Pre-summary DQ | Old guide describes a baseline gate | No such task in either graph | Remove the obsolete operational instructions |
| Baseline table | PDF mentions auxiliary audit inventory | No baseline dependency in supplied procedures | Do not draw it as required or claim it is updated |
| Summary DQ | Old guide promises trade-count reconciliation | Procedure checks daily row coverage only | State the narrower implemented guarantee |
| Recovery graphs | Old guide names separate recovery tasks | Current recovery demo uses ordinary DELTA | Document the existing DELTA demo |
| Retention | Report proposes 90 days + cold storage | Executable pruning uses 366 days | Separate proposal from implementation |
| Paths | Old retention guide uses `/snowflake/` | Deployment reads repository-root paths | Correct the documentation paths |
| Scope | Old examples use `USING CONFIG` | Roots derive dates from stage / UTC today | Do not imply runtime custom-date filtering |

The diagrams cover Snowflake table lineage, orchestration, repository responsibilities and ingestion. They reflect the attached source.

The processing implementation is unchanged. A standalone screenshot demonstration has been added under `debug_sql/demo/`; it is not part of either task graph.
