# Deploy to GitHub Pages

## Place the downloads

Put `index.html`, `README.md` and this `deploy_github_pages.md` at the repository root. Extract `docs.zip` at that same root: it contains `docs/` and an empty `.nojekyll` file. Keep your eight PNG files in the root `img/` directory, with their original names.

| File | Location |
|---|---|
| Landing page | `index.html` |
| Screenshots | `img/*.png` |
| Markdown documentation | `docs/*.md` |
| Readable HTML guides | `docs/guides/*.html` |
| Editable diagrams and exports | `docs/assets/diagrams/` |

The landing page embeds its CSS and vector diagram previews. It references screenshots using `img/filename.png`, and companion guides using `docs/guides/`. Downloadable diagram sources remain in `docs/assets/diagrams/`. There is no framework build.

## Publish

1. Commit and push these files to `main` in your GitHub repository.
2. Open **Settings → Pages**.
3. Set Source to **Deploy from a branch**.
4. Select **main** and **/(root)**, then save.
5. Wait for the Pages deployment to succeed and open the URL shown by GitHub.

Use **/(root)** rather than the former `/docs` configuration: Pages needs to serve both `index.html` and the root `img/` folder. For the original repository, the expected URL is `https://saradfrz.github.io/bitcoin-pipeline-benchmark-snowflake/`. Use your own owner/repository path for a fork. This delivery prepares files; it does not publish them.

## Preview

From the repository root run `python -m http.server 8000` and open `http://localhost:8000`. Check the eight screenshots, mobile layout, guide links and SVG/PNG/draw.io downloads. Clicking screenshots opens the originals for zooming. Keep filenames and case exactly as supplied.

## Update

Replace images in `img/`, update their captions if the evidence changes, then commit and push. The HTML and guide metrics are static snapshots; they do not query Snowflake. If maintaining Markdown and HTML companions manually, update both.

For 404s, confirm `main / (root)`, an exact lowercase `index.html`, a successful deployment, and that `img/` and `docs/` were committed. Refresh cached pages after a successful deployment.

Official reference: https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site
