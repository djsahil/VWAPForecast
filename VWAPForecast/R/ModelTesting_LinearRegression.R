
# VWAP EOD Forecasting with Rolling 1-Month Window (Fully Annotated Version)
# Predicts end-of-day VWAP using early-day intraday data (up to 11:30 AM)
# Tracks R², MSE, MAE; suppresses verbose read_csv output; fully documented

# --- INSTALL REQUIRED LIBRARIES (Run once) ---
required_packages <- c("tidyverse", "lubridate", "broom", "MASS", "Metrics", "scales")
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages)) install.packages(new_packages)

# --- LIBRARIES: LOAD CORE TOOLKITS ---
library(tidyverse)     # Data plots library
library(lubridate)     # Date and time handling
library(broom)         # Consolidated model summaries
library(MASS)          # Stepwise regression via AIC - used in class
library(Metrics)       # Error metrics: MAE, MSE
library(scales)        # Number formatting for axis labels - easier to read

# --- CONFIGURATION ---
symbol <- "SPY"                                  # Stock/ETF to analyze
years_to_include <- 2020:2025                    # Historical range
data_folder <- "../polygon_data"                 # Input directory with CSV files
output_folder <- "VWAP_LinearModel_Output"       # Output folder
dir.create(output_folder, showWarnings = FALSE)

target_column <- "vwap_eod"                      # Our target variable = end-of-day VWAP
lookback_window_days <- 21                       # Rolling training window (21 past days)
session_start_hour <- 9.5                        # Market open (9:30 AM)
session_end_hour <- 16.0                         # Market close (4:00 PM)
feature_end_hour <- 11.5                         # Use bars only up to 11:30 AM

# --- LOAD DATA WITHOUT PRINTING COLUMN SPECS ---
file_paths <- paste0(data_folder, "/", symbol, "_", years_to_include, ".csv")
raw_data <- map_df(file_paths, ~ read_csv(.x, show_col_types = FALSE))

# --- FEATURE ENGINEERING ---

# Clean timestamps and compute decimal time
intraday_data <- raw_data %>%
  mutate(
    timestamp = ymd_hms(timestamp),
    date = as.Date(date),
    decimal_hour = hour(timestamp) + minute(timestamp) / 60
  ) %>%
  filter(decimal_hour >= session_start_hour & decimal_hour <= session_end_hour) %>%
  arrange(timestamp) %>%
  group_by(date) %>%
  mutate(lagged_close = lag(close)) %>%
  ungroup()

# Extract end-of-day VWAP (used as target for prediction)
vwap_targets <- intraday_data %>%
  group_by(date) %>%
  summarize(!!target_column := last(vwap), .groups = "drop")

# Extract early features available up to 11:30 AM
early_features <- intraday_data %>%
  filter(decimal_hour <= feature_end_hour) %>%
  group_by(date) %>%
  summarize(
    lagged_close = last(lagged_close),
    total_volume = sum(volume),
    cumulative_volume = last(cumulative_volume),
    price_change_since_open = last(close) - first(open),
    macro_event_day = max(macro_event_day),
    .groups = "drop"
  )

# Join features and target
modeling_dataset <- inner_join(early_features, vwap_targets, by = "date") %>%
  drop_na(lagged_close, !!sym(target_column))

# --- TRAINING LOOP (Rolling Window Forecasting) ---

# Loop over days, simulate real-time prediction using past 21 days only
all_dates <- sort(modeling_dataset$date)
forecast_results <- list()
forecast_metrics <- tibble(date = as.Date(character()), MSE = double(), MAE = double(), R2 = double())

for (i in (lookback_window_days + 1):length(all_dates)) {
  test_date <- all_dates[i]
  train_dates <- all_dates[(i - lookback_window_days):(i - 1)]

  # Subset for training and today's test row
  training_data <- modeling_dataset %>% filter(date %in% train_dates)
  test_day_data <- modeling_dataset %>% filter(date == test_date)

  if (nrow(training_data) < 10 || nrow(test_day_data) == 0) next

  # Define and fit model using stepwise AIC
  model_formula <- as.formula(paste(target_column, "~ ."))
  training_subset <- training_data[, !(names(training_data) %in% "date")]

  base_model <- lm(model_formula, data = training_subset)
  selected_model <- stepAIC(base_model, direction = "both", trace = FALSE, k = log(nrow(training_subset)))

  # Predict current day
  test_day_data$predicted_vwap <- predict(selected_model, newdata = test_day_data)

  # Store predictions
  forecast_results[[as.character(test_date)]] <- test_day_data[, c("date", target_column, "predicted_vwap")]

  # Capture performance metrics
  forecast_metrics <- forecast_metrics %>%
    add_row(
      date = test_date,
      MSE = mse(test_day_data[[target_column]], test_day_data$predicted_vwap),
      MAE = mae(test_day_data[[target_column]], test_day_data$predicted_vwap),
      R2 = summary(selected_model)$r.squared
    )
}

# --- COMBINE & PLOT RESULTS ---
combined_predictions <- bind_rows(forecast_results)

# Scatter Plot: Actual vs Predicted EOD VWAP (with formatted axes)
ggplot(combined_predictions, aes(x = .data[[target_column]], y = predicted_vwap)) +
  geom_point(alpha = 0.6) +
  geom_abline(slope = 1, intercept = 0, color = "gray", linetype = "dashed") +
  labs(
    title = paste(symbol, "- Predicted vs Actual EOD VWAP"),
    subtitle = "Using early-day features through 11:30 AM",
    x = "Actual End-of-Day VWAP (USD)",
    y = "Predicted End-of-Day VWAP (USD)"
  ) +
  scale_x_continuous(labels = label_number(accuracy = 0.01)) +
  scale_y_continuous(labels = label_number(accuracy = 0.01)) +
  theme_minimal()

# Time Series Overlay: Most Recent 22 Days
recent_predictions <- combined_predictions %>%
  arrange(date) %>%
  tail(22)

ggplot(recent_predictions, aes(x = date)) +
  geom_line(aes(y = .data[[target_column]], color = "Actual VWAP"), linewidth = 1) +
  geom_line(aes(y = predicted_vwap, color = "Predicted VWAP"), linewidth = 1, linetype = "dashed") +
  labs(
    title = paste(symbol, "- Recent VWAP Forecasts"),
    subtitle = "Last 21 Days + Today",
    x = "Date", y = "VWAP",
    color = "Legend"
  ) +
  scale_color_manual(values = c("Actual VWAP" = "steelblue", "Predicted VWAP" = "firebrick")) +
  scale_y_continuous(labels = label_number(accuracy = 0.01)) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# R² Line Chart Over Time
ggplot(forecast_metrics, aes(x = date, y = R2)) +
  geom_line(color = "darkgreen", linewidth = 1) +
  geom_point(color = "darkgreen") +
  labs(
    title = paste(symbol, "- R² of Daily EOD VWAP Forecast Models"),
    x = "Date", y = "R-squared"
  ) +
  theme_minimal()

# View metrics in console
print(forecast_metrics)
