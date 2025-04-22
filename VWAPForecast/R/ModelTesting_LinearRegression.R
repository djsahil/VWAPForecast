
# Dual Linear Regression for EOD Price and Volume with Stepwise Selection
# ------------------------------------------------------------------------
# This script separately models:
# - Close Price (EOD) ~ early-day features
# - Volume (EOD) ~ early-day features
# using AIC-based stepwise regression to identify significant explanatory variables.

# --- INSTALL REQUIRED LIBRARIES ---
required_packages <- c("tidyverse", "lubridate", "broom", "scales", "MASS")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages)) install.packages(new_packages)

# --- LOAD LIBRARIES ---
library(tidyverse)
library(lubridate)
library(broom)
library(scales)
library(MASS)

# --- CONFIGURATION ---
data_folder <- "../polygon_data"
symbol <- "SPY"
years_to_include <- 2020:2025
session_start <- 9.5
session_end <- 16.0
feature_cutoff <- 11.5

# --- LOAD DATA ---
file_paths <- paste0(data_folder, "/", symbol, "_", years_to_include, ".csv")
raw_data <- map_df(file_paths, ~ read_csv(.x, show_col_types = FALSE)) %>%
  mutate(
    timestamp = ymd_hms(timestamp),
    date = as.Date(date),
    decimal_hour = hour(timestamp) + minute(timestamp) / 60
  ) %>%
  filter(decimal_hour >= session_start & decimal_hour <= session_end)

# --- LOAD VIX DATA ---
vix_raw <- read_csv("VIX_History.csv", show_col_types = FALSE)
vix_data <- vix_raw %>%
  rename(date = DATE, vix_close = CLOSE) %>%
  mutate(date = mdy(date)) %>%
  arrange(date) %>%
  mutate(vix_change = vix_close - lag(vix_close))

# --- TARGETS ---
targets <- raw_data %>%
  group_by(date) %>%
  summarise(
    close_eod = last(close),
    volume_eod = sum(volume),
    .groups = "drop"
  )

# EARLY-DAY FEATURES from Polygon Data
features <- raw_data %>%
  filter(decimal_hour <= feature_cutoff) %>%
  group_by(date) %>%
  summarise(
    lagged_close = last(lag(close)),
    cumulative_volume = last(cumulative_volume),
    price_trend = last(close) - first(open),
    macro_event_day = max(macro_event_day),
    is_cpi_day = max(is_cpi_day),
    is_nfp_day = max(is_nfp_day),
    is_month_end = max(is_month_end),
    .groups = "drop"
  )

# --- MERGE FEATURES + VIX ---
features_with_vix <- left_join(features, vix_data %>% select(date, vix_close, vix_change), by = "date")

# --- COMBINE DATA ---
df <- inner_join(features_with_vix, targets, by = "date") %>% drop_na()

# --- LINEAR MODEL FOR CLOSE PRICE ---
lm_price <- lm(close_eod ~ ., data = select(df, -date, -volume_eod))
lm_price_step <- stepAIC(lm_price, direction = "both", trace = FALSE)

# --- LINEAR MODEL FOR VOLUME ---
lm_volume <- lm(volume_eod ~ ., data = select(df, -date, -close_eod))
lm_volume_step <- stepAIC(lm_volume, direction = "both", trace = FALSE)

print("Summary of Linear Regression EOD Close Price:")
summary(lm_price_step)

print("Summary of Linear Regression on EOD Volume:")
summary(lm_volume_step)

# --- CLEANED LINEAR MODEL FOR VOLUME (NO lagged_close b/c not sure how its relevant) ---
lm_volume_clean <- lm(volume_eod ~ cumulative_volume + is_cpi_day + is_nfp_day, data = select(df, -date, -close_eod))

cat("\n--- Linear Regression (EOD Volume, Cleaned Variables) ---\n")
summary(lm_volume_clean)

# --- CLEANED LINEAR MODEL FOR VOLUME WITH VIX ---
lm_volume_vix <- lm(volume_eod ~ cumulative_volume + is_cpi_day + is_nfp_day + vix_close + vix_change, data = df)

cat("\n--- Linear Regression (Volume EOD with VIX) ---\n")
summary(lm_volume_vix)
