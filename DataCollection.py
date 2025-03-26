import requests
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import time
import os

# --- API CONFIGURATION ---
API_KEY_POLYGON = "oUSe4A__ttXGPcxtn0klhLZ0BhuHxYgk"  # Replace with your actual API key
symbols = ["AAPL", "SPY", "PLTR", "XOM"]
interval = "5"  #5 Min Bars
years_back = 5
output_dir = "polygon_data"
os.makedirs(output_dir, exist_ok=True)

# --- HARDCODED MACRO EVENT DATES (used to flag important market days) ---
macro_event_dates = [
    pd.to_datetime("2024-01-11").date(),
    pd.to_datetime("2024-01-31").date(),
    pd.to_datetime("2024-02-02").date(),
    pd.to_datetime("2024-02-13").date(),
    pd.to_datetime("2024-03-01").date(),
    pd.to_datetime("2024-03-12").date(),
    pd.to_datetime("2024-03-20").date(),
]

# --- Generate last N years of U.S. trading days ---
def generate_trading_days(n_years):
    end = datetime.now()
    start = end - timedelta(days=n_years * 365)
    business_days = pd.date_range(start=start, end=end, freq="B")
    return [d.strftime('%Y-%m-%d') for d in business_days]

dates = generate_trading_days(years_back)

# --- Download OHLCV intraday data for one symbol and one date ---
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

# --- Feature Engineering with full commentary ---
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

# --- Main loop across all symbols and dates, with batching ---
for symbol in symbols:
    symbol_data = []
    print(f"\nCollecting 5 years of intraday data for {symbol}...")

    for i, date in enumerate(dates):
        try:
            df = get_intraday_ohlcv(symbol, date, interval)
            if not df.empty:
                enriched = compute_features(df)
                symbol_data.append(enriched)

            # Save batch every 100 trading days
            if i % 100 == 0 and symbol_data:
                part_df = pd.concat(symbol_data)
                part_df.to_csv(f"{output_dir}/{symbol}_part_{i}.csv", index=False)
                print(f"Saved {symbol} part {i} with {len(part_df)} rows.")
                symbol_data = []

            time.sleep(1.1)  # Respect Polygon's API rate limits

        except Exception as e:
            print(f"Error for {symbol} on {date}: {e}")
            continue

    # Final save after loop ends
    if symbol_data:
        final_df = pd.concat(symbol_data)
        final_df.to_csv(f"{output_dir}/{symbol}_last_5_years_features.csv", index=False)
        print(f"Final save: {symbol} | {len(final_df)} rows.")
    else:
        print(f"No data collected for {symbol}.")
