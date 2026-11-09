"""Download daily Binance Spot trades, unzip, and optionally convert to Parquet."""

import os
import shutil
import time
import zipfile
from datetime import datetime, timedelta
from pathlib import Path

import requests


class BinanceTradeDownloader:
    BASE_URL = "https://data.binance.vision/data/spot/daily/trades"

    def __init__(
        self,
        start_date: str,
        end_date: str,
        volume: str,
        symbol: str = "BTCUSDT",
        sleep_seconds: float = 1.0,
        max_retries: int = 3,
        timeout_seconds: int = 180,
    ):
        self.start_date = datetime.strptime(start_date, "%d/%m/%Y").date()
        self.end_date = datetime.strptime(end_date, "%d/%m/%Y").date()
        if self.start_date > self.end_date:
            raise ValueError("start_date must be on or before end_date")
        if sleep_seconds < 0 or max_retries < 1 or timeout_seconds < 1:
            raise ValueError("Invalid sleep_seconds, max_retries, or timeout_seconds")

        self.symbol = symbol.upper()
        self.sleep_seconds = sleep_seconds
        self.max_retries = max_retries
        self.timeout_seconds = timeout_seconds
        self.zip_dir = Path(volume) / "zipped"
        self.csv_dir = Path(volume) / "unzipped"
        self.zip_dir.mkdir(parents=True, exist_ok=True)
        self.csv_dir.mkdir(parents=True, exist_ok=True)

    def dates(self):
        """Yield every date in the requested range, inclusive."""
        current = self.start_date
        while current <= self.end_date:
            yield current
            current += timedelta(days=1)

    def build_url(self, day):
        """Build the official Binance daily Spot trades URL."""
        filename = f"{self.symbol}-trades-{day:%Y-%m-%d}.zip"
        return f"{self.BASE_URL}/{self.symbol}/{filename}"

    def download_zip(self, day):
        """Download one archive, or reuse the existing file."""
        filename = f"{self.symbol}-trades-{day:%Y-%m-%d}.zip"
        target = self.zip_dir / filename
        partial = self.zip_dir / f"{filename}.part"

        if target.exists() and target.stat().st_size > 0:
            print(f"ZIP exists: {filename}")
            return target

        for attempt in range(1, self.max_retries + 1):
            try:
                with requests.get(
                    self.build_url(day),
                    stream=True,
                    timeout=(15, self.timeout_seconds),
                ) as response:
                    if response.status_code == 404:
                        print(f"Not available (404): {filename}")
                        return None

                    if response.status_code in (429, 500, 502, 503, 504):
                        if attempt < self.max_retries:
                            delay = float(
                                response.headers.get("Retry-After", 5 * attempt)
                            )
                            print(f"HTTP {response.status_code}; retry in {delay}s")
                            time.sleep(delay)
                            continue

                    response.raise_for_status()
                    with partial.open("wb") as output:
                        for chunk in response.iter_content(chunk_size=1024 * 1024):
                            if chunk:
                                output.write(chunk)

                os.replace(partial, target)
                print(f"Downloaded: {filename}")
                return target

            except requests.HTTPError:
                # Do not retry authorization or blocking errors (such as 403/418).
                raise
            except requests.RequestException as error:
                partial.unlink(missing_ok=True)
                if attempt == self.max_retries:
                    raise
                print(f"Download failed ({attempt}/{self.max_retries}): {error}")
                time.sleep(5 * attempt)
            finally:
                # Space out HTTP requests even when a file is unavailable.
                time.sleep(self.sleep_seconds)

        raise RuntimeError(f"Failed to download {filename}")

    def unzip_file(self, zip_path):
        """Extract the CSV to the Volume without loading it all into memory."""
        csv_path = self.csv_dir / f"{zip_path.stem}.csv"
        partial = self.csv_dir / f"{zip_path.stem}.csv.part"

        if csv_path.exists() and csv_path.stat().st_size > 0:
            print(f"CSV exists: {csv_path.name}")
            return csv_path

        try:
            with zipfile.ZipFile(zip_path) as archive:
                csv_members = [name for name in archive.namelist() if name.endswith(".csv")]
                if len(csv_members) != 1:
                    raise ValueError(f"Expected one CSV inside {zip_path.name}")

                with archive.open(csv_members[0]) as source, partial.open("wb") as target:
                    shutil.copyfileobj(source, target)

            os.replace(partial, csv_path)
            print(f"Extracted: {csv_path.name}")
            return csv_path
        finally:
            partial.unlink(missing_ok=True)

    def convert_to_parquet(self, csv_path):
        """Stream a headerless trade CSV into volume/parquet using PyArrow.

        Preserve raw values as strings for the Snowflake Bronze COPY mapping.
        Conversion replaces an existing output only after a successful write.
        Install the optional dependency with: python -m pip install pyarrow
        """
        try:
            import pyarrow as pa
            import pyarrow.csv as arrow_csv
            import pyarrow.parquet as parquet
        except ImportError as error:
            raise ImportError(
                "Parquet conversion requires pyarrow: python -m pip install pyarrow"
            ) from error

        csv_path = Path(csv_path)
        columns = [
            "trade_id", "price", "qty", "quote_qty", "time",
            "is_buyer_maker", "is_best_match",
        ]
        output_dir = self.csv_dir.parent / "parquet"
        output_dir.mkdir(parents=True, exist_ok=True)
        target = output_dir / f"{csv_path.stem}.parquet"
        partial = target.with_suffix(".parquet.part")

        try:
            with arrow_csv.open_csv(
                csv_path,
                read_options=arrow_csv.ReadOptions(
                    column_names=columns, block_size=8 * 1024 * 1024,
                ),
                convert_options=arrow_csv.ConvertOptions(
                    column_types={name: pa.string() for name in columns},
                    strings_can_be_null=False,
                ),
            ) as reader:
                with parquet.ParquetWriter(
                    partial, reader.schema, compression="snappy",
                ) as writer:
                    for batch in reader:
                        writer.write_batch(batch)
            os.replace(partial, target)
            print(f"Converted: {target.name}")
            return target
        finally:
            partial.unlink(missing_ok=True)

    def run(self):
        """Download and extract each day in the configured date range."""
        results = []
        for day in self.dates():
            zip_path = self.download_zip(day)
            if zip_path is not None:
                results.append(self.unzip_file(zip_path))

        print(f"Finished: {len(results)} CSV files available in {self.csv_dir}")
        return results
