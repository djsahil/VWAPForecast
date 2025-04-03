
# VWAP Forecasting Using auto.arima with price_trend and volume as Xreg
# ----------------------------------------------------------------------
# This version of the script includes both `price_trend` and `volume` as exogenous regressors
# in a rolling 21-day SARIMA forecast using `auto.arima`. It also visualizes predicted vs actual
# VWAP over the last 22 days and R² over the full sample.

# --- INSTALL REQUIRED LIBRARIES ---
required_packages <- c("tidyverse", "lubridate", "forecast", "Metrics", "scales", "tseries")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages)) install.packages(new_packages)

# --- LIBRARIES ---
library(tidyverse)
library(lubridate)
library(forecast)
library(Metrics)
library(scales)
library(tseries)

# --- PARAMETERS ---
data_folder <- "../polygon_data"
symbol <- "SPY"
lookback_days <- 21

# --- LOAD DATA ---
files <- list.files(data_folder, pattern = paste0(symbol, "_\\d{4}\\.csv"), full.names = TRUE)
df <- files %>%
  map_dfr(~ suppressMessages(read_csv(.x, show_col_types = FALSE))) %>%
  filter(hour >= 9.5 & hour <= 16) %>%
  mutate(
    timestamp = ymd_hms(timestamp),
    date = as.Date(date)
  )

# --- CALCULATE EOD VWAP & Features ---
daily_features <- df %>%
  group_by(date) %>%
  summarise(
    vwap_eod = last(vwap),
    price_trend = last(close) - first(open),
    volume = sum(volume),
    .groups = "drop"
  ) %>%
  arrange(date)

# --- ROLLING auto.arima FORECAST WITH XREGS ---
dates <- daily_features$date
results <- list()
models_selected <- list()
r2_over_time <- tibble(date = as.Date(character()), r2 = double())

for (i in (lookback_days + 1):length(dates)) {
  train_dates <- dates[(i - lookback_days):(i - 1)]
  test_date <- dates[i]

  train_set <- daily_features %>% filter(date %in% train_dates)
  test_set <- daily_features %>% filter(date == test_date)

  y_train <- train_set$vwap_eod
  x_train <- as.matrix(train_set %>% select(price_trend, volume))
  x_test <- as.matrix(test_set %>% select(price_trend, volume))
  y_test <- test_set$vwap_eod

  # Fit auto.arima
  fit_auto <- tryCatch({
    auto.arima(y_train, xreg = x_train, stepwise = FALSE, approximation = FALSE)
  }, error = function(e) NULL)

  pred_auto <- tryCatch({
    forecast(fit_auto, xreg = x_test, h = 1)$mean[1]
  }, error = function(e) NA)

  r2_val <- tryCatch({
    1 - (y_test - pred_auto)^2 / var(y_train)  # pseudo-R²
  }, error = function(e) NA)

  results[[as.character(test_date)]] <- tibble(
    date = test_date,
    actual = y_test,
    predicted = pred_auto
  )

  r2_over_time <- r2_over_time %>%
    add_row(date = test_date, r2 = r2_val)

  models_selected[[as.character(test_date)]] <- if (!is.null(fit_auto)) arimaorder(fit_auto) else NA
}

# --- EVALUATION ---
eval_df <- bind_rows(results) %>% drop_na()

metrics <- tibble(
  MSE = mse(eval_df$actual, eval_df$predicted),
  MAE = mae(eval_df$actual, eval_df$predicted),
  R2 = 1 - sum((eval_df$actual - eval_df$predicted)^2) / sum((eval_df$actual - mean(eval_df$actual))^2)
)

print(metrics)

# --- MODEL SELECTION LOG ---
model_log <- tibble(
  date = names(models_selected),
  arima_order = sapply(models_selected, function(x) paste0("(", paste(x, collapse = ","), ")"))
)

print("Sample of selected models:")
print(tail(model_log, 22))

# --- PLOT: LAST 22 DAYS ---
eval_recent <- eval_df %>% filter(date >= max(date) - 21)

p1 <- ggplot(eval_recent, aes(x = date)) +
  geom_line(aes(y = actual), color = "black", linewidth = 1, alpha = 0.6) +
  geom_line(aes(y = predicted), color = "darkgreen", linewidth = 1) +
  labs(
    title = "EOD VWAP Forecasting with auto.arima + price_trend + volume",
    subtitle = "Last 22 Trading Days",
    x = "Date", y = "VWAP"
  ) +
  theme_minimal()

print(p1)

# --- PLOT: R² Over Time ---
p2 <- ggplot(r2_over_time, aes(x = date, y = r2)) +
  geom_line(color = "darkblue") +
  geom_point(color = "darkblue", alpha = 0.6) +
  labs(
    title = "R² of auto.arima Forecasts (with Xreg)",
    x = "Date", y = "R-squared"
  ) +
  theme_minimal()

print(p2)
