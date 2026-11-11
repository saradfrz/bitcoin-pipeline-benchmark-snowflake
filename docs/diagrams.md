# Editable diagrams and high-resolution exports

The four figures show Snowflake lineage, orchestration, repository organization and ingestion. Behavior is reconciled with the attached SQL.

| Figure | Editable source | Vector | Raster |
|---|---|---|---|
| Table lineage | [draw.io](assets/diagrams/01-lineage.drawio) | [SVG](assets/diagrams/01-lineage.svg) | [PNG](assets/diagrams/01-lineage.png) |
| Orchestration | [draw.io](assets/diagrams/02-orchestration.drawio) | [SVG](assets/diagrams/02-orchestration.svg) | [PNG](assets/diagrams/02-orchestration.png) |
| Repository | [draw.io](assets/diagrams/03-repository.drawio) | [SVG](assets/diagrams/03-repository.svg) | [PNG](assets/diagrams/03-repository.png) |
| Ingestion | [draw.io](assets/diagrams/04-ingestion.drawio) | [SVG](assets/diagrams/04-ingestion.svg) | [PNG](assets/diagrams/04-ingestion.png) |

SVG stays sharp at any zoom. PNG exports are 4,200 pixels wide (3× the 1,400-pixel diagram canvas). The page links to both and to the editable sources. Tables use bronze, silver and gold accents, with bold names. The website shares the portfolio palette: black and white surfaces and text, #ff2bd6 accents and #b80f96 primary buttons. The landing page reuses the portfolio nebula cover and portrait. Diagram layer colors distinguish Bronze, Silver and Gold.

Open a `.drawio` source in diagrams.net or draw.io Desktop. Edit labels, shapes and connectors, then export SVG and PNG with the background included. Keep labels as plain text for portability and use at least a 3× raster scale. Replace the matching assets without changing filenames.

The included exports were rendered from the supplied editable mxGraph XML using its rectangle, label and orthogonal connector geometry, then rasterized with Inkscape. They are not screenshots or embedded low-resolution copies of the PDF figures. Draw.io's own auto-routing can differ slightly when re-exporting an edited file.
