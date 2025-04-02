
# VWAP Panel Charts with Log-Scaled Volume

library(tidyverse)
library(lubridate)
library(patchwork)
library(scales)
library(ggfortify)
library(forecast)


# --- CONFIGURATION ---
symbol <- "SPY"
years <- 2020:2025
data_path <- "../polygon_data"
output_dir <- "research"
dir.create(output_dir, showWarnings = FALSE)

# --- LOAD DATA ---
file_paths <- paste0(data_path, "/", symbol, "_", years, ".csv")
df_all <- file_paths %>%
  map_df(read_csv) %>%
  mutate(
    timestamp = ymd_hms(timestamp),
    date = as.Date(date),
    week = isoweek(date),
    year = year(timestamp),
    hour = hour(timestamp) + minute(timestamp) / 60
  ) %>%
  arrange(timestamp)

# --- FIND A FULL WEEK ---
valid_weeks <- df_all %>%
  group_by(year, week) %>%
  summarise(unique_days = n_distinct(day_of_week), .groups = "drop") %>%
  filter(unique_days == 5) %>%
  slice(1)

week_year <- valid_weeks$year
week_num <- valid_weeks$week

# --- FILTER TO THAT WEEK AND REGULAR HOURS ONLY ---
df_week <- df_all %>%
  filter(
    year == week_year,
    week == week_num,
    day_of_week %in% 0:4,
    hour >= 9.5,
    hour <= 16
  ) %>%
  mutate(
    weekday_label = factor(
      weekdays(date),
      levels = c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")
    )
  )

# --- PLOT EACH WEEKDAY SEPARATELY ---
unique_days <- df_week %>% distinct(date, weekday_label)

for (i in seq_len(nrow(unique_days))) {
  day_data <- df_week %>% filter(date == unique_days$date[i])
  day_name <- unique_days$weekday_label[i]
  plot_file <- paste0(output_dir, "/", symbol, "_", day_name, "_VWAP_vs_Close_Panel.png")

  price_plot <- ggplot(day_data, aes(x = timestamp)) +
    geom_line(aes(y = close, color = "Close Price"), linewidth = 0.8) +
    geom_line(aes(y = vwap, color = "VWAP"), linewidth = 0.8, linetype = "dashed") +
    labs(
      title = paste(symbol, "- VWAP vs Close on", day_name),
      subtitle = paste("Date:", unique_days$date[i]),
      x = NULL, y = "Price (USD)", color = "Line Type"
    ) +
    scale_color_manual(values = c("Close Price" = "steelblue", "VWAP" = "firebrick")) +
    theme_minimal() +
    theme(legend.position = "bottom", axis.text.x = element_blank(), axis.ticks.x = element_blank())

  volume_plot <- ggplot(day_data, aes(x = timestamp, y = volume)) +
    geom_col(fill = "gray70") +
    scale_y_log10(labels = label_number(scale_cut = cut_si("b"))) +
    labs(x = "Timestamp", y = "Volume (log scale)") +
    theme_minimal()

  g <- price_plot / volume_plot + plot_layout(heights = c(3, 1))
  ggsave(filename = plot_file, plot = g, width = 12, height = 8)
}

# --- LAST 30 DAYS PLOT ---
last_30_days <- df_all %>% filter(date >= max(date) - 30)

plot_file_30 <- paste0(output_dir, "/", symbol, "_VWAP_Last30Days_Panel.png")
price_plot <- ggplot(last_30_days, aes(x = timestamp)) +
  geom_line(aes(y = close, color = "Close Price"), linewidth = 0.6) +
  geom_line(aes(y = vwap, color = "VWAP"), linewidth = 0.9) +
  labs(title = paste(symbol, "- VWAP vs Close (Last 30 Trading Days)"),
       x = NULL, y = "Price (USD)", color = "Line Type") +
  scale_color_manual(values = c("Close Price" = "gray50", "VWAP" = "firebrick")) +
  theme_minimal() +
  theme(legend.position = "bottom", axis.text.x = element_blank(), axis.ticks.x = element_blank())

volume_plot <- ggplot(last_30_days, aes(x = timestamp, y = volume)) +
  geom_col(fill = "gray80") +
  scale_y_log10(labels = label_number(scale_cut = cut_si("b"))) +
  labs(x = "Timestamp", y = "Volume (log scale)") +
  theme_minimal()

g <- price_plot / volume_plot + plot_layout(heights = c(3, 1))
ggsave(filename = plot_file_30, plot = g, width = 12, height = 8)

# --- FULL PERIOD PLOT ---
plot_file_full <- paste0(output_dir, "/", symbol, "_VWAP_FullHorizon_Panel.png")
price_plot <- ggplot(df_all, aes(x = timestamp)) +
  geom_line(aes(y = close, color = "Close Price"), linewidth = 0.4) +
  geom_line(aes(y = vwap, color = "VWAP"), linewidth = 0.9) +
  labs(title = paste(symbol, "- VWAP vs Close (Full Horizon)"),
       x = NULL, y = "Price (USD)", color = "Line Type") +
  scale_color_manual(values = c("Close Price" = "gray60", "VWAP" = "firebrick")) +
  theme_minimal() +
  theme(legend.position = "bottom", axis.text.x = element_blank(), axis.ticks.x = element_blank())

volume_plot <- ggplot(df_all, aes(x = timestamp, y = volume)) +
  geom_col(fill = "gray85") +
  scale_y_log10(labels = label_number(scale_cut = cut_si("b"))) +
  labs(x = "Timestamp", y = "Volume (log scale)") +
  theme_minimal()

g <- price_plot / volume_plot + plot_layout(heights = c(3, 1))
ggsave(filename = plot_file_full, plot = g, width = 12, height = 8)


### PRELIM ANALYSIS
# --- FILTER TO TRADING HOURS AND REMOVE NA ---
vwap_series <- last_30_days %>%
  filter(hour >= 9.5, hour <= 16) %>%
  drop_na(vwap) %>%
  pull(vwap)

# --- ACF/PACF PLOTS ---
acf_plot <- autoplot(Acf(vwap_series, lag.max = 40, plot = FALSE)) +
  ggtitle("ACF of VWAP Time Series") +
  theme_minimal() +
  theme(
    panel.grid.major = element_line(color = "gray80"),
    panel.grid.minor = element_blank(),
    axis.text = element_text(color = "black"),
    axis.title = element_text(color = "black"),
    plot.title = element_text(face = "bold")
  )

pacf_plot <- autoplot(Pacf(vwap_series, lag.max = 40, plot = FALSE)) +
  ggtitle("PACF of VWAP Time Series") +
  theme_minimal() +
  theme(
    panel.grid.major = element_line(color = "gray80"),
    panel.grid.minor = element_blank(),
    axis.text = element_text(color = "black"),
    axis.title = element_text(color = "black"),
    plot.title = element_text(face = "bold")
  )

plot(acf_plot)
plot(pacf_plot)

# --- CREATE TIME SERIES OBJECT ---
# Assume ~78 bars per trading day (5-min bars across 6.5 hours)
vwap_ts <- ts(vwap_series, frequency = 78)

# --- STL DECOMPOSITION ---
vwap_stl <- stl(vwap_ts, s.window = "periodic")

# --- PLOT STL OUTPUT ---
stl_plot <- autoplot(vwap_stl) +
  labs(title = paste(symbol, "- STL Decomposition of VWAP"), x = "Bars", y = "VWAP") +
  theme_minimal()

print(stl_plot)
# --- SAVE PLOT ---
ggsave(filename = file.path(output_dir, paste0(symbol, "_VWAP_STL.png")), plot = stl_plot, width = 10, height = 6)
