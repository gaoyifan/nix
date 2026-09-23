import argparse
import datetime as dt
import os
import sqlite3
import time
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq


def archive(database: Path, directory: Path) -> None:
    if not directory.is_dir() or not os.path.ismount(directory):
        raise RuntimeError(f"archive dataset is not mounted: {directory}")

    directory = directory / "ulogd"
    directory.mkdir(mode=0o700, exist_ok=True)
    db = sqlite3.connect(database, timeout=30)
    columns = db.execute("PRAGMA table_info(flows)").fetchall()
    schema = pa.schema(
        (name, pa.string() if declared_type == "TEXT" else pa.int64()) for _, name, declared_type, *_ in columns
    )
    today = dt.datetime.now(dt.UTC).date()
    cutoff = int(dt.datetime.combine(today, dt.time(), dt.UTC).timestamp())

    def finish(path: Path) -> None:
        day, watermark = path.name.removesuffix(".pending.parquet").split(".to-")
        start = int(dt.datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=dt.UTC).timestamp())
        end = start + 86400
        expected = pq.ParquetFile(path).metadata.num_rows
        remaining = db.execute(
            "SELECT count(*) FROM flows WHERE flow_end_sec >= ? AND flow_end_sec < ? AND rowid <= ?",
            (start, end, int(watermark)),
        ).fetchone()[0]
        if remaining > expected:
            raise RuntimeError(f"archive has fewer rows than SQLite for {day}")
        while True:
            deleted = db.execute(
                "DELETE FROM flows WHERE rowid IN "
                "(SELECT rowid FROM flows WHERE flow_end_sec >= ? AND flow_end_sec < ? "
                "AND rowid <= ? LIMIT 10000)",
                (start, end, int(watermark)),
            ).rowcount
            db.commit()
            if not deleted:
                break
            time.sleep(0.01)
        final = directory / path.name.replace(".pending.parquet", ".parquet")
        path.replace(final)
        print(f"archived {day}: {expected} flows, {final.stat().st_size} bytes", flush=True)

    for pending in sorted(directory.glob("*.pending.parquet")):
        finish(pending)
    for temporary in directory.glob("*.tmp"):
        temporary.unlink()

    while True:
        first = db.execute(
            "SELECT flow_end_sec FROM flows WHERE flow_end_sec < ? ORDER BY flow_end_sec LIMIT 1",
            (cutoff,),
        ).fetchone()
        if first is None:
            break
        day = dt.datetime.fromtimestamp(first[0], dt.UTC).date()
        start = int(dt.datetime.combine(day, dt.time(), dt.UTC).timestamp())
        end = start + 86400
        watermark = db.execute(
            "SELECT max(rowid) FROM flows WHERE flow_end_sec >= ? AND flow_end_sec < ?",
            (start, end),
        ).fetchone()[0]
        stem = f"{day}.to-{watermark}"
        temporary = directory / f"{stem}.tmp"
        pending = directory / f"{stem}.pending.parquet"
        print(f"exporting {day} through rowid {watermark}", flush=True)
        writer = pq.ParquetWriter(temporary, schema, compression="zstd", compression_level=3)
        exported = 0
        try:
            cursor = db.execute(
                "SELECT * FROM flows WHERE flow_end_sec >= ? AND flow_end_sec < ? AND rowid <= ?",
                (start, end, watermark),
            )
            while rows := cursor.fetchmany(50000):
                batch = pa.Table.from_arrays(
                    [pa.array(values, type=field.type) for values, field in zip(zip(*rows), schema)],
                    schema=schema,
                )
                writer.write_table(batch)
                exported += len(rows)
        finally:
            writer.close()
        if pq.ParquetFile(temporary).metadata.num_rows != exported:
            raise RuntimeError(f"Parquet row count mismatch for {day}")
        with temporary.open("rb") as file:
            os.fsync(file.fileno())
        temporary.replace(pending)
        folder = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(folder)
        finally:
            os.close(folder)
        finish(pending)

    expiry = today - dt.timedelta(days=90)
    for path in directory.glob("*.parquet"):
        if ".pending." not in path.name and dt.date.fromisoformat(path.name[:10]) < expiry:
            path.unlink()
    db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    archive(args.database, args.directory)
