import sys
from pathlib import Path

sys.path.insert(0, str(Path.cwd() / "src"))
from binance_downloader import BinanceTradeDownloader

folder = Path(r"")

downloader = BinanceTradeDownloader(
    start_date="01/01/2026",
    end_date="09/11/2026",
    volume=str(folder),
)

downloader.run()

csv_files = sorted((folder / "unzipped").glob("*.csv"))
if not csv_files:
    raise FileNotFoundError(f"No CSV files found in {folder / 'unzipped'}")

for csv_path in csv_files:
    downloader.convert_to_parquet(csv_path)

print(f"Processed {len(csv_files)} CSV files. Output folder: {folder / 'parquet'}")