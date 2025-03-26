# VWAP Forecasting: 

This repository contains a Python script that collects and processes 5-minute intraday OHLCV (Open, High, Low, Close, Volume) data for selected U.S. equities using the Polygon.io API.

The goal is to prepare a dataset for research in VWAP forecasting, volume modeling, and intraday trading signal generation.

## Features

For each 5-minute bar extracted per symbol, the script calculates:

- `cumulative_volume`: Volume traded so far in the day
- `price_return`: Return from the previous bar
- `intraday_volatility`: Realized volatility up to the bar
- `price_trend`: Difference from the day's opening price
- `vwap`: Real-time volume-weighted average price
- `vwap_deviation`: Close - VWAP (used in trading signals)
- `time_of_day`: Decimal hour (e.g., 10.5 = 10:30 AM)
- `macro_event_day`: Flag for major macroeconomic events

## Output

One CSV per symbol is saved to the `polygon_data/` directory, containing 5 years of enriched 5-minute bars.
