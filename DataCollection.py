"""
Intraday OHLCV Feature Engineering Script for VWAP Forecasting
--------------------------------------------------------------

Author: Sahil Shah
Course: Financial Time Series (MQF)
Project: VWAP Forecasting and Trading Signal Generation
Data Source: Polygon.io (https://polygon.io)

Description:
------------
This script automates the process of downloading and enriching intraday OHLCV
(Open, High, Low, Close, Volume) data at 5-minute frequency for selected equities
over the past 5 years. The goal is to prepare data for predictive modeling of
VWAP and related trading strategies.

Key Features Created per Interval:
----------------------------------
- cumulative_volume: Intraday volume from market open
- price_return: Percentage return since last interval
- intraday_volatility: Expanding standard deviation of returns
- price_trend: Difference between current close and daily open
- time_of_day: Decimal hour representation of the bar
- day_of_week: 0 = Monday, 4 = Friday
- vwap: Real-time volume-weighted average price
- vwap_deviation: Close minus VWAP (used for trading signal logic)
- macro_event_day: Binary flag for major macroeconomic news days

Script Behavior:
----------------
1. Connects to the Polygon.io API.
2. Downloads 5-minute OHLCV bars for each symbol and each U.S. trading day over the past 5 years.
3. Performs feature engineering and tagging of macro event days.
4. Saves the enriched data to CSV files, chunked by calendar year.
5. Runs each symbol’s data pipeline in parallel using multithreading (max 4 concurrent threads).
"""

import requests
import pandas as pd
from datetime import datetime, timedelta
import time
import os
import concurrent.futures

# --- LOAD API KEY FROM FILE ---
with open("./api_config/polygon_api_key.txt", "r") as f:
    API_KEY_POLYGON = f.read().strip()

# --- CONFIGURATION ---
symbols = ["AAPL", "SPY", "PLTR", "XOM"]
interval = "5"  # 5 Min Bars
years_back = 5
output_dir = "polygon_data"
os.makedirs(output_dir, exist_ok=True)

# Max number of threads to run in parallel
MAX_THREADS = min(4, len(symbols))

# --- HARDCODED MACRO EVENT DATES (used to flag important market days) ---
# NEED TO REPLACE WITH DATES FROM FRED or etc.
macro_event_dates = [
    pd.to_datetime("2024-01-11").date(),
    pd.to_datetime("2024-01-31").date(),
    pd.to_datetime("2024-02-02").date(),
    pd.to_datetime("2024-02-13").date(),
    pd.to_datetime("2024-03-01").date(),
    pd.to_datetime("2024-03-12").date(),
    pd.to_datetime("2024-03-20").date(),
]

# --- Function to Generate last N years of U.S. trading days ---
def generate_trading_days(n_years):
    end = datetime.now()
    start = end - timedelta(days=n_years * 365)
    business_days = pd.date_range(start=start, end=end, freq="B")
    return [d.strftime('%Y-%m-%d') for d in business_days]

dates = generate_trading_days(years_back)

# --- Function to Download OHLCV intraday data for one symbol and one date ---
def get_intraday_ohlcv(symbol, date, interval="5"):
    url = f"https://api.polygon.io/v2/aggs/ticker/{symbol}/range/{interval}/minute/{date}/{date}"
    params = {
        "adjusted": "true",
        "sort": "asc",
        "limit": 50000,
        "apiKey": API_KEY_POLYGON
    }
    response = requests.get(url, params=params)
    if response.status_code != 200:
        print(f"API error for {symbol} on {date}: {response.status_code}")
        return pd.DataFrame()

    data = response.json()
    if "results" not in data:
        return pd.DataFrame()

    df = pd.DataFrame(data["results"])
    df["timestamp"] = pd.to_datetime(df["t"], unit="ms")
    df["symbol"] = symbol
    df["date"] = df["timestamp"].dt.date
    df["time"] = df["timestamp"].dt.time
    df["hour"] = df["timestamp"].dt.hour + df["timestamp"].dt.minute / 60
    df["day_of_week"] = df["timestamp"].dt.weekday
    df.rename(columns={"o": "open", "h": "high", "l": "low", "c": "close", "v": "volume"}, inplace=True)
    return df[["symbol", "timestamp", "date", "time", "hour", "day_of_week", "open", "high", "low", "close", "volume"]]

# --- Feature Engineering  ---
def compute_features(df):
    df.sort_values(['symbol', 'timestamp'], inplace=True)

    # Cumulative volume traded so far during the day
    df['cumulative_volume'] = df.groupby(['symbol', 'date'])['volume'].cumsum()

    # Return since last interval (close-to-close percentage change)
    df['price_return'] = df.groupby(['symbol', 'date'])['close'].pct_change()

    # Realized volatility up to the current time (expanding std dev of returns)
    df['intraday_volatility'] = df.groupby(['symbol', 'date'])['price_return'].transform(lambda x: x.expanding().std())

    # Price trend: difference between current close and the day's opening price
    df['price_trend'] = df['close'] - df.groupby(['symbol', 'date'])['open'].transform('first')

    # Time of day in decimal (e.g., 10:30 AM → 10.5)
    df['time_of_day'] = df['hour']

    # Binary flag for macroeconomic announcement day
    df['macro_event_day'] = df['date'].isin(macro_event_dates).astype(int)

    # VWAP = cumulative (price × volume) / cumulative volume
    df['pv'] = df['close'] * df['volume']
    df['cumulative_pv'] = df.groupby(['symbol', 'date'])['pv'].cumsum()
    df['vwap'] = df['cumulative_pv'] / df['cumulative_volume']

    # VWAP Deviation: actual close minus VWAP
    df['vwap_deviation'] = df['close'] - df['vwap']

    # Drop intermediate columns and rows with NaNs
    return df.drop(columns=["pv", "cumulative_pv"]).dropna()

# --- Worker Function: Process One Symbol (downloads, enriches, saves) ---
def process_symbol(symbol):
    print(f"\n[START] Collecting 5 years of intraday data for {symbol}...")

    year_data = {}  # Dict to hold dataframes grouped by year

    for date in dates:
        try:
            df = get_intraday_ohlcv(symbol, date, interval)
            if df.empty:
                continue

            enriched = compute_features(df)
            year = pd.to_datetime(date).year

            if year not in year_data:
                year_data[year] = []

            year_data[year].append(enriched)

            time.sleep(1.1)  # Avoid rate limits

        except Exception as e:
            print(f"[ERROR] {symbol} on {date}: {e}")
            continue

    # After all dates are processed, write one file per year
    for year, data_chunks in sorted(year_data.items()):
        if data_chunks:
            year_df = pd.concat(data_chunks)
            filepath = f"{output_dir}/{symbol}_{year}.csv"
            year_df.to_csv(filepath, index=False)
            print(f"[SAVED] {symbol} {year} with {len(year_df)} rows.")

    print(f"[DONE] Finished processing {symbol}.")

# --- Multithreading: Run one thread per symbol ---
print("Launching threads for each symbol...\n")

with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_THREADS) as executor:
    futures = [executor.submit(process_symbol, symbol) for symbol in symbols]

    for future in concurrent.futures.as_completed(futures):
        try:
            future.result()
        except Exception as e:
            print(f"[THREAD ERROR] {e}")

print("\nAll symbols processed.")
