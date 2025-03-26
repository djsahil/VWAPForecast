
# CSV Schema: Enriched 5-Minute OHLCV Data

Each row in the output CSV files represents one **5-minute interval** for a given symbol and trading day. All timestamps are in **Eastern Time (ET)**, aligned with U.S. market hours.

## Base Columns from Polygon.io

| Column         | Type     | Description                                  |
|----------------|----------|----------------------------------------------|
| `symbol`       | string   | Stock or ETF ticker (e.g., AAPL, SPY)        |
| `timestamp`    | datetime | Datetime of the bar (format: `%Y-%m-%d %H:%M:%S`) |
| `date`         | date     | Date only (format: `%Y-%m-%d`)               |
| `time`         | time     | Time only (format: `%H:%M:%S`)               |
| `hour`         | float    | Decimal representation of the time (e.g., 10.5 = 10:30 AM) |
| `day_of_week`  | integer  | Day of week (0 = Monday, ..., 4 = Friday)    |
| `open`         | float    | Opening price for the interval               |
| `high`         | float    | High price during the interval               |
| `low`          | float    | Low price during the interval                |
| `close`        | float    | Closing price for the interval               |
| `volume`       | float    | Total volume traded during the interval      |

## Engineered Features

| Column               | Type     | Description |
|----------------------|----------|-------------|
| `cumulative_volume`  | float    | Running total of volume for the trading day |
| `price_return`       | float    | Percentage return from the previous close (interval-to-interval) |
| `intraday_volatility`| float    | Expanding standard deviation of `price_return` from market open to current time |
| `price_trend`        | float    | Difference between current close and the open price of the day |
| `time_of_day`        | float    | Duplicate of `hour`, for modeling convenience |
| `macro_event_day`    | integer  | 1 if the day is flagged as a macroeconomic event (CPI, FOMC, NFP, etc.), 0 otherwise |
| `vwap`               | float    | Real-time Volume Weighted Average Price up to that interval |
| `vwap_deviation`     | float    | Difference between `close` and `vwap` (used in signal generation) |

## Notes on Time

- Data includes **pre-market, regular hours, and post-market** (typically from 4:00 AM to 8:00 PM ET).
- Use `hour` or `time_of_day` to filter regular session (e.g., 9.5 ≤ `hour` ≤ 16.0).
- All times are Eastern, with automatic daylight saving time adjustment.

## Example Row (AAPL)

| symbol | timestamp           | close | volume | vwap | vwap_deviation | macro_event_day |
|--------|---------------------|--------|--------|------|----------------|------------------|
| AAPL   | 2022-06-01 10:15:00 | 148.23 | 32000  | 147.89 | 0.34         | 0 |

